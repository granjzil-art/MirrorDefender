param(
    [ValidateSet('Audit', 'Apply', 'Rollback')]
    [string]$Mode = 'Audit',
    [ValidateRange(256, 8192)]
    [int]$TargetLimit = 2048,
    [ValidateRange(512, 32768)]
    [int]$MinimumSourceDimension = 4096,
    [string[]]$ExcludedRoots = @('assets/ui', 'assets/png'),
    [string]$ManifestPath = 'tools/performance/world_texture_limit_manifest.json'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$assetRoot = Join-Path $projectRoot 'assets'
$manifestFullPath = Join-Path $projectRoot ($ManifestPath -replace '/', [IO.Path]::DirectorySeparatorChar)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$limitPattern = [regex]'(?m)^(process/size_limit=)(\d+)(\r?)$'


function Convert-ToRelativeProjectPath {
    param([string]$FullPath)

    $resolved = [IO.Path]::GetFullPath($FullPath)
    if (-not $resolved.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project: $resolved"
    }
    return $resolved.Substring($projectRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}


function Convert-ToFullProjectPath {
    param([string]$RelativePath)

    return Join-Path $projectRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}


function Read-BigEndianUInt16 {
    param([IO.Stream]$Stream)

    $high = $Stream.ReadByte()
    $low = $Stream.ReadByte()
    if ($high -lt 0 -or $low -lt 0) {
        return -1
    }
    return ($high -shl 8) -bor $low
}


function Get-ImageDimensions {
    param([string]$Path)

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($extension -eq '.png') {
            $header = New-Object byte[] 24
            if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
                return $null
            }
            if (
                $header[0] -ne 0x89 -or $header[1] -ne 0x50 -or
                $header[2] -ne 0x4e -or $header[3] -ne 0x47
            ) {
                return $null
            }
            $width = (
                ([int]$header[16] -shl 24) -bor ([int]$header[17] -shl 16) -bor
                ([int]$header[18] -shl 8) -bor [int]$header[19]
            )
            $height = (
                ([int]$header[20] -shl 24) -bor ([int]$header[21] -shl 16) -bor
                ([int]$header[22] -shl 8) -bor [int]$header[23]
            )
            return [pscustomobject]@{ Width = [int]$width; Height = [int]$height }
        }

        if ($extension -notin @('.jpg', '.jpeg')) {
            return $null
        }
        if ($stream.ReadByte() -ne 0xff -or $stream.ReadByte() -ne 0xd8) {
            return $null
        }
        $startOfFrameMarkers = @(0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf)
        while ($stream.Position -lt $stream.Length) {
            $prefix = $stream.ReadByte()
            while ($prefix -ge 0 -and $prefix -ne 0xff) {
                $prefix = $stream.ReadByte()
            }
            if ($prefix -lt 0) {
                break
            }
            $marker = $stream.ReadByte()
            while ($marker -eq 0xff) {
                $marker = $stream.ReadByte()
            }
            if ($marker -lt 0 -or $marker -eq 0xd9 -or $marker -eq 0xda) {
                break
            }
            if ($marker -eq 0x01 -or ($marker -ge 0xd0 -and $marker -le 0xd7)) {
                continue
            }
            $segmentLength = Read-BigEndianUInt16 -Stream $stream
            if ($segmentLength -lt 2) {
                break
            }
            if ($startOfFrameMarkers -contains $marker) {
                if ($stream.ReadByte() -lt 0) {
                    break
                }
                $height = Read-BigEndianUInt16 -Stream $stream
                $width = Read-BigEndianUInt16 -Stream $stream
                if ($width -gt 0 -and $height -gt 0) {
                    return [pscustomobject]@{ Width = [int]$width; Height = [int]$height }
                }
                break
            }
            [void]$stream.Seek($segmentLength - 2, [IO.SeekOrigin]::Current)
        }
        return $null
    }
    finally {
        $stream.Dispose()
    }
}


