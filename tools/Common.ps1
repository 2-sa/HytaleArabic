Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
}
function File-Hash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return $null
}
function Read-Lang([string]$Path) {
    $map = [ordered]@{}
    $pending = ''
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($pending) { $line = $pending + $line.TrimStart() }
        if ($line.EndsWith('\')) { $pending = $line.Substring(0, $line.Length - 1); continue }
        $pending = ''
        if ($line -match '^\s*([^#\s][^=]*?)\s*=\s*(.*)$') { $map[$matches[1].Trim()] = $matches[2] }
    }
    if ($pending) { throw "Incomplete continuation in $Path" }
    return $map
}
function Write-Lang([string]$Path, $Map) {
    $lines = foreach ($key in $Map.Keys) { "$key = $($Map[$key])" }
    Write-Utf8 $Path (($lines -join "`n") + "`n")
}
function Resolve-Hytale([string]$Root) {
    if (!$Root) { $Root = Join-Path $env:APPDATA 'Hytale' }
    if (!(Test-Path -LiteralPath (Join-Path $Root 'install\release\package\game\latest\Client\Data\Shared\Language\en-US\client.lang'))) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'اختر مجلد Hytale الذي يحتوي install وUserData'
        if ($dialog.ShowDialog() -ne 'OK') { throw 'لم يُحدّد مجلد اللعبة.' }
        $Root = $dialog.SelectedPath
    }
    return [IO.Path]::GetFullPath($Root).TrimEnd('\')
}
function Assert-Closed {
    if (Get-Process -Name HytaleClient,HytaleLauncher,'hytale-launcher' -ErrorAction SilentlyContinue) {
        throw 'أغلق اللعبة ومشغّلها ثم حاول مجددًا.'
    }
}
function Assert-Contained([string]$Root, [string]$Relative) {
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (!$full.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'مسار خارج مجلد اللعبة.' }
    return $full
}
