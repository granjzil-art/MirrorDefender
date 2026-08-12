param(
    [switch]$Rollback
)

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$textureNames = @(
    'flatstone2_0.png', 'flatstone2_1.png', 'flatstone2_2.png', 'flatstone2_3.png',
    'GrassMud_0.png', 'GrassMud_1.png', 'GrassMud_2.png', 'GrassMud_3.png',
    'GrassStone_0.png', 'GrassStone_1.png', 'GrassStone_2.png', 'GrassStone_3.png',
    'greenstone_0.png', 'greenstone_1.png', 'greenstone_2.png', 'greenstone_3.png',
    'mud1_0.png', 'mud1_1.png', 'mud1_2.png', 'mud1_3.png'
)
$targetLimit = 0
if (-not $Rollback) {
    $targetLimit = 2048
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$updatedCount = 0

foreach ($textureName in $textureNames) {
    $importPath = Join-Path $projectRoot "assets\blocks\fbx\$textureName.import"
    if (-not (Test-Path -LiteralPath $importPath)) {
        Write-Warning "Missing Godot import sidecar: $importPath"
        continue
    }
    $content = [System.IO.File]::ReadAllText($importPath)
    $updated = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        'process/size_limit=\d+',
        "process/size_limit=$targetLimit",
        1
    )
    if ($updated -eq $content) {
        continue
    }
    [System.IO.File]::WriteAllText($importPath, $updated, $utf8NoBom)
    $updatedCount += 1
}

$mode = '2048 texture cap'
if ($Rollback) {
    $mode = 'unlimited texture size'
}
Write-Output "Applied $mode to $updatedCount terrain import sidecar(s)."
