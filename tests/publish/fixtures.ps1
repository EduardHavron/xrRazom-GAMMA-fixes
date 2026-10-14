# Fixture builders and helpers for tests/publish (dot-sourced by run.ps1).
# Sandbox layout (one per test case, copied from a template built once per run):
#   <case>\gh\EduardHavron\xrRazom-GAMMA-fixes.git   bare "GitHub" origin (branch main)
#   <case>\H\  host GAMMA root: ModOrganizer.exe/.ini, profiles\P\modlist.txt, mods\..., repo\ (clone)
#   <case>\F\  friend GAMMA root (same shape)
#   <case>\lad\   LOCALAPPDATA for child processes      <case>\tmp\   TEMP/TMP for child processes
# Seed mods: modA, modB, modX, "zz Фикс Y" (pack order: zz Фикс Y, modX, modB, modA), each with
# gamedata\scripts\<name with _>.script = "v1 <name>`r`n"; MO2 adds meta.ini; "Other mod" is a foreign mod below the separator.

$script:UTF8NoBom = New-Object Text.UTF8Encoding($false)
$script:SEED_NAMES = @('modA', 'modB', 'modX', 'zz Фикс Y')
$script:SEED_ORDER = @('zz Фикс Y', 'modX', 'modB', 'modA')
$script:SEP = 'xrRazom Sync_separator'
$script:FAKE_PROC = 'xrrfix_fake_mo2_t2'   # unique name: independent of a real MO2 and of the agent suite
$script:PS_EXE = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------------------------------------------------------------- generic
function G {
    # git with fixed config; returns stdout lines (stderr discarded unless -c is wanted)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $r = & git.exe -c core.autocrlf=false -c core.quotepath=false @args 2>$null } finally { $ErrorActionPreference = $old }
    if ($null -ne $r) { $r }
}
function G-Code {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git.exe -c core.autocrlf=false -c core.quotepath=false @args 2>&1 | Out-Null } finally { $ErrorActionPreference = $old }
    return $LASTEXITCODE
}
function G-Must {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $r = & git.exe -c core.autocrlf=false -c core.quotepath=false @args 2>&1 } finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $($r -join ' | ')" }
}

function Write-Bytes([string]$Path, [byte[]]$Bytes) {
    $d = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllBytes($Path, $Bytes)
}
function Write-Text([string]$Path, [string]$Text) {
    Write-Bytes $Path ($script:UTF8NoBom.GetBytes($Text))
}
function Read-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $script:UTF8NoBom) }

