param(
    [string]$KeilRoot = 'C:\Keil_v5',
    [string]$QuartusRoot = 'C:\altera_lite\25.1std'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$uv4 = Join-Path $KeilRoot 'UV4\UV4.exe'
$quartus = Join-Path $QuartusRoot 'quartus\bin64\quartus_sh.exe'

if (-not (Test-Path $uv4)) { throw "Keil uVision not found: $uv4" }
if (-not (Test-Path $quartus)) { throw "Quartus shell not found: $quartus" }

Write-Host "`n==== Keil MCU clean rebuild ===="
$project = Join-Path $repo 'Firm_MCU\ssmaster.uvprojx'
$log = Join-Path $env:TEMP 'saroo-stv-keil-build.log'
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
$keil = Start-Process -FilePath $uv4 -ArgumentList @(
    '-r', $project, '-j0', '-o', $log
) -WindowStyle Hidden -PassThru -Wait
if (Test-Path $log) { Get-Content $log }
if ($keil.ExitCode -ne 0) { throw "Keil rebuild failed: exit $($keil.ExitCode)" }

$mcuBin = Join-Path $repo 'Firm_MCU\Objects\ssmaster.bin'
if (-not (Test-Path $mcuBin)) { throw "Keil output missing: $mcuBin" }
Write-Host "verified MCU binary $((Get-Item $mcuBin).Length) bytes"

Write-Host "`n==== Quartus FPGA full compilation ===="
Push-Location (Join-Path $repo 'FPGA')
try {
    & $quartus --flow compile SSMaster
    if ($LASTEXITCODE -ne 0) { throw "Quartus compile failed: exit $LASTEXITCODE" }
} finally {
    Pop-Location
}

foreach ($name in 'SSMaster.sof', 'ssmaster.jic') {
    $output = Join-Path $repo "FPGA\output_files\$name"
    if (-not (Test-Path $output)) { throw "Quartus output missing: $output" }
    Write-Host "verified $name $((Get-Item $output).Length) bytes"
}

Write-Host "`nVENDOR ACCEPTANCE PASS"
