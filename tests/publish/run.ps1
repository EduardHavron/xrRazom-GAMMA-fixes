# Integration tests for host/publish.ps1, host/publish.bat and installer/install.ps1 (Windows PowerShell 5.1).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\publish\run.ps1 [-Filter 'PUB-012*'] [-KeepTemp] [-ShowOutput]
# Test names start with the requirement IDs from specs/system/{publish,installer,overview}.md (see COVERAGE.md).
# Everything runs in a fresh temp root (RUNNER_TEMP or %TEMP%); child processes get their own LOCALAPPDATA/TEMP,
# XRRFIX_BLOCK_PROCS=<fake process>, a bare origin on disk. No network, no real MO2 / user folders.
param(
    [string]$Filter = '*',
    [switch]$KeepTemp,
    [switch]$ShowOutput
)
$ErrorActionPreference = 'Stop'
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $script:RepoRoot 'tests\lib\assert.ps1')
. (Join-Path $PSScriptRoot 'fixtures.ps1')
$script:Verbose = [bool]$ShowOutput

$oldOutEnc = $null
try { $oldOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

# ---- expected failures: spec [auto] requirement that the code does not meet (does not fail the run)
$script:XF = @{ Fail = 0; Pass = 0; Names = @() }
function Test-CaseXF([string]$Name, [string]$Why, [scriptblock]$Body) {
    if ($Name -notlike $script:XT.Filter) { $script:XT.Skip++; return }
    try {
        & $Body
        $script:XF.Pass++
        Write-Host ("XPASS {0}  (expected to fail: {1}) - remove the EXPECTED-FAIL mark" -f $Name, $Why) -ForegroundColor Yellow
    } catch {
        $script:XF.Fail++
        $script:XF.Names += "$Name ($Why)"
        Write-Host ("XFAIL {0}: {1}" -f $Name, ($_.Exception.Message -split "`n")[0]) -ForegroundColor DarkYellow
    }
}
function Skip-Case([string]$Name, [string]$Why) {
    if ($Name -notlike $script:XT.Filter) { return }
    Write-Host ("SKIP  {0}: {1}" -f $Name, $Why) -ForegroundColor DarkGray
}

Initialize-Tests -Filter $Filter
$script:TestRoot = New-TestRoot 'xrrfix_pub'
$script:InsLad = Join-Path $script:TestRoot 'ins_lad'
$script:InsTmp = Join-Path $script:TestRoot 'ins_tmp'
New-Item -ItemType Directory -Path $script:InsLad, $script:InsTmp -Force | Out-Null
Write-Host "Temp root: $script:TestRoot"

$exitCode = 1
try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'git.exe not found in PATH' }
    $script:TemplateDir = Join-Path $script:TestRoot 'template'
    $t0 = Get-Date
    New-Template $script:TemplateDir $script:RepoRoot
    Write-Host ("Template built in {0:n1}s" -f ((Get-Date) - $t0).TotalSeconds)

    . (Join-Path $PSScriptRoot 'cases_publish.ps1')
    . (Join-Path $PSScriptRoot 'cases_publish2.ps1')
    . (Join-Path $PSScriptRoot 'cases_installer.ps1')
    . (Join-Path $PSScriptRoot 'cases_system.ps1')
} finally {
    Get-Process -Name $script:FAKE_PROC, 'ModOrganizer' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($script:TestRoot, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { try { $_.Kill() } catch { } }
    if ($oldOutEnc) { try { [Console]::OutputEncoding = $oldOutEnc } catch { } }
    if ($KeepTemp) { Write-Host "Kept: $script:TestRoot" }
    else {
        Start-Sleep -Milliseconds 300
        try { Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction Stop }
        catch { Write-Host "Warning: could not delete $script:TestRoot : $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

if ($script:XF.Fail -gt 0 -or $script:XF.Pass -gt 0) {
    Write-Host ''
    Write-Host ("EXPECTED-FAIL: {0} (XPASS: {1})" -f $script:XF.Fail, $script:XF.Pass) -ForegroundColor DarkYellow
    $script:XF.Names | ForEach-Object { Write-Host "  ~ $_" -ForegroundColor DarkYellow }
}
Complete-Tests