function QArg([string]$a) {
    if ($a -eq '') { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

# Runs a process with stdin closed (or fed), UTF-8 stdout/stderr, extra env, timeout. -> @{Code; Out; Err; All; Sec}
function Invoke-Proc {
    param([string]$File, [string[]]$ArgList = @(), [hashtable]$Env = @{}, [string]$Stdin = $null,
          [int]$TimeoutSec = 180, [string]$WorkDir = $null, [string]$RawArgs = $null)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    if ($null -ne $RawArgs -and $RawArgs -ne '') { $psi.Arguments = $RawArgs }
    else { $psi.Arguments = (@($ArgList) | ForEach-Object { QArg $_ }) -join ' ' }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:UTF8NoBom
    $psi.StandardErrorEncoding = $script:UTF8NoBom
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    foreach ($k in $Env.Keys) {
        if ($null -eq $Env[$k]) { $psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # .NET Framework creates the child's stdin writer with Console.InputEncoding and AutoFlush, which writes the
    # encoding preamble at once: with a UTF-8 console (GitHub runners) the child reads a BOM before our input.
    # ASCII has no preamble, so switch to it just for the start.
    $prevIn = $null
    try { $prevIn = [Console]::InputEncoding; [Console]::InputEncoding = [Text.Encoding]::ASCII } catch { $prevIn = $null }
    try { $p = [Diagnostics.Process]::Start($psi) }
    finally { if ($prevIn) { try { [Console]::InputEncoding = $prevIn } catch {} } }
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    # bytes straight to the pipe (no encoder involved)
    if ($Stdin) { $bin = [Text.Encoding]::ASCII.GetBytes($Stdin); $p.StandardInput.BaseStream.Write($bin, 0, $bin.Length); $p.StandardInput.BaseStream.Flush() }
    $p.StandardInput.Close()
    $code = $null
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { & taskkill.exe /F /T /PID $p.Id 2>&1 | Out-Null } catch { }
        $p.WaitForExit(10000) | Out-Null
        $code = -999
    } else { $p.WaitForExit(); $code = $p.ExitCode }
    $sw.Stop()
    $out = ''; $err = ''
    try { $out = $outTask.Result } catch { }
    try { $err = $errTask.Result } catch { }
    return New-Object PSObject -Property @{ Code = $code; Out = $out; Err = $err; All = ($out + "`n" + $err); Sec = $sw.Elapsed.TotalSeconds }
}

# ---------------------------------------------------------------- sandbox
function Get-ChildEnv($sb, [hashtable]$Extra = @{}) {
    $e = @{
        LOCALAPPDATA       = $sb.Lad
        TEMP               = $sb.Tmp
        TMP                = $sb.Tmp
        XRRFIX_BLOCK_PROCS = $script:FAKE_PROC
        XRRFIX_NO_NOTIFY   = '1'
        GIT_TERMINAL_PROMPT = '0'
    }
    foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }
    return $e
}

function Write-PackJson([string]$Path, [string]$Section, [string[]]$Mods) {
    $q = { param($s) '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }
    $txt = "{`n  `"section`": " + (& $q $Section) + ",`n  `"mods`": [`n" + ((@($Mods) | ForEach-Object { '    ' + (& $q $_) }) -join ",`n") + "`n  ]`n}`n"
    Write-Text $Path $txt
}

function New-ModDir([string]$ModsDir, [string]$Name, [string]$Content) {
    $fn = $Name.Replace(' ', '_')
    Write-Text (Join-Path $ModsDir "$Name\gamedata\scripts\$fn.script") ($Content + "`r`n")
}

function New-Machine([string]$Root, [string]$Origin, [string]$Who, [string]$SeedMods) {
    New-Item -ItemType Directory -Path "$Root\profiles\P", "$Root\mods" -Force | Out-Null
    Write-Bytes "$Root\ModOrganizer.exe" ([byte[]]@())
    Write-Text "$Root\ModOrganizer.ini" "[General]`r`nselected_profile=@ByteArray(P)`r`n"
    G-Must clone -q $Origin "$Root\repo"
    G-Must -C "$Root\repo" config user.name $Who
    G-Must -C "$Root\repo" config user.email "$Who@example.invalid"
    G-Must -C "$Root\repo" config core.autocrlf false
    foreach ($n in $script:SEED_NAMES) {
        Copy-Item -LiteralPath (Join-Path $SeedMods $n) -Destination "$Root\mods\$n" -Recurse
        Write-Text "$Root\mods\$n\meta.ini" "[General]`r`nmodid=0`r`n"
    }
    Write-Text "$Root\mods\Other mod\a.txt" "x`r`n"
    Set-Modlist $Root (@('# This file was automatically generated by Mod Organizer.') + @($script:SEED_ORDER | ForEach-Object { "+$_" }) +
        @("+$script:SEP", '+Other mod', '+Base_separator'))
}

# Build the template once: origin + seed commit + H + F.
function New-Template([string]$Dir, [string]$RepoRoot) {
    $origin = Join-Path $Dir 'gh\EduardHavron\xrRazom-GAMMA-fixes.git'
    New-Item -ItemType Directory -Path $origin -Force | Out-Null
    G-Must init -q --bare $origin
    G-Must --git-dir $origin symbolic-ref HEAD refs/heads/main
    $seed = Join-Path $Dir 'seed'
    New-Item -ItemType Directory -Path "$seed\host", "$seed\installer", "$seed\agent", "$seed\pack" -Force | Out-Null
    Copy-Item "$RepoRoot\host\publish.ps1", "$RepoRoot\host\publish.bat" "$seed\host\"
    Write-Text "$seed\host\publish.ini" "gamma_root=`r`nprofile=`r`nsection=xrRazom Sync`r`npush=1`r`n"
    Copy-Item "$RepoRoot\installer\*" "$seed\installer\"
    Copy-Item "$RepoRoot\agent\*" "$seed\agent\"
    Write-Text "$seed\.gitattributes" "* -text`n"
    Write-Text "$seed\README.md" "test repo`n"
    foreach ($n in $script:SEED_NAMES) { New-ModDir "$seed\mods" $n "v1 $n" }
    Write-PackJson "$seed\pack\pack.json" 'xrRazom Sync' $script:SEED_ORDER
    G-Must -C $seed init -q
    G-Must -C $seed symbolic-ref HEAD refs/heads/main
    G-Must -C $seed add -A
    G-Must -C $seed -c user.name=seed -c user.email=seed@example.invalid commit -q -m seed
    G-Must -C $seed push -q $origin main
    New-Machine "$Dir\H" $origin 'H' "$seed\mods"
    New-Machine "$Dir\F" $origin 'F' "$seed\mods"
    Remove-Item -LiteralPath $seed -Recurse -Force
}

$script:CaseNo = 0
function New-Sandbox {
    $script:HoldingMutex = $false
    $script:CaseNo++
    $dir = Join-Path $script:TestRoot ('c{0:d3}' -f $script:CaseNo)
    Copy-Item -LiteralPath $script:TemplateDir -Destination $dir -Recurse
    $origin = Join-Path $dir 'gh\EduardHavron\xrRazom-GAMMA-fixes.git'
    foreach ($w in 'H', 'F') { G-Must -C "$dir\$w\repo" remote set-url origin $origin }
    New-Item -ItemType Directory -Path "$dir\lad", "$dir\tmp", "$dir\cap" -Force | Out-Null
    return @{ Root = $dir; Origin = $origin; H = "$dir\H"; F = "$dir\F"; Lad = "$dir\lad"; Tmp = "$dir\tmp"; Cap = "$dir\cap" }
}

# ---------------------------------------------------------------- MO2 helpers
function Get-Modlist([string]$Root, [string]$Profile = 'P') {
    $p = "$Root\profiles\$Profile\modlist.txt"
    return @((Read-Text $p).TrimStart([char]0xFEFF) -split "`r?`n" | Where-Object { $_ -ne '' })
}
function Set-Modlist([string]$Root, [string[]]$Lines, [string]$Profile = 'P') {
    Write-Text "$Root\profiles\$Profile\modlist.txt" ((@($Lines) -join "`r`n") + "`r`n")
}
# Lines of the section (above the separator up to the previous separator / header), with +/- prefixes.
function Get-Section([string]$Root, [string]$Sep = $script:SEP, [string]$Profile = 'P') {
    $l = Get-Modlist $Root $Profile
    $i = [Array]::FindIndex([string[]]$l, [Predicate[string]] { param($x) $x.Length -gt 1 -and $x.Substring(1) -eq $Sep })
    if ($i -lt 0) { return @() }
    $res = @()
    for ($j = $i - 1; $j -ge 0; $j--) {
        if ($l[$j].StartsWith('#') -or $l[$j].EndsWith('_separator')) { break }
        $res = @($l[$j]) + $res
    }
    return $res
}
function Join-L($a) { return (@($a) -join '|') }

function Set-Mod([string]$Root, [string]$Name, [string]$Content) {
    New-ModDir "$Root\mods" $Name $Content
}
function Get-Mod([string]$Root, [string]$Name) {
    $p = "$Root\mods\$Name\gamedata\scripts\$($Name.Replace(' ', '_')).script"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return (Read-Text $p).Replace("`r", '').TrimEnd("`n")
}
function Add-NewMod([string]$Root, [string]$Name, [string]$Content, [string]$After = 'modA') {
    Set-Mod $Root $Name $Content
    $l = Get-Modlist $Root
    $out = @(); foreach ($x in $l) { $out += $x; if ($x -eq "+$After") { $out += "+$Name" } }
    Set-Modlist $Root $out
}
function Remove-FromModlist([string]$Root, [string]$Name) {
    Set-Modlist $Root @(Get-Modlist $Root | Where-Object { $_.Substring(1) -ne $Name })
}
function Set-SectionOrder([string]$Root, [string[]]$Order) {
    $l = Get-Modlist $Root
    $i = [Array]::IndexOf([string[]]$l, "+$script:SEP")
    $sec = @(Get-Section $Root)
    $start = $i - $sec.Count
    Set-Modlist $Root (@($l[0..($start - 1)]) + @($Order | ForEach-Object { "+$_" }) + @($l[$i..($l.Count - 1)]))
}
# snapshot of a directory: "rel|sha256" lines
function Get-DirSnapshot([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return '<missing>' }
    $base = (Get-Item -LiteralPath $Dir).FullName.TrimEnd('\') + '\'
    $rows = foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force)) {
        $f.FullName.Substring($base.Length) + '|' + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $arr = [string[]]@($rows); [Array]::Sort($arr, [StringComparer]::Ordinal)
    return ($arr -join "`n")
}
function Get-FileSha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# ---------------------------------------------------------------- git/origin helpers
function Get-OriginSha($sb) { return (G --git-dir $sb.Origin rev-parse main | Select-Object -First 1) }
function Get-HeadSha([string]$Repo) { return (G -C $Repo rev-parse HEAD | Select-Object -First 1) }
function Get-OriginText($sb, [string]$Path, [string]$Rev = 'main') {
    $r = Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, '-c', 'core.quotepath=false', 'show', "${Rev}:$Path")
    if ($r.Code -ne 0) { return $null }
    return $r.Out
}
function Get-OriginMod($sb, [string]$Name) {
    $t = Get-OriginText $sb "mods/$Name/gamedata/scripts/$($Name.Replace(' ', '_')).script"
    if ($null -eq $t) { return $null }
    return $t.Replace("`r", '').TrimEnd("`n")
}
function Get-OriginPack($sb, [string]$Rev = 'main') {
    $t = Get-OriginText $sb 'pack/pack.json' $Rev
    if ($null -eq $t) { return $null }
    return ($t.TrimStart([char]0xFEFF) | ConvertFrom-Json)
}
function Get-OriginList($sb) { $p = Get-OriginPack $sb; return @($p.mods | ForEach-Object { [string]$_ }) }
function Get-OriginPaths($sb, [string]$Rev = 'main') {
    $r = Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, '-c', 'core.quotepath=false', 'ls-tree', '-r', '--name-only', $Rev)
    return @($r.Out -split "`n" | Where-Object { $_ })
}
# Commit directly in a clone and push (used to simulate changes outside publish).
function Push-Direct([string]$Repo, [scriptblock]$Change, [string]$Msg = 'direct') {
    G-Must -C $Repo pull -q --rebase
    & $Change
    G-Must -C $Repo add -A
    G-Must -C $Repo commit -q -m $Msg
    G-Must -C $Repo push -q
}

# ---------------------------------------------------------------- publish / installer runners
function Invoke-Publish($sb, [string]$Who, [string[]]$PubArgs = @(), [hashtable]$Env = @{}, [string]$Stdin = $null, [int]$TimeoutSec = 180) {
    $ps1 = Join-Path $sb[$Who] 'repo\host\publish.ps1'
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1) + @($PubArgs)
    $r = Invoke-Proc $script:PS_EXE $a (Get-ChildEnv $sb $Env) $Stdin $TimeoutSec
    # Another publish (a real host-mode agent, a parallel suite) may hold Local\xrrfix_publish for a moment:
    # retry runs deferred by the mutex unless this test holds the mutex itself.
    for ($i = 0; $i -lt 30 -and -not $script:HoldingMutex -and $r.Code -eq 2 -and $r.Out.Contains('publish уже выполняется'); $i++) {
        Write-Host '  (mutex held by another process - retrying)' -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
        $r = Invoke-Proc $script:PS_EXE $a (Get-ChildEnv $sb $Env) $Stdin $TimeoutSec
    }
    $script:LastLog = "--- publish $Who $($PubArgs -join ' ') -> $($r.Code)`n$($r.All)"
    if ($script:Verbose) { Write-Host $script:LastLog -ForegroundColor DarkGray }
    return $r
}
function Invoke-PublishPs1([string]$Ps1, $sb, [string[]]$PubArgs = @(), [hashtable]$Env = @{}) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Ps1) + @($PubArgs)
    return (Invoke-Proc $script:PS_EXE $a (Get-ChildEnv $sb $Env) $null 120)
}
# Publish that must succeed (setup step).
function Publish-Ok($sb, [string]$Who, [string[]]$PubArgs = @('-NoPrompt')) {
    $r = Invoke-Publish $sb $Who $PubArgs
    if ($r.Code -ne 0) { throw "setup publish $Who $($PubArgs -join ' ') exited $($r.Code):`n$($r.All)" }
    return $r
}
function Assert-Code([int]$Exp, $r, [string]$Msg = 'exit code') {
    if ($r.Code -ne $Exp) {
        $o = $r.All; if ($o.Length -gt 3000) { $o = $o.Substring($o.Length - 3000) }
        throw "Assert-Code failed: $Msg`n    expected: $Exp`n    actual:   $($r.Code)`n    output:`n$o"
    }
}
function Assert-Out($r, [string]$Literal, [string]$Msg = '') {
    if ($r.All.IndexOf($Literal, [StringComparison]::Ordinal) -lt 0) {
        $o = $r.All; if ($o.Length -gt 3000) { $o = $o.Substring($o.Length - 3000) }
        throw "Assert-Out failed: $Msg`n    missing: $Literal`n    output:`n$o"
    }
}
function Assert-NoOut($r, [string]$Literal, [string]$Msg = '') {
    if ($r.All.IndexOf($Literal, [StringComparison]::Ordinal) -ge 0) { throw "Assert-NoOut failed: $Msg`n    unexpected: $Literal" }
}
function Get-ResultLine($r) {
    $m = [regex]::Matches($r.Out, '(?m)^XRRFIX_SYNC_RESULT: .*?$')
    if ($m.Count -eq 0) { return $null }
    return $m[$m.Count - 1].Value.TrimEnd("`r")
}
function Get-ConflictLine($r) {
    $m = [regex]::Match($r.Out, '(?m)^XRRFIX_SYNC_CONFLICT: .*?$')
    if (-not $m.Success) { return $null }
    return $m.Value.TrimEnd("`r")
}
function Assert-NoTempLeft($sb, [string]$Msg = 'no xrrfix_sync_* temp folder left') {
    $left = @(Get-ChildItem -LiteralPath $sb.Tmp -Directory -Filter 'xrrfix_sync_*' -ErrorAction SilentlyContinue)
    Assert-Equal 0 $left.Count $Msg
}

