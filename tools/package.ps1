param(
    [string]$Output = "dist/MinecraftRV32IShader-26.3-snapshot-5.zip"
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectRoot $Output
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$inputs = @(
    (Join-Path $projectRoot "pack.mcmeta"),
    (Join-Path $projectRoot "README.md"),
    (Join-Path $projectRoot "LICENSE.txt"),
    (Join-Path $projectRoot "THIRD_PARTY.md"),
    (Join-Path $projectRoot "assets")
)

Compress-Archive -LiteralPath $inputs -DestinationPath $outputPath -CompressionLevel Optimal -Force
Write-Output $outputPath
