"""Run QEM fallback for surfaces where meshoptimizer cannot reach 20%."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np

try:
    import fast_simplification
except ImportError as exc:
    raise SystemExit(
        "fast-simplification is required. Install it with: "
        "python -m pip install fast-simplification"
    ) from exc

def split_mapped_attribute_seams(
    geometry_points: np.ndarray,
    original_triangles: np.ndarray,
    original_to_geometry: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Split reduced positions at original UV/normal seams without adding faces."""
    mapped_faces = original_to_geometry[original_triangles]
    valid = (
        (mapped_faces >= 0).all(axis=1)
        & (mapped_faces[:, 0] != mapped_faces[:, 1])
        & (mapped_faces[:, 1] != mapped_faces[:, 2])
        & (mapped_faces[:, 2] != mapped_faces[:, 0])
    )
    mapped_faces = mapped_faces[valid]
    source_faces = original_triangles[valid]
    canonical = np.sort(mapped_faces, axis=1)
    _, unique_indices = np.unique(canonical, axis=0, return_index=True)
    unique_indices.sort()
    mapped_faces = mapped_faces[unique_indices]
    source_faces = source_faces[unique_indices]
    pairs = np.column_stack((mapped_faces.reshape(-1), source_faces.reshape(-1)))
    unique_pairs, pair_inverse = np.unique(pairs, axis=0, return_inverse=True)
    points = geometry_points[unique_pairs[:, 0]]
    representatives = unique_pairs[:, 1].astype(np.int32)
    faces = pair_inverse.reshape((-1, 3)).astype(np.int32)
    return points, faces, representatives


