param(
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [int]$BaudRate = 1000000,
    [string]$OutputPath = (Join-Path $PWD ("saroo-uart-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
)

$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, $BaudRate, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 250
$serial.NewLine = "`r`n"
$writer = [System.IO.StreamWriter]::new(
    [System.IO.Path]::GetFullPath($OutputPath), $false,
    [System.Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true

try {
    $serial.Open()
    Write-Host "Capturing $Port at $BaudRate baud to $OutputPath (Ctrl+C to stop)"
    $writer.WriteLine("# SAROO UART capture {0:o} port={1} baud={2}" -f
        (Get-Date), $Port, $BaudRate)
    while($true) {
        try {
            $text = $serial.ReadExisting()
            if($text.Length -gt 0) {
                [Console]::Write($text)
                $writer.Write($text)
            } else {
                Start-Sleep -Milliseconds 20
            }
        } catch [System.TimeoutException] {
            # Poll again so Ctrl+C remains responsive.
        }
    }
} finally {
    if($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $writer.Dispose()
}
