param(
    [Parameter(Mandatory = $true)]
    [string]$SdRoot,
    [string]$DiagnosticImage = "$env:USERPROFILE\Downloads\bakubaku-saroo.bin",
    [string]$RunImage = "$env:USERPROFILE\Downloads\bakubaku-saroo-run.bin"
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($SdRoot)
if(-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "SD root does not exist: $root"
}

$destination = Join-Path $root 'SAROO\STV'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$images = @($DiagnosticImage, $RunImage)
$hashLines = @()

foreach($image in $images) {
    $source = (Resolve-Path -LiteralPath $image).Path
    $item = Get-Item -LiteralPath $source
    if($item.Length -ne 33554432) {
        throw "Expected a 32 MB packed image: $source ($($item.Length) bytes)"
    }
    $manifest = "$source.json"
    if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "Packed-image manifest is missing: $manifest"
    }
    $metadata = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
    if($metadata.format -notin @('saroo-stv-cart-v1', 'saroo-stv-cart-v2') -or
       [uint64]$metadata.image_size -ne [uint64]$item.Length) {
        throw "Invalid SAROO-STV manifest: $manifest"
    }
    $actualSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $source).Hash.ToLowerInvariant()
    if($actualSha1 -ne ([string]$metadata.image_sha1).ToLowerInvariant()) {
        throw "Image SHA-1 does not match its manifest: $source"
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Copy-Item -LiteralPath $manifest -Destination $destination -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    $hashLines += "$hash  $($item.Name)"
}

$checksumPath = Join-Path $destination 'SHA256SUMS.txt'
[System.IO.File]::WriteAllLines($checksumPath, $hashLines,
    [System.Text.UTF8Encoding]::new($false))
Write-Host "Prepared $destination"
$hashLines | ForEach-Object { Write-Host $_ }
