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