def voxel_cluster_fallback(
    points: np.ndarray, triangles: np.ndarray, target_count: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Topology-independent fallback that preserves source corner attributes."""
    bounds_min = points.min(axis=0)
    diagonal = float(np.linalg.norm(np.ptp(points, axis=0)))

    def cluster(cell_size: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        keys = np.floor((points - bounds_min) / cell_size).astype(np.int64)
        _, inverse = np.unique(keys, axis=0, return_inverse=True)
        cluster_count = int(inverse.max()) + 1
        counts = np.bincount(inverse, minlength=cluster_count).astype(np.float64)
        centroids = np.column_stack(
            [np.bincount(inverse, weights=points[:, axis], minlength=cluster_count) / counts for axis in range(3)]
        )
        clustered_faces = inverse[triangles]
        valid = (
            (clustered_faces[:, 0] != clustered_faces[:, 1])
            & (clustered_faces[:, 1] != clustered_faces[:, 2])
            & (clustered_faces[:, 2] != clustered_faces[:, 0])
        )
        clustered_faces = clustered_faces[valid]
        original_faces = triangles[valid]
        if clustered_faces.size == 0:
            return np.empty((0, 3)), np.empty((0, 3), dtype=np.int32), np.empty(0, dtype=np.int32)
        canonical = np.sort(clustered_faces, axis=1)
        _, unique_indices = np.unique(canonical, axis=0, return_index=True)
        unique_indices.sort()
        clustered_faces = clustered_faces[unique_indices]
        original_faces = original_faces[unique_indices]

        # Split a clustered position when source corner attributes differ. The
        # geometry is still collapsed, but Godot can copy the exact UV/normal/
        # tangent data from each representative source vertex without smearing
        # seams across the reduced model.
        pairs = np.column_stack((clustered_faces.reshape(-1), original_faces.reshape(-1)))
        unique_pairs, pair_inverse = np.unique(pairs, axis=0, return_inverse=True)
        out_points = centroids[unique_pairs[:, 0]]
        representatives = unique_pairs[:, 1].astype(np.int32)
        out_faces = pair_inverse.reshape((-1, 3)).astype(np.int32)
        return out_points, out_faces, representatives

    low = max(diagonal * 1.0e-7, 1.0e-9)
    high = max(diagonal * 2.0, 1.0e-6)
    best = None
    for _ in range(36):
        middle = float(np.sqrt(low * high))
        candidate = cluster(middle)
        face_count = candidate[1].shape[0]
        if face_count > target_count:
            low = middle
        else:
            high = middle
            if face_count > 0 and (best is None or face_count > best[1].shape[0]):
                best = candidate
    if best is None:
        best = cluster(high)
    if best[1].shape[0] == 0:
        raise RuntimeError("Voxel fallback collapsed the entire surface")
    return best


def simplify_request(input_path: Path, output_dir: Path) -> dict[str, object]:
    request = json.loads(input_path.read_text(encoding="utf-8"))
    points = np.asarray(request["vertices"], dtype=np.float64).reshape((-1, 3))
    triangles = np.asarray(request["triangles"], dtype=np.int32).reshape((-1, 3))
    target_count = int(request["target_triangles"])

    # Imported meshes often split the same geometric point at UV or hard-normal
    # seams. Topology-aware simplifiers then see every seam as a border and can
    # stop well above the target. Weld only coincident positions for the QEM
    # topology; the returned mapping still points back to the original vertices
    # so Godot can restore the retained vertex attributes afterward.
    diagonal = float(np.linalg.norm(np.ptp(points, axis=0)))
    weld_tolerance = max(diagonal * 1.0e-7, 1.0e-9)
    weld_keys = np.rint((points - points.min(axis=0)) / weld_tolerance).astype(np.int64)
    _, welded_indices, original_to_welded = np.unique(
        weld_keys, axis=0, return_index=True, return_inverse=True
    )
    welded_points = np.ascontiguousarray(points[welded_indices])
    welded_triangles = original_to_welded[triangles]
    nondegenerate = (
        (welded_triangles[:, 0] != welded_triangles[:, 1])
        & (welded_triangles[:, 1] != welded_triangles[:, 2])
        & (welded_triangles[:, 2] != welded_triangles[:, 0])
    )
    welded_triangles = np.ascontiguousarray(welded_triangles[nondegenerate].astype(np.int32))

    best = None
    for requested_target in (target_count, int(target_count * 0.75), int(target_count * 0.5), int(target_count * 0.25)):
        for aggressiveness in (7.0, 10.0, 15.0, 30.0, 50.0, 100.0):
            out_points, out_faces, collapses = fast_simplification.simplify(
                welded_points,
                welded_triangles,
                target_count=max(1, requested_target),
                agg=aggressiveness,
                preserve_border=False,
                return_collapses=True,
            )
            replay_points, replay_faces, mapping = fast_simplification.replay_simplification(
                welded_points, welded_triangles, collapses
            )
            if out_points.shape != replay_points.shape or not np.array_equal(out_faces, replay_faces):
                raise RuntimeError("Simplifier/replay topology mismatch; attribute mapping is unsafe")
            candidate = (out_points, out_faces, mapping, aggressiveness)
            if best is None or out_faces.shape[0] < best[1].shape[0]:
                best = candidate
            if out_faces.shape[0] <= target_count:
                break
        if best is not None and best[1].shape[0] <= target_count:
            break

    assert best is not None
    out_points, out_faces, welded_to_reduced, aggressiveness = best
    engine = f"fast-simplification {fast_simplification.__version__}"
    original_to_reduced = welded_to_reduced[original_to_welded]
    out_points, out_faces, reduced_to_original = split_mapped_attribute_seams(
        out_points, triangles, original_to_reduced
    )
    if out_faces.shape[0] > target_count:
        out_points, out_faces, reduced_to_original = voxel_cluster_fallback(points, triangles, target_count)
        engine = "voxel-cluster attribute-preserving fallback"

    output = {
        "key": request["key"],
        "source": request["source"],
        "node_path": request["node_path"],
        "surface": request["surface"],
        "engine": engine,
        "aggressiveness": aggressiveness,
        "original_vertices": int(points.shape[0]),
        "welded_vertices": int(welded_points.shape[0]),
        "original_triangles": int(triangles.shape[0]),
        "target_triangles": target_count,
        "reduced_vertices": int(out_points.shape[0]),
        "reduced_triangles": int(out_faces.shape[0]),
        "vertices": out_points.astype(np.float32).reshape(-1).tolist(),
        "triangles": out_faces.astype(np.int32).reshape(-1).tolist(),
        "reduced_to_original": reduced_to_original.tolist(),
    }
    output_path = output_dir / f"{request['key']}.json"
    output_path.write_text(json.dumps(output, separators=(",", ":")), encoding="utf-8")
    return {key: value for key, value in output.items() if key not in {"vertices", "triangles", "reduced_to_original"}}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    results = [simplify_request(path, args.output_dir) for path in sorted(args.input_dir.glob("*.json"))]
    print(json.dumps({"processed": len(results), "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
