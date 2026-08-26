param(
    [string]$Output = "dist/MinecraftRV32IShader-26.3-snapshot-5.zip"
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectRoot $Output
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$inputs = @(
    "pack.mcmeta",
    "README.md",
    "LICENSE.txt",
    "THIRD_PARTY.md"
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$files = foreach ($relativePath in $inputs) {
    Get-Item -LiteralPath (Join-Path $projectRoot $relativePath)
}
$files += Get-ChildItem -LiteralPath (Join-Path $projectRoot "assets") -File -Recurse

if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
}

$archive = [System.IO.Compression.ZipFile]::Open(
    $outputPath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    foreach ($file in $files) {
        $entryName = [System.IO.Path]::GetRelativePath($projectRoot, $file.FullName).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $file.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

Write-Output $outputPath
