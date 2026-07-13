param(
    [string]$Image = (Join-Path $PSScriptRoot '..\..\Firm_MCU\Objects\ssmaster.bin'),
    [string]$JLink = 'C:\Program Files\SEGGER\JLink\JLink.exe',
    [int]$SpeedKHz = 4000
)

$ErrorActionPreference = 'Stop'
$imagePath = (Resolve-Path -LiteralPath $Image).Path
if(-not (Test-Path -LiteralPath $JLink -PathType Leaf)) {
    throw "J-Link Commander not found: $JLink"
}
$imageSize = (Get-Item -LiteralPath $imagePath).Length
if($imageSize -eq 0 -or $imageSize -gt 0x20000) {
    throw "MCU image exceeds the configured 128 KB flash region: $imagePath"
}

$commands = @"
device STM32H750VB
si SWD
speed $SpeedKHz
connect
r
h
loadbin $imagePath, 0x08000000
r
g
exit
"@
$commandFile = Join-Path $env:TEMP 'saroo-stv-flash-mcu.jlink'
[System.IO.File]::WriteAllText($commandFile, $commands,
    [System.Text.UTF8Encoding]::new($false))
try {
    & $JLink -NoGui 1 -ExitOnError 1 -CommanderScript $commandFile
    if($LASTEXITCODE -ne 0) { throw "J-Link programming failed ($LASTEXITCODE)" }
} finally {
    Remove-Item -LiteralPath $commandFile -Force -ErrorAction SilentlyContinue
}