# Standalone package for installer tests. $Mods: ordered hashtable name -> hashtable(relpath -> content string or byte[])
function New-Package([string]$Dir, [string]$Version = '2026.10.13-7', [string]$Section = 'xrRazom Sync', $Mods, [string[]]$Order = $null, [switch]$NoModLines, [string[]]$ExtraLines = @()) {
    New-Item -ItemType Directory -Path "$Dir\mods" -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'installer\install.ps1') -Destination "$Dir\install.ps1"
    if (-not $Order) { $Order = @($Mods.Keys) }
    foreach ($n in $Mods.Keys) {
        New-Item -ItemType Directory -Path (Join-Path "$Dir\mods" $n) -Force | Out-Null
        foreach ($rel in $Mods[$n].Keys) {
            $v = $Mods[$n][$rel]
            $p = Join-Path (Join-Path "$Dir\mods" $n) $rel
            if ($v -is [byte[]]) { Write-Bytes $p $v } else { Write-Text $p ([string]$v) }
        }
    }
    $txt = "version=$Version`nprofile=github`nsection=$Section`n" + (($ExtraLines | ForEach-Object { "$_`n" }) -join '') + "`n"
    if (-not $NoModLines) { $txt += (($Order | ForEach-Object { "[mod] $_`n  0123456789abcdef  gamedata\x.script" }) -join "`n") + "`n" }
    Write-Text "$Dir\pack.txt" $txt
    return $Dir
}
# Fake GAMMA root for installer tests.
function New-Gamma([string]$Root, [string[]]$Modlist = $null, [string]$Profile = 'P', [string[]]$Foreign = @(), [string[]]$Ours = @(), [switch]$NoIni) {
    New-Item -ItemType Directory -Path "$Root\mods", "$Root\profiles\$Profile" -Force | Out-Null
    Write-Bytes "$Root\ModOrganizer.exe" ([byte[]]@())
    if (-not $NoIni) { Write-Text "$Root\ModOrganizer.ini" "[General]`r`nselected_profile=@ByteArray($Profile)`r`n" }
    foreach ($n in $Foreign) { Write-Text "$Root\mods\$n\foreign.txt" "foreign $n`r`n" }
    foreach ($n in $Ours) { Write-Text "$Root\mods\$n\old.script" "old $n`r`n"; Write-Text "$Root\mods\$n\xrrfix_pack.txt" "xrRazom fixes pack 0`r`n" }
    if ($null -ne $Modlist) { Set-Modlist $Root $Modlist $Profile }
    return $Root
}
# Runs install.ps1. Default: through -Command with UTF-8 console output (as publish does), so messages are readable.
function Invoke-Installer([string]$PackDir, [string[]]$InsArgs = @(), [hashtable]$Env = @{}, [switch]$File, [string]$Lad = $null) {
    if (-not $Lad) { $Lad = $script:InsLad }
    $e = @{ LOCALAPPDATA = $Lad; XRRFIX_BLOCK_PROCS = $script:FAKE_PROC; TEMP = $script:InsTmp; TMP = $script:InsTmp }
    foreach ($k in $Env.Keys) { $e[$k] = $Env[$k] }
    $ps1 = Join-Path $PackDir 'install.ps1'
    if ($File) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1) + @($InsArgs)
        $r = Invoke-Proc $script:PS_EXE $a $e $null 120
    } else {
        function Q1([string]$s) { "'" + $s.Replace("'", "''") + "'" }
        $argText = (@($InsArgs) | ForEach-Object { if ($_ -like '-*') { $_ } else { Q1 $_ } }) -join ' '
        $cmd = "`$ProgressPreference = 'SilentlyContinue'; try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false) } catch { }; " +
               "& $(Q1 $ps1) $argText; exit `$LASTEXITCODE"
        $r = Invoke-Proc $script:PS_EXE @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NonInteractive', '-Command', $cmd) $e $null 120
    }
    $script:LastLog = "--- install $($InsArgs -join ' ') -> $($r.Code)`n$($r.All)"
    if ($script:Verbose) { Write-Host $script:LastLog -ForegroundColor DarkGray }
    return $r
}

