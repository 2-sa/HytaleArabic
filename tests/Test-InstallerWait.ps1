param([Parameter(Mandatory=$true)][string]$InstallerPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$installer=(Resolve-Path -LiteralPath $InstallerPath).Path
$destination=Join-Path (Split-Path $PSScriptRoot -Parent) ('build\wait-extraction-'+[guid]::NewGuid().ToString('N'))
$sleeper=Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 3') -WindowStyle Hidden -PassThru
try {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $extractor=Start-Process -FilePath $installer -ArgumentList @('--wait-pid',$sleeper.Id,'--test-extract',$destination) -WindowStyle Hidden -PassThru -Wait
    $timer.Stop()
    if ($extractor.ExitCode -ne 0) { throw "Wait/extraction failed with exit code $($extractor.ExitCode)." }
    if ($timer.Elapsed.TotalSeconds -lt 2) { throw 'Installer did not wait for the previous process to exit.' }
    if (!(Test-Path -LiteralPath (Join-Path $destination '.test-result'))) { throw 'Wait test extraction result missing.' }
    Write-Output 'PASS: installer waits for its parent process before extracting files.'
} finally {
    if (!$sleeper.HasExited) { Stop-Process -Id $sleeper.Id -Force }
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
}
