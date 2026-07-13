param(
    [string]$RomDirectory,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wslRepo = (& wsl -- wslpath -a -u ($repo -replace '\\', '/')).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to translate the repository path for WSL.' }

$scriptArgs = @()
if ($RomDirectory) {
    $rom = (Resolve-Path $RomDirectory).Path
    $wslRom = (& wsl -- wslpath -a -u ($rom -replace '\\', '/')).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to translate the ROM path for WSL.' }
    $scriptArgs += @('--rom-dir', $wslRom)
}
if ($OutputDirectory) {
    $output = [System.IO.Path]::GetFullPath($OutputDirectory)
    $wslOutput = (& wsl -- wslpath -a -u ($output -replace '\\', '/')).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to translate the output path for WSL.' }
    $scriptArgs += @('--output-dir', $wslOutput)
}

& wsl -- bash -lc 'cd "$1"; shift; exec bash tools/stv/verify_virtual.sh "$@"' bash $wslRepo @scriptArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$uv4 = 'C:\Keil_v5\UV4\UV4.exe'
$quartus = 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe'
if ((Test-Path $uv4) -and (Test-Path $quartus)) {
    & (Join-Path $PSScriptRoot 'verify_vendor.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "`nVendor acceptance skipped (Keil and/or Quartus not installed)."
}