# ---------------------------------------------------------------- fake MO2 process and mutex holder
function Start-FakeMO2([int]$Seconds = 600, [string]$Name = $script:FAKE_PROC) {
    $exe = Join-Path $script:TestRoot "$Name.exe"
    if (-not (Test-Path -LiteralPath $exe)) { Copy-Item (Join-Path $env:WINDIR 'System32\PING.EXE') $exe }
    $p = Start-Process -FilePath $exe -ArgumentList @('-n', ($Seconds + 1), '127.0.0.1') -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 50 -and -not (Get-Process -Name $Name -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
    return $p
}
function Stop-FakeMO2($p) {
    if ($p) { try { if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit(5000) | Out-Null } } catch { } }
}
# Holds Local\xrrfix_publish in another process for $Seconds; -Abandon: exit without releasing.
function Start-MutexHolder([int]$Seconds = 30, [switch]$Abandon) {
    $script:HoldingMutex = $true
    $ready = Join-Path $script:TestRoot ("mutex_ready_" + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    $rel = if ($Abandon) { '' } else { '$m.ReleaseMutex();' }
    $cmd = "`$m = New-Object Threading.Mutex(`$false, 'Local\xrrfix_publish'); try { [void]`$m.WaitOne() } catch [Threading.AbandonedMutexException] { }; " +
           "[IO.File]::WriteAllText('$ready', 'x'); Start-Sleep -Seconds $Seconds; $rel"
    $p = Start-Process -FilePath $script:PS_EXE -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', "`"$cmd`"") -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 150 -and -not (Test-Path -LiteralPath $ready); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $ready)) { throw 'mutex holder did not start' }
    return $p
}
