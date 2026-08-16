[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Rollback')]
    [string]$Mode = 'Audit'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$BatchRoot = Join-Path $WorkspaceRoot 'outputs\model_decimation_20pct\2026-08-16_all_models_20pct'
$DecimationManifestPath = Join-Path $BatchRoot 'manifest.json'
$SwitchManifestPath = Join-Path $BatchRoot 'production_reference_switch.json'
$ProductionRoots = @('assets', 'resources', 'scenes', 'scripts', 'HexTileset')
$TextExtensions = @('.tscn', '.tres', '.gd', '.cfg', '.godot', '.json')
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Sha256([string]$Text) {
    $bytes = $Utf8NoBom.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-ProductionFiles {
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($rootName in $ProductionRoots) {
        $rootPath = Join-Path $WorkspaceRoot $rootName
        if (-not (Test-Path -LiteralPath $rootPath)) {
            continue
        }
        foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -File) {
            if ($TextExtensions -contains $file.Extension.ToLowerInvariant()) {
                $files.Add($file)
            }
        }
    }
    return @($files)
}

function Get-RelativePath([string]$Path) {
    return [IO.Path]::GetRelativePath($WorkspaceRoot, $Path).Replace('\', '/')
}

function Get-ProcessedEntries {
    if (-not (Test-Path -LiteralPath $DecimationManifestPath)) {
        throw "Decimation manifest not found: $DecimationManifestPath"
    }
    $manifest = Get-Content -LiteralPath $DecimationManifestPath -Raw | ConvertFrom-Json
    return @($manifest.processed | Where-Object { $_.success -eq $true })
}

function Get-ReferenceState {
    param(
        [object[]]$Entries,
        [System.IO.FileInfo[]]$Files
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $lines = [regex]::Split($text, '\r?\n')
        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            $line = $lines[$lineIndex]
            foreach ($entry in $Entries) {
                $source = [string]$entry.source
                $output = [string]$entry.output
                $state = $null
                if ($line.Contains($source, [StringComparison]::OrdinalIgnoreCase)) {
                    $state = 'high'
                }
                elseif ($line.Contains($output, [StringComparison]::OrdinalIgnoreCase)) {
                    $state = 'low'
                }
                if ($null -ne $state) {
                    $records.Add([pscustomobject]@{
                        state = $state
                        file = Get-RelativePath $file.FullName
                        line = $lineIndex + 1
                        source = $source
                        output = $output
                        original_triangles = [int64]$entry.original_triangles
                        reduced_triangles = [int64]$entry.reduced_triangles
                        text = $line.Trim()
                    })
                }
            }
        }
    }
    return @($records)
}

function New-AppliedLine {
    param(
        [string]$Line,
        [string]$Source,
        [string]$Output
    )

    if (-not $Line.TrimStart().StartsWith('[ext_resource ', [StringComparison]::Ordinal)) {
        throw "Refusing to rewrite a non-ext_resource reference: $Line"
    }
    if (-not $Line.Contains('type="PackedScene"', [StringComparison]::Ordinal)) {
        throw "Refusing to rewrite a non-PackedScene reference: $Line"
    }
    $updated = $Line.Replace($Source, $Output, [StringComparison]::OrdinalIgnoreCase)
    # Generated binary .scn files do not own stable committed UIDs. Remove the
    # source model UID so Godot resolves the replacement solely by its exact path.
    $updated = [regex]::Replace($updated, '\s+uid="uid://[^"]+"', '', 1)
    return $updated
}

function Write-JsonFile([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $Utf8NoBom)
}

function Set-DecimationProductionState([bool]$Applied) {
    $text = [IO.File]::ReadAllText($DecimationManifestPath)
    $replacement = '"production_references_modified": ' + $Applied.ToString().ToLowerInvariant()
    $updated = [regex]::Replace(
        $text,
        '"production_references_modified"\s*:\s*(true|false)',
        $replacement,
        1
    )
    if ($updated -eq $text -and -not $text.Contains($replacement, [StringComparison]::Ordinal)) {
        throw 'Could not update production_references_modified in the decimation manifest.'
    }
    [IO.File]::WriteAllText($DecimationManifestPath, $updated, $Utf8NoBom)
}

$entries = Get-ProcessedEntries
$files = Get-ProductionFiles
$stateBefore = Get-ReferenceState -Entries $entries -Files $files

if ($Mode -eq 'Audit') {
    $high = @($stateBefore | Where-Object state -eq 'high')
    $low = @($stateBefore | Where-Object state -eq 'low')
    [pscustomobject]@{
        mode = 'Audit'
        processed_models = $entries.Count
        production_files_scanned = $files.Count
        high_model_references = $high.Count
        low_model_references = $low.Count
        high_model_files = @($high | Select-Object -ExpandProperty file -Unique).Count
        high_model_sources = @($high | Select-Object -ExpandProperty source -Unique).Count
        references = @($stateBefore | Sort-Object file, line, state)
    } | ConvertTo-Json -Depth 8
    exit 0
}

if ($Mode -eq 'Apply') {
    if (Test-Path -LiteralPath $SwitchManifestPath) {
        $existing = Get-Content -LiteralPath $SwitchManifestPath -Raw | ConvertFrom-Json
        if ($existing.status -eq 'applied') {
            $unexpectedHigh = @($stateBefore | Where-Object state -eq 'high')
            if ($unexpectedHigh.Count -gt 0) {
                throw "Switch manifest says applied, but $($unexpectedHigh.Count) high-model references remain. Roll back or inspect manually."
            }
            Set-DecimationProductionState $true
            [pscustomobject]@{
                mode = 'Apply'
                status = 'already_applied'
                manifest = Get-RelativePath $SwitchManifestPath
                low_model_references = @($stateBefore | Where-Object state -eq 'low').Count
            } | ConvertTo-Json -Depth 5
            exit 0
        }
    }

    $highReferences = @($stateBefore | Where-Object state -eq 'high')
    if ($highReferences.Count -eq 0) {
        throw 'No production high-model references were found to apply.'
    }

    $changes = [System.Collections.Generic.List[object]]::new()
    $pendingWrites = [System.Collections.Generic.List[object]]::new()
    foreach ($fileGroup in $highReferences | Group-Object file) {
        $relativePath = [string]$fileGroup.Name
        $absolutePath = Join-Path $WorkspaceRoot $relativePath
        $beforeText = [IO.File]::ReadAllText($absolutePath)
        $afterText = $beforeText
        $lineChanges = [System.Collections.Generic.List[object]]::new()

        foreach ($reference in @($fileGroup.Group | Sort-Object line -Descending)) {
            $beforeLine = [string]$reference.text
            $rawLines = [regex]::Split($afterText, '(?<=\n)')
            $targetIndex = [int]$reference.line - 1
            if ($targetIndex -lt 0 -or $targetIndex -ge $rawLines.Count) {
                throw "Recorded line is outside file: ${relativePath}:$($reference.line)"
            }
            $rawLine = $rawLines[$targetIndex]
            $lineEnding = if ($rawLine.EndsWith("`r`n")) { "`r`n" } elseif ($rawLine.EndsWith("`n")) { "`n" } else { '' }
            $contentLine = $rawLine.Substring(0, $rawLine.Length - $lineEnding.Length)
            $afterLine = New-AppliedLine -Line $contentLine -Source ([string]$reference.source) -Output ([string]$reference.output)
            $rawLines[$targetIndex] = $afterLine + $lineEnding
            $afterText = [string]::Concat($rawLines)
            $lineChanges.Add([pscustomobject]@{
                line = [int]$reference.line
                source = [string]$reference.source
                output = [string]$reference.output
                original_triangles = [int64]$reference.original_triangles
                reduced_triangles = [int64]$reference.reduced_triangles
                before_line = $contentLine
                after_line = $afterLine
            })
        }

        $changes.Add([pscustomobject]@{
            file = $relativePath
            before_sha256 = Get-Sha256 $beforeText
            after_sha256 = Get-Sha256 $afterText
            replacements = @($lineChanges | Sort-Object line)
        })
        $pendingWrites.Add([pscustomobject]@{
            path = $absolutePath
            text = $afterText
        })
    }

    foreach ($write in $pendingWrites) {
        [IO.File]::WriteAllText([string]$write.path, [string]$write.text, $Utf8NoBom)
    }

    $stateAfter = Get-ReferenceState -Entries $entries -Files $files
    $remainingHigh = @($stateAfter | Where-Object state -eq 'high')
    if ($remainingHigh.Count -ne 0) {
        throw "Apply verification failed: $($remainingHigh.Count) high-model references remain."
    }

    $switchManifest = [ordered]@{
        schema_version = 1
        batch = '2026-08-16_all_models_20pct'
        status = 'applied'
        applied_at = (Get-Date).ToString('o')
        decimation_manifest = Get-RelativePath $DecimationManifestPath
        scope = @($ProductionRoots)
        processed_models_available = $entries.Count
        referenced_models_replaced = @($highReferences.source | Sort-Object -Unique).Count
        references_replaced = $highReferences.Count
        files_modified = $changes.Count
        original_triangles_across_references = [int64](($highReferences | Measure-Object original_triangles -Sum).Sum)
        reduced_triangles_across_references = [int64](($highReferences | Measure-Object reduced_triangles -Sum).Sum)
        explicitly_unchanged = @(
            [ordered]@{
                source = 'res://assets/greattree/realistic_tree_gltf/scene.gltf'
                reason = 'user_excluded_realistic_tree'
            }
        )
        changes = @($changes | Sort-Object file)
    }
    Write-JsonFile -Path $SwitchManifestPath -Value $switchManifest
    Set-DecimationProductionState $true

    [pscustomobject]@{
        mode = 'Apply'
        status = 'applied'
        referenced_models_replaced = $switchManifest.referenced_models_replaced
        references_replaced = $switchManifest.references_replaced
        files_modified = $switchManifest.files_modified
        high_model_references_remaining = $remainingHigh.Count
        low_model_references = @($stateAfter | Where-Object state -eq 'low').Count
        manifest = Get-RelativePath $SwitchManifestPath
    } | ConvertTo-Json -Depth 5
    exit 0
}

if (-not (Test-Path -LiteralPath $SwitchManifestPath)) {
    throw "Rollback manifest not found: $SwitchManifestPath"
}
$switchManifest = Get-Content -LiteralPath $SwitchManifestPath -Raw | ConvertFrom-Json
if ($switchManifest.status -eq 'rolled_back') {
    [pscustomobject]@{
        mode = 'Rollback'
        status = 'already_rolled_back'
        manifest = Get-RelativePath $SwitchManifestPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$rollbackWrites = [System.Collections.Generic.List[object]]::new()
foreach ($change in $switchManifest.changes) {
    $absolutePath = Join-Path $WorkspaceRoot ([string]$change.file)
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        throw "Rollback target is missing: $($change.file)"
    }
    $text = [IO.File]::ReadAllText($absolutePath)
    foreach ($replacement in $change.replacements) {
        $afterLine = [string]$replacement.after_line
        $beforeLine = [string]$replacement.before_line
        if (-not $text.Contains($afterLine, [StringComparison]::Ordinal)) {
            throw "Rollback preflight failed because the applied line changed: $($change.file):$($replacement.line)"
        }
        $text = $text.Replace($afterLine, $beforeLine, [StringComparison]::Ordinal)
    }
    $rollbackWrites.Add([pscustomobject]@{
        path = $absolutePath
        text = $text
    })
}

foreach ($write in $rollbackWrites) {
    [IO.File]::WriteAllText([string]$write.path, [string]$write.text, $Utf8NoBom)
}
$switchManifest.status = 'rolled_back'
$switchManifest | Add-Member -NotePropertyName rolled_back_at -NotePropertyValue ((Get-Date).ToString('o')) -Force
Write-JsonFile -Path $SwitchManifestPath -Value $switchManifest
Set-DecimationProductionState $false

$stateAfterRollback = Get-ReferenceState -Entries $entries -Files $files
[pscustomobject]@{
    mode = 'Rollback'
    status = 'rolled_back'
    restored_high_model_references = @($stateAfterRollback | Where-Object state -eq 'high').Count
    low_model_references_remaining = @($stateAfterRollback | Where-Object state -eq 'low').Count
    manifest = Get-RelativePath $SwitchManifestPath
} | ConvertTo-Json -Depth 5
