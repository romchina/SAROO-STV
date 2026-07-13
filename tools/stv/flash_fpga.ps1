param(
    [string]$Image = (Join-Path $PSScriptRoot '..\..\FPGA\output_files\ssmaster.jic'),
    [string]$QuartusPgm = 'C:\altera_lite\25.1std\quartus\bin64\quartus_pgm.exe',
    [string]$Cable = '1',
    [int]$DeviceIndex = 1,
    [switch]$Volatile
)

$ErrorActionPreference = 'Stop'
$imagePath = (Resolve-Path -LiteralPath $Image).Path
if(-not (Test-Path -LiteralPath $QuartusPgm -PathType Leaf)) {
    throw "Quartus Programmer not found: $QuartusPgm"
}

if($Volatile) {
    if([System.IO.Path]::GetExtension($imagePath) -ne '.sof') {
        throw 'Volatile programming requires a .sof image.'
    }
    $operation = "p;$imagePath@$DeviceIndex"
} else {
    if([System.IO.Path]::GetExtension($imagePath) -ne '.jic') {
        throw 'Persistent programming requires a .jic image.'
    }
    # I initializes the serial-flash bridge; P/V/B program, verify and blank-check.
    $operation = "pvbi;$imagePath@$DeviceIndex"
}

& $QuartusPgm -c $Cable -m JTAG -o $operation
if($LASTEXITCODE -ne 0) { throw "Quartus programming failed ($LASTEXITCODE)" }