function Test-IsExcluded {
    param([string]$RelativeSourcePath)

    $normalized = $RelativeSourcePath.Replace('\', '/').Trim('/').ToLowerInvariant()
    foreach ($excludedRoot in $ExcludedRoots) {
        $excluded = $excludedRoot.Replace('\', '/').Trim('/').ToLowerInvariant()
        if ($normalized -eq $excluded -or $normalized.StartsWith("$excluded/")) {
            return $true
        }
    }
    return $false
}


function Get-ImportLimit {
    param([string]$ImportPath)

    $content = [IO.File]::ReadAllText($ImportPath)
    $match = $limitPattern.Match($content)
    if (-not $match.Success) {
        return $null
    }
    return [int]$match.Groups[2].Value
}


function Get-RuntimeCacheSnapshot {
    param([string]$ImportPath)

    $content = [IO.File]::ReadAllText($ImportPath)
    $match = [regex]::Match($content, 'path\.s3tc="res://([^"]+)"')
    if (-not $match.Success) {
        $match = [regex]::Match($content, '(?m)^path="res://([^"]+)"')
    }
    if (-not $match.Success) {
        return [pscustomobject]@{ Path = ''; Bytes = 0L }
    }
    $relativePath = $match.Groups[1].Value.Replace('\', '/')
    $fullPath = Convert-ToFullProjectPath -RelativePath $relativePath
    $bytes = if (Test-Path -LiteralPath $fullPath) {
        [long](Get-Item -LiteralPath $fullPath).Length
    }
    else {
        0L
    }
    return [pscustomobject]@{ Path = $relativePath; Bytes = $bytes }
}


function Set-ImportLimit {
    param(
        [string]$ImportPath,
        [int]$Limit
    )

    $content = [IO.File]::ReadAllText($ImportPath)
    $match = $limitPattern.Match($content)
    if (-not $match.Success) {
        throw "Missing process/size_limit in $ImportPath"
    }
    $evaluator = [Text.RegularExpressions.MatchEvaluator]{
        param($value)
        return $value.Groups[1].Value + $Limit + $value.Groups[3].Value
    }
    $updated = $limitPattern.Replace($content, $evaluator, 1)
    if ($updated -eq $content) {
        return $false
    }
    [IO.File]::WriteAllText($ImportPath, $updated, $utf8NoBom)
    return $true
}


function Get-Candidates {
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($importFile in Get-ChildItem -LiteralPath $assetRoot -Recurse -File -Filter '*.import') {
        $sourcePath = $importFile.FullName.Substring(0, $importFile.FullName.Length - '.import'.Length)
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }
        $extension = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        if ($extension -notin @('.png', '.jpg', '.jpeg')) {
            continue
        }
        $relativeSource = Convert-ToRelativeProjectPath -FullPath $sourcePath
        if (Test-IsExcluded -RelativeSourcePath $relativeSource) {
            continue
        }
        $dimensions = Get-ImageDimensions -Path $sourcePath
        if ($null -eq $dimensions) {
            Write-Warning "Unable to read image dimensions: $relativeSource"
            continue
        }
        if ([Math]::Max($dimensions.Width, $dimensions.Height) -lt $MinimumSourceDimension) {
            continue
        }
        $currentLimit = Get-ImportLimit -ImportPath $importFile.FullName
        if ($null -eq $currentLimit) {
            Write-Warning "Missing process/size_limit: $(Convert-ToRelativeProjectPath -FullPath $importFile.FullName)"
            continue
        }
        $results.Add([pscustomobject][ordered]@{
            source_path = $relativeSource
            import_path = Convert-ToRelativeProjectPath -FullPath $importFile.FullName
            width = [int]$dimensions.Width
            height = [int]$dimensions.Height
            current_limit = [int]$currentLimit
        })
    }
    return @($results | Sort-Object source_path)
}


function Write-AuditSummary {
    param([array]$Candidates)

    $unlimited = @($Candidates | Where-Object { $_.current_limit -eq 0 }).Count
    $atOrBelowTarget = @($Candidates | Where-Object {
        $_.current_limit -gt 0 -and $_.current_limit -le $TargetLimit
    }).Count
    Write-Output "Mode=$Mode Candidates=$($Candidates.Count) Unlimited=$unlimited AtOrBelowTarget=$atOrBelowTarget Target=$TargetLimit"
    $Candidates |
        Group-Object { ($_.source_path -split '/')[1] } |
        Sort-Object Count -Descending |
        ForEach-Object { Write-Output ("Category={0} Count={1}" -f $_.Name, $_.Count) }
}


if ($Mode -eq 'Rollback') {
    if (-not (Test-Path -LiteralPath $manifestFullPath)) {
        throw "Rollback manifest not found: $manifestFullPath"
    }
    $manifest = [IO.File]::ReadAllText($manifestFullPath) | ConvertFrom-Json
    $updatedCount = 0
    $missingCount = 0
    foreach ($entry in $manifest.entries) {
        $importPath = Convert-ToFullProjectPath -RelativePath ([string]$entry.import_path)
        if (-not (Test-Path -LiteralPath $importPath)) {
            $missingCount += 1
            Write-Warning "Missing import sidecar during rollback: $($entry.import_path)"
            continue
        }
        if (Set-ImportLimit -ImportPath $importPath -Limit ([int]$entry.previous_limit)) {
            $updatedCount += 1
        }
    }
    Write-Output "Mode=Rollback Entries=$($manifest.entries.Count) Updated=$updatedCount Missing=$missingCount"
    exit 0
}

$candidates = Get-Candidates
Write-AuditSummary -Candidates $candidates
if ($Mode -eq 'Audit') {
    exit 0
}

$previousByImportPath = @{}
if (Test-Path -LiteralPath $manifestFullPath) {
    $previousManifest = [IO.File]::ReadAllText($manifestFullPath) | ConvertFrom-Json
    foreach ($entry in $previousManifest.entries) {
        $previousByImportPath[[string]$entry.import_path] = $entry
    }
}

$manifestEntries = @()
foreach ($candidate in $candidates) {
    $previousLimit = $candidate.current_limit
    $cacheSnapshot = Get-RuntimeCacheSnapshot -ImportPath (
        Convert-ToFullProjectPath -RelativePath $candidate.import_path
    )
    $previousCachePath = $cacheSnapshot.Path
    $previousCacheBytes = $cacheSnapshot.Bytes
    if ($previousByImportPath.ContainsKey($candidate.import_path)) {
        $previousEntry = $previousByImportPath[$candidate.import_path]
        $previousLimit = [int]$previousEntry.previous_limit
        if ($null -ne $previousEntry.PSObject.Properties['previous_cache_path']) {
            $previousCachePath = [string]$previousEntry.previous_cache_path
        }
        if ($null -ne $previousEntry.PSObject.Properties['previous_cache_bytes']) {
            $previousCacheBytes = [long]$previousEntry.previous_cache_bytes
        }
    }
    $manifestEntries += [ordered]@{
        source_path = $candidate.source_path
        import_path = $candidate.import_path
        width = $candidate.width
        height = $candidate.height
        previous_limit = [int]$previousLimit
        previous_cache_path = $previousCachePath
        previous_cache_bytes = [long]$previousCacheBytes
    }
}

$manifest = [ordered]@{
    version = 1
    generated_at = [DateTime]::Now.ToString('yyyy-MM-ddTHH:mm:ssK')
    target_limit = $TargetLimit
    minimum_source_dimension = $MinimumSourceDimension
    excluded_roots = @($ExcludedRoots)
    entries = $manifestEntries
}
$manifestDirectory = Split-Path -Parent $manifestFullPath
if (-not (Test-Path -LiteralPath $manifestDirectory)) {
    [void](New-Item -ItemType Directory -Path $manifestDirectory)
}
[IO.File]::WriteAllText($manifestFullPath, ($manifest | ConvertTo-Json -Depth 6), $utf8NoBom)

$updatedCount = 0
$unchangedCount = 0
foreach ($candidate in $candidates) {
    $importPath = Convert-ToFullProjectPath -RelativePath $candidate.import_path
    if (Set-ImportLimit -ImportPath $importPath -Limit $TargetLimit) {
        $updatedCount += 1
    }
    else {
        $unchangedCount += 1
    }
}
Write-Output "Mode=Apply Manifest=$ManifestPath Updated=$updatedCount Unchanged=$unchangedCount"
