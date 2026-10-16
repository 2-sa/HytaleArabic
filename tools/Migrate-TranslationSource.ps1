param(
    [Parameter(Mandatory=$true)][string]$OldReferenceDirectory,
    [Parameter(Mandatory=$true)][string]$NewReferenceDirectory,
    [Parameter(Mandatory=$true)][string]$ArabicDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('FlatReference','Mirrored')][string]$ReferenceLayout='FlatReference'
)
. "$PSScriptRoot\Common.ps1"
Add-Type -Path "$PSScriptRoot\MessageTokens.cs"

function Full-Directory([string]$Path) {
    if(!(Test-Path -LiteralPath $Path -PathType Container)){throw "Input directory missing: $Path"}
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\','/')
}
function Relative-File([string]$Root,[string]$File) {
    $prefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(!$File.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "File outside input root: $File"}
    return $File.Substring($prefix.Length)
}
function Reference-Index([string]$Root) {
    $index=[ordered]@{}
    if($ReferenceLayout -eq 'FlatReference'){
        $files=@(Get-ChildItem -LiteralPath $Root -Filter 'reference-*.lang' -File)
    }else{
        $files=@(Get-ChildItem -LiteralPath $Root -Filter '*.lang' -File -Recurse)
    }
    if(!$files.Count){throw "No reference language files found in $Root"}
    foreach($file in $files | Sort-Object FullName){
        if($ReferenceLayout -eq 'FlatReference'){
            $name=$file.Name.Substring('reference-'.Length)
            $relative=if($name -in @('client.lang','server.lang','wordlists.lang')){$name}else{Join-Path 'avatarCustomization' $name}
        }else{$relative=Relative-File $Root $file.FullName}
        if($index.Contains($relative)){throw "Duplicate reference path: $relative"}
        $index[$relative]=[pscustomobject]@{Path=$file.FullName;Values=(Read-Lang $file.FullName)}
    }
    return ,$index
}
function Save-Map([string]$Root,[string]$Relative,$Map) {
    $path=Assert-Contained $Root $Relative
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    Write-Lang $path $Map
}

