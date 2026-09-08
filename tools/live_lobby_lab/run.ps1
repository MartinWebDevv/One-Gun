param([switch]$Validate, [switch]$Capture, [switch]$High, [switch]$Editor)
$ErrorActionPreference = 'Stop'
$labProject = Join-Path $PSScriptRoot 'project'
$labEngine = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Godot_v4.7.1-stable_win64.exe'))
$labImportLog = Join-Path $PSScriptRoot 'import.log'
$labRunLog = Join-Path $PSScriptRoot 'run.log'
if (-not (Test-Path -LiteralPath $labEngine)) { throw "Godot executable missing: $labEngine" }
# Quote paths for the Windows process command line, never for another shell.
$labImportArgs = @('--headless','--editor','--path',('"' + $labProject + '"'),'--import','--log-file',('"' + $labImportLog + '"'))
$labImport = Start-Process -FilePath $labEngine -ArgumentList $labImportArgs -PassThru -Wait -WindowStyle Hidden
if ($labImport.ExitCode -ne 0 -or (Select-String -LiteralPath $labImportLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    throw 'Standalone import failed. See import.log.'
}
$labArgs = @('--path',('"' + $labProject + '"'),'--log-file',('"' + $labRunLog + '"'))
if ($Editor) { $labArgs += '--editor' }
if ($Validate) { $labArgs += '--headless' }
if ($Capture) { $labArgs += @('--position','-3000,-3000') }
$labArgs += '--'
if ($Validate) { $labArgs += '--validate' }
if ($Capture) { $labArgs += '--capture' }
if ($High) { $labArgs += '--high' }
$labWindowStyle = if ($Validate -or $Capture) { 'Hidden' } else { 'Normal' }
$labRun = Start-Process -FilePath $labEngine -ArgumentList $labArgs -PassThru -Wait -WindowStyle $labWindowStyle
if ($Validate -or $Capture) { Get-Content -LiteralPath $labRunLog }
exit $labRun.ExitCode