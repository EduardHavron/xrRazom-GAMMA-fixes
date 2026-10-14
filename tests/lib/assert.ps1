# Minimal test helpers for Windows PowerShell 5.1 suites (no Pester dependency).
#   . "$PSScriptRoot\..\lib\assert.ps1"
#   Initialize-Tests -Filter $Filter
#   Test-Case 'name' { Assert-Equal 1 1 'one' }
#   Complete-Tests        # prints the summary, exits 1 on any failure

$script:XT = @{ Pass = 0; Fail = 0; Skip = 0; Failed = @(); Filter = '*'; Start = Get-Date }

function Initialize-Tests([string]$Filter = '*') {
    if (-not $Filter) { $Filter = '*' }
    $script:XT = @{ Pass = 0; Fail = 0; Skip = 0; Failed = @(); Filter = $Filter; Start = Get-Date }
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Name -notlike $script:XT.Filter) { $script:XT.Skip++; return }
    $t = Get-Date
    try {
        & $Body
        $script:XT.Pass++
        Write-Host ("PASS  {0}  ({1:n1}s)" -f $Name, ((Get-Date) - $t).TotalSeconds) -ForegroundColor Green
    } catch {
        $script:XT.Fail++
        $script:XT.Failed += $Name
        $where = ''
        if ($_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
            $where = " [{0}:{1}]" -f (Split-Path $_.InvocationInfo.ScriptName -Leaf), $_.InvocationInfo.ScriptLineNumber
        }
        Write-Host ("FAIL  {0}: {1}{2}" -f $Name, $_.Exception.Message, $where) -ForegroundColor Red
        if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host ("::error title=FAIL {0}::{1}" -f $Name, $_.Exception.Message) }
    }
}

function Assert-True($Condition, [string]$Message = 'expected true') {
    if (-not $Condition) { throw "Assert-True failed: $Message" }
}

function Assert-False($Condition, [string]$Message = 'expected false') {
    if ($Condition) { throw "Assert-False failed: $Message" }
}

function Assert-Equal($Expected, $Actual, [string]$Message = '') {
    $e = if ($null -eq $Expected) { '<null>' } else { [string]$Expected }
    $a = if ($null -eq $Actual) { '<null>' } else { [string]$Actual }
    if ($e -cne $a) { throw "Assert-Equal failed: $Message`n    expected: $e`n    actual:   $a" }
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message = '') {
    if ($Text -notmatch $Pattern) {
        $short = if ($Text.Length -gt 400) { $Text.Substring(0, 400) + '...' } else { $Text }
        throw "Assert-Match failed: $Message`n    pattern: $Pattern`n    text:    $short"
    }
}

function Assert-NotMatch([string]$Text, [string]$Pattern, [string]$Message = '') {
    if ($Text -match $Pattern) { throw "Assert-NotMatch failed: $Message`n    pattern: $Pattern" }
}

function Assert-PathExists([string]$Path, [string]$Message = '') {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Assert-PathExists failed: $Message`n    path: $Path" }
}

function Assert-PathMissing([string]$Path, [string]$Message = '') {
    if (Test-Path -LiteralPath $Path) { throw "Assert-PathMissing failed: $Message`n    path: $Path" }
}

function Assert-FilesEqual([string]$A, [string]$B, [string]$Message = '') {
    $ha = (Get-FileHash -LiteralPath $A -Algorithm SHA256).Hash
    $hb = (Get-FileHash -LiteralPath $B -Algorithm SHA256).Hash
    if ($ha -ne $hb) { throw "Assert-FilesEqual failed: $Message`n    $A`n    $B" }
}

function Complete-Tests {
    $d = ((Get-Date) - $script:XT.Start).TotalSeconds
    Write-Host ''
    Write-Host ("Итого: {0} пройдено, {1} упало, {2} пропущено фильтром ({3:n0}s)" -f $script:XT.Pass, $script:XT.Fail, $script:XT.Skip, $d)
    if ($script:XT.Fail -gt 0) {
        $script:XT.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    if ($script:XT.Pass -eq 0) { Write-Host 'Ни один тест не выполнен.' -ForegroundColor Yellow; exit 1 }
    exit 0
}

function New-TestRoot([string]$Prefix = 'xrrfix_test') {
    $base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    $p = Join-Path $base ("{0}_{1}" -f $Prefix, [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    return $p
}