$oldRoot=Full-Directory $OldReferenceDirectory
$newRoot=Full-Directory $NewReferenceDirectory
$arabicRoot=Full-Directory $ArabicDirectory
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(Test-Path -LiteralPath $outputRoot){throw 'OutputDirectory must be a new directory; existing sources will never be overwritten.'}
$old=Reference-Index $oldRoot
$next=Reference-Index $newRoot
$fileReports=New-Object 'System.Collections.Generic.List[object]'
$totals=[ordered]@{NextKeys=0;Reused=0;Added=0;Changed=0;Removed=0;UntranslatedUnchanged=0;InvalidArabic=0;Pending=0}
# Read and validate everything before creating any output.
$plans=New-Object 'System.Collections.Generic.List[object]'
foreach($relative in @($old.Keys)+@($next.Keys) | Sort-Object -Unique){
    $before=if($old.Contains($relative)){$old[$relative].Values}else{[ordered]@{}}
    $after=if($next.Contains($relative)){$next[$relative].Values}else{[ordered]@{}}
    $arabicPath=Assert-Contained $arabicRoot $relative
    $translated=if(Test-Path -LiteralPath $arabicPath -PathType Leaf){Read-Lang $arabicPath}else{[ordered]@{}}
    $reuse=[ordered]@{};$pending=[ordered]@{}
    $counts=[ordered]@{NextKeys=$after.Count;Reused=0;Added=0;Changed=0;Removed=0;UntranslatedUnchanged=0;InvalidArabic=0;Pending=0}
    $reasons=New-Object 'System.Collections.Generic.List[object]'
    $removed=New-Object 'System.Collections.Generic.List[string]'
    foreach($key in $before.Keys){if(!$after.Contains($key)){$counts.Removed++;$removed.Add($key)}}
    foreach($key in $after.Keys){
        $reason=$null
        if(!$before.Contains($key)){$counts.Added++;$reason='added'}
        elseif($before[$key] -cne $after[$key]){$counts.Changed++;$reason='english_changed'}
        elseif(!$translated.Contains($key) -or ($after[$key] -and [string]::IsNullOrWhiteSpace($translated[$key]))){$counts.UntranslatedUnchanged++;$reason='untranslated_unchanged'}
        else{
            try{
                $sourceTokens=@([MessageTokens]::Extract($after[$key])) -join ','
                $arabicTokens=@([MessageTokens]::Extract($translated[$key])) -join ','
                if($sourceTokens -cne $arabicTokens){throw 'Argument names differ'}
                $formatPattern='\{([\w]+)\s*,\s*(plural|selectordinal|select|number|date|time)\b'
                $originalFormats=@([regex]::Matches($after[$key],$formatPattern)|ForEach-Object{$_.Groups[1].Value+':'+$_.Groups[2].Value}|Sort-Object -Unique) -join ','
                $arabicFormats=@([regex]::Matches($translated[$key],$formatPattern)|ForEach-Object{$_.Groups[1].Value+':'+$_.Groups[2].Value}|Sort-Object -Unique) -join ','
                if($originalFormats -cne $arabicFormats){throw 'Argument formatters differ'}
                $tagPattern='</?[A-Za-z][\w:-]*(?=\s*/?>|\s+[\w:-]+\s*=)[^>]*>'
                $originalTags=@([regex]::Matches($after[$key],$tagPattern)|ForEach-Object Value) -join '|'
                $arabicTags=@([regex]::Matches($translated[$key],$tagPattern)|ForEach-Object Value) -join '|'
                if($originalTags -cne $arabicTags){throw 'Markup differs'}
                $flagPattern='(?<![A-Za-z0-9_-])--[A-Za-z][A-Za-z0-9_-]*'
                $originalFlags=@([regex]::Matches($after[$key],$flagPattern)|ForEach-Object Value|Sort-Object -Unique) -join ','
                $arabicFlags=@([regex]::Matches($translated[$key],$flagPattern)|ForEach-Object Value|Sort-Object -Unique) -join ','
                if($originalFlags -cne $arabicFlags){throw 'CLI flags differ'}
                if($after[$key].Contains('[TMP]') -ne $translated[$key].Contains('[TMP]')){throw 'TMP marker differs'}
                $reuse[$key]=$translated[$key];$counts.Reused++
            }catch{$counts.InvalidArabic++;$reason='invalid_arabic_structure'}
        }
        if($reason){$pending[$key]=$after[$key];$reasons.Add([pscustomobject]@{Key=$key;Reason=$reason})}
    }
    $counts.Pending=$pending.Count
    foreach($name in @($totals.Keys)){$totals[$name]+=$counts[$name]}
    $fileReports.Add([pscustomobject]@{Path=$relative.Replace('\','/');Counts=$counts;Pending=@($reasons.ToArray());Removed=@($removed.ToArray())})
    if($next.Contains($relative)){$plans.Add([pscustomobject]@{Path=$relative;Arabic=$reuse;Pending=$pending})}
}
[void][IO.Directory]::CreateDirectory($outputRoot)
$sourceOutput=Join-Path $outputRoot 'arabic'
$pendingOutput=Join-Path $outputRoot 'pending-english'
[void][IO.Directory]::CreateDirectory($sourceOutput)
[void][IO.Directory]::CreateDirectory($pendingOutput)
foreach($plan in $plans){Save-Map $sourceOutput $plan.Path $plan.Arabic;Save-Map $pendingOutput $plan.Path $plan.Pending}
$report=[ordered]@{
    Format=1;OldReference=$oldRoot;NewReference=$newRoot;ArabicSource=$arabicRoot;ReferenceLayout=$ReferenceLayout
    Rule='Only same file path, same key, and ordinal-identical parsed English may reuse structurally valid Arabic.'
    Fallback='Added, changed, untranslated, or structurally invalid entries stay in the new native English reference; they are excluded from Arabic output.'
    Counts=$totals;Files=@($fileReports.ToArray());GameModified=$false
}
Write-Utf8 (Join-Path $outputRoot 'migration-report.json') ($report | ConvertTo-Json -Depth 12)
Write-Host "Migration source prepared: $($totals.Reused) reused; $($totals.Added) added; $($totals.Changed) changed; $($totals.Removed) removed; $($totals.Pending) pending."
