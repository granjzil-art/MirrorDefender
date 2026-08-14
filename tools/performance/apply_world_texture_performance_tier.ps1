param(
    [ValidateSet('Audit', 'Apply', 'Rollback')]
    [string]$Mode = 'Audit'
)

$ErrorActionPreference = 'Stop'

$baseScript = Join-Path $PSScriptRoot 'apply_world_texture_limits.ps1'
& $baseScript `
    -Mode $Mode `
    -TargetLimit 1024 `
    -MinimumSourceDimension 2048 `
    -ExcludedRoots @('assets/ui', 'assets/png') `
    -ManifestPath 'tools/performance/world_texture_performance_tier_manifest.json'
