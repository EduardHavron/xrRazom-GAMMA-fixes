# installer/install.ps1 cases: INS-* (spec: specs/system/installer.md). Dot-sourced by run.ps1.
# Safety: every run without -GammaRoot has its package inside a fake GAMMA root (or a valid saved path), so root
# discovery never reaches the drive scan (INS-004 step 3) that could find a real GAMMA on a developer machine.

$script:InsNo = 0
function New-InsCase {
    $script:InsNo++
    $d = Join-Path $script:TestRoot ('i{0:d3}' -f $script:InsNo)
    New-Item -ItemType Directory -Path "$d\lad" -Force | Out-Null
    return @{ Dir = $d; G = "$d\G"; Lad = "$d\lad"; Pkg = "$d\G\tmp\pkg" }
}
function Std-Mods { $m = [ordered]@{}; $m['P1'] = @{ 'gamedata\scripts\p1.script' = "p1`r`n" }; $m['P2'] = @{ 'gamedata\scripts\p2.script' = "p2`n" }; return $m }
function Ins($c, [string[]]$InsArgs = @(), [hashtable]$Env = @{}, [switch]$File) {
    return (Invoke-Installer $c.Pkg $InsArgs $Env -File:$File -Lad $c.Lad)
}
function Get-Saved($c) {
    $p = "$($c.Lad)\xrrfix\gamma_root.txt"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return (Read-Text $p).TrimStart([char]0xFEFF).Trim()
}
function Set-Saved($c, [string]$Root) { Write-Text "$($c.Lad)\xrrfix\gamma_root.txt" "$Root`r`n" }

Test-Case 'INS-002 install.ps1 UTF-8 BOM, parses in PS 5.1; install.bat ASCII + CRLF' {
    $p = Join-Path $script:RepoRoot 'installer\install.ps1'
    $b = [IO.File]::ReadAllBytes($p)
    Assert-True ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'BOM'
    $tokens = $null; $errs = $null
    [void][Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errs)
    Assert-Equal 0 @($errs).Count "parse errors: $(@($errs) -join '; ')"
    $bat = [IO.File]::ReadAllBytes((Join-Path $script:RepoRoot 'installer\install.bat'))
    Assert-Equal 0 @($bat | Where-Object { $_ -gt 127 }).Count 'install.bat ASCII'
    $txt = [Text.Encoding]::ASCII.GetString($bat)
    Assert-Equal 0 ([regex]::Matches($txt, '(?<!\r)\n')).Count 'install.bat CRLF only'
}

Test-Case 'INS-003 -GammaRoot with trailing \ is used as is, no discovery, saved path untouched' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+P1', "+$script:SEP") | Out-Null
    $other = New-Gamma "$($c.Dir)\Other" @('# h', "+$script:SEP")
    Set-Saved $c $other
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', "$($c.G)\")
    Assert-Code 0 $r
    Assert-Out $r "GAMMA: $($c.G)`n" 'trailing \ trimmed'
    Assert-PathExists "$($c.G)\mods\P1\xrrfix_pack.txt"
    Assert-PathMissing "$other\mods\P1"
    Assert-Equal $other (Get-Saved $c) 'gamma_root.txt unchanged'
}

Test-Case 'INS-003 -GammaRoot without ModOrganizer.exe/mods -> exit 1, nothing changed' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+P1', "+$script:SEP") | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $empty = "$($c.Dir)\Empty"; New-Item -ItemType Directory $empty | Out-Null
    $snap = Get-DirSnapshot $c.Dir
    $r = Ins $c @('-NoWait', '-GammaRoot', $empty)
    Assert-Code 1 $r
    Assert-Out $r 'нет ModOrganizer.exe и папки mods'
    Assert-True ($snap -ceq (Get-DirSnapshot $c.Dir)) 'no files changed'
}

Test-Case 'INS-004 discovery: valid saved path wins over package location' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    $g1 = New-Gamma "$($c.Dir)\G1" @('# h', "+$script:SEP")
    Set-Saved $c $g1
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait')
    Assert-Code 0 $r
    Assert-Out $r "GAMMA: $g1"
    Assert-PathExists "$g1\mods\P1"
    Assert-PathMissing "$($c.G)\mods\P1"
}

Test-Case 'INS-004 INS-005 discovery: stale saved path -> package parents; found root is saved' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    Set-Saved $c "$($c.Dir)\Deleted"
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait')
    Assert-Code 0 $r
    Assert-Out $r "GAMMA: $($c.G)"
    Assert-PathExists "$($c.G)\mods\P2"
    Assert-Equal $c.G (Get-Saved $c)
}

Test-Case 'INS-005 INS-007 found root is saved even when deferred (exit 2), nothing else changes' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+P1', "+$script:SEP", '+Below') -Foreign @('Below') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $snapM = Get-DirSnapshot "$($c.G)\mods"; $snapP = Get-DirSnapshot "$($c.G)\profiles"
    $p = Start-FakeMO2 60
    try { $r = Ins $c @('-NoWait') } finally { Stop-FakeMO2 $p }
    Assert-Code 2 $r
    Assert-Out $r 'Mod Organizer запущен - установка отложена.'
    Assert-Equal $c.G (Get-Saved $c) 'saved before the process check'
    Assert-True ($snapM -ceq (Get-DirSnapshot "$($c.G)\mods")) 'mods untouched (no separator folder)'
    Assert-True ($snapP -ceq (Get-DirSnapshot "$($c.G)\profiles")) 'modlist untouched, no backup'
}

Test-Case 'INS-006 XRRFIX_BLOCK_PROCS parsing: trims, drops empties, wildcards; "," = none; default ModOrganizer' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $p = Start-FakeMO2 60
    try { $r = Ins $c @('-NoWait', '-GammaRoot', $c.G) @{ XRRFIX_BLOCK_PROCS = ' foo , ,' + $script:FAKE_PROC.Substring(0, 10) + '*' } }
    finally { Stop-FakeMO2 $p }
    Assert-Code 2 $r 'wildcard entry blocks'
    $mo = Start-FakeMO2 60 'ModOrganizer'
    try {
        $r1 = Ins $c @('-NoWait', '-GammaRoot', $c.G) @{ XRRFIX_BLOCK_PROCS = ',' }
        $r2 = Ins $c @('-NoWait', '-GammaRoot', $c.G) @{ XRRFIX_BLOCK_PROCS = ' foo , ' }
        $r3 = Ins $c @('-NoWait', '-GammaRoot', $c.G) @{ XRRFIX_BLOCK_PROCS = $null }
    } finally { Stop-FakeMO2 $mo }
    Assert-Code 0 $r1 '"," -> no blocking processes (ModOrganizer running)'
    Assert-Code 0 $r2 'explicit list replaces ModOrganizer'
    Assert-Code 2 $r3 'default list = ModOrganizer'
}

Test-Case 'INS-009 pack.txt: version, section, [mod] lines; other lines ignored; missing pack.txt -> exit 1' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Old_separator', '+Test_separator', '+Below') -Foreign @('Below') | Out-Null
    New-Package $c.Pkg -Version '9.9' -Section 'Test' -Mods (Std-Mods) -Order @('P2', 'P1') -ExtraLines @('profile=ignored', 'junk line') | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal '# h|+Old_separator|+P2|+P1|+Test_separator|+Below' (Join-L (Get-Modlist $c.G))
    Assert-Equal 'xrRazom fixes pack 9.9' (Read-Text "$($c.G)\mods\P1\xrrfix_pack.txt").TrimStart([char]0xFEFF).Trim()

    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    Remove-Item -LiteralPath "$($c.Pkg)\pack.txt"
    $snap = Get-DirSnapshot "$($c.G)\mods"
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 1 $r 'no pack.txt'
    Assert-True ($snap -ceq (Get-DirSnapshot "$($c.G)\mods")) 'mods unchanged'
}

Test-Case 'INS-010 no [mod] lines -> folder names in alphabetical order' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    $m = [ordered]@{}; $m['B'] = @{ 'b.txt' = 'b' }; $m['A'] = @{ 'a.txt' = 'a' }
    New-Package $c.Pkg -Mods $m -NoModLines | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal '+A|+B' (Join-L (Get-Section $c.G))
}

Test-Case 'INS-011 INS-012 mod folder replaced entirely (LiteralPath, [ ] names), byte-exact, marker with BOM' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    Write-Text "$($c.G)\mods\P1\old.script" 'old'
    $bin = [byte[]](0..255)
    $m = [ordered]@{}
    $m['P1'] = @{ 'gamedata\scripts\new.script' = "a`r`nb`n"; 'gamedata\t.dds' = $bin }
    $m['zz Fix [test]'] = @{ 'gamedata\x.script' = "x`r`n" }
    New-Package $c.Pkg -Mods $m | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-PathMissing "$($c.G)\mods\P1\old.script"
    Assert-Out $r '  установлен: P1'
    Assert-Out $r '  установлен: zz Fix [test]'
    foreach ($n in 'P1', 'zz Fix [test]') {
        $exp = (Get-DirSnapshot "$($c.Pkg)\mods\$n")
        $got = ((Get-DirSnapshot "$($c.G)\mods\$n") -split "`n" | Where-Object { $_ -notlike 'xrrfix_pack.txt|*' }) -join "`n"
        Assert-Equal $exp $got "files of $n = package (byte-exact) + marker"
    }
    $mk = [IO.File]::ReadAllBytes("$($c.G)\mods\P1\xrrfix_pack.txt")
    Assert-True ($mk[0] -eq 0xEF -and $mk[1] -eq 0xBB -and $mk[2] -eq 0xBF) 'marker UTF-8 BOM'
    Assert-Equal 'xrRazom fixes pack 2026.10.13-7' (Read-Text "$($c.G)\mods\P1\xrrfix_pack.txt").TrimStart([char]0xFEFF).Trim()
    Assert-Equal '+P1|+zz Fix [test]' (Join-L (Get-Section $c.G))
}

Test-Case 'INS-013 separator folder created with meta.ini; existing one untouched' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "[General]`r`nmodid=0`r`nversion=`r`nnewestVersion=`r`ncategory=0`r`ninstallationFile=`r`n" ((Read-Text "$($c.G)\mods\$script:SEP\meta.ini").TrimStart([char]0xFEFF))
    Write-Text "$($c.G)\mods\$script:SEP\meta.ini" 'custom'
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal 'custom' (Read-Text "$($c.G)\mods\$script:SEP\meta.ini")
}

Test-Case 'INS-014 profile: @ByteArray(...) from ini; -Profile overrides; missing ModOrganizer.ini -> exit 1' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") -Profile 'G.A.M.M.A' | Out-Null
    New-Item -ItemType Directory "$($c.G)\profiles\Test" | Out-Null
    Set-Modlist $c.G @('# t', "+$script:SEP") 'Test'
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal '+P1|+P2' (Join-L (Get-Section $c.G $script:SEP 'G.A.M.M.A')) 'selected_profile used'
    Assert-Equal "# t|+$script:SEP" (Join-L (Get-Modlist $c.G 'Test')) 'other profile untouched'
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G, '-Profile', 'Test')
    Assert-Code 0 $r
    Assert-Equal '+P1|+P2' (Join-L (Get-Section $c.G $script:SEP 'Test')) '-Profile used'

    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") -NoIni | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $ml = Get-FileSha "$($c.G)\profiles\P\modlist.txt"
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G, '-Profile', 'P')
    Assert-Code 1 $r 'no ModOrganizer.ini'
    Assert-Equal $ml (Get-FileSha "$($c.G)\profiles\P\modlist.txt") 'modlist untouched'
}

Test-Case 'INS-015 INS-027 backup = modlist before the run; rerun is idempotent' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Old', "+$script:SEP", '+Below') -Foreign @('Below') -Ours @('Old') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $orig = Read-Text "$($c.G)\profiles\P\modlist.txt"
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal $orig (Read-Text "$($c.G)\profiles\P\modlist.txt.xrrfix.bak") 'backup of the original'
    $after1 = Read-Text "$($c.G)\profiles\P\modlist.txt"
    $snap1 = Get-DirSnapshot "$($c.G)\mods"
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal $after1 (Read-Text "$($c.G)\profiles\P\modlist.txt") 'idempotent modlist'
    Assert-Equal $after1 (Read-Text "$($c.G)\profiles\P\modlist.txt.xrrfix.bak") 'backup overwritten with the 1st result'
    Assert-True ($snap1 -ceq (Get-DirSnapshot "$($c.G)\mods")) 'idempotent mod folders'
}

Test-Case 'INS-016 INS-019 section bounds: lines above our separator up to the previous separator' {
    $c = New-InsCase
    New-Gamma $c.G @('#hdr', '+X', '-Other_separator', '+A', '+B', "-$script:SEP") -Foreign @('X', 'A', 'B') | Out-Null
    $m = [ordered]@{}; $m['P'] = @{ 'p.txt' = 'p' }
    New-Package $c.Pkg -Mods $m | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "#hdr|+X|-Other_separator|+P|+$script:SEP|+A|+B" (Join-L (Get-Modlist $c.G))
    Assert-Out $r 'перенесён из секции: A'
}

Test-Case 'INS-017 INS-029 package mod found elsewhere (any state, duplicates, other case) moves into the section' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Above', '+ZZ fix a', '+Other_separator', '+P1', "+$script:SEP", '-zz Fix A', '+Below', '-P2') -Foreign @('Above', 'Below') | Out-Null
    $m = [ordered]@{}; $m['P1'] = @{ 'a' = '1' }; $m['zz Fix A'] = @{ 'a' = '2' }; $m['P2'] = @{ 'a' = '3' }
    New-Package $c.Pkg -Mods $m | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+Above|+Other_separator|+P1|+zz Fix A|+P2|+$script:SEP|+Below" (Join-L (Get-Modlist $c.G))
}

Test-Case 'INS-018 our mods in the section that are not in the package stay disabled after package mods' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Old', '+P1', '-Old2', "+$script:SEP", '+Below') -Foreign @('Below') -Ours @('Old', 'Old2') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+P1|+P2|-Old|-Old2|+$script:SEP|+Below" (Join-L (Get-Modlist $c.G))
    Assert-Out $r 'выключен (нет в пакете): Old'
    Assert-NoOut $r 'выключен (нет в пакете): Old2' 'already disabled: no message'
    Assert-PathExists "$($c.G)\mods\Old\old.script" 'folder kept'
}

Test-Case 'INS-019 foreign mods in the section move right under the separator, state kept' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Test Mod', '+P1', '-Test Off', "+$script:SEP", '+Below') -Foreign @('Test Mod', 'Test Off', 'Below') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+P1|+P2|+$script:SEP|+Test Mod|-Test Off|+Below" (Join-L (Get-Modlist $c.G))
    Assert-Out $r 'перенесён из секции: Test Mod'
    Assert-PathExists "$($c.G)\mods\Test Mod\foreign.txt"
}

Test-Case 'INS-020 legacy "zz xrRazom Fixes" and marker-bearing old fixes outside the section are disabled in place' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+Above', '+zz xrRazom Fixes', '+Old_separator', "+$script:SEP", '+OldFix', '-OldFix2', '+Below') -Foreign @('Above', 'Below', 'zz xrRazom Fixes') -Ours @('OldFix', 'OldFix2') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+Above|-zz xrRazom Fixes|+Old_separator|+P1|+P2|+$script:SEP|-OldFix|-OldFix2|+Below" (Join-L (Get-Modlist $c.G))
    Assert-Out $r 'выключен старый фикс вне секции: zz xrRazom Fixes'
    Assert-Out $r 'выключен старый фикс вне секции: OldFix'
}

Test-Case 'INS-021 INS-028 SYS-004 foreign lines outside the section keep bytes, order and state; folders untouched' {
    $c = New-InsCase
    $above = @(1..50 | ForEach-Object { if ($_ % 3 -eq 0) { "-Up $_" } elseif ($_ % 7 -eq 0) { "*Up $_" } else { "+Up $_" } })
    $below = @(1..50 | ForEach-Object { if ($_ % 4 -eq 0) { "-Dn $_" } else { "+Dn $_ Мод" } })
    New-Gamma $c.G (@('# h') + $above + @('+Up_separator', '+P1', "+$script:SEP") + $below) -Foreign @('Up 1', 'Dn 2 Мод', 'Dn 4') | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $fs = Get-DirSnapshot "$($c.G)\mods\Up 1"; $fs2 = Get-DirSnapshot "$($c.G)\mods\Dn 2 Мод"
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal (Join-L (@('# h') + $above + @('+Up_separator', '+P1', '+P2', "+$script:SEP") + $below)) (Join-L (Get-Modlist $c.G))
    Assert-True ($fs -ceq (Get-DirSnapshot "$($c.G)\mods\Up 1")) 'foreign folder untouched'
    Assert-True ($fs2 -ceq (Get-DirSnapshot "$($c.G)\mods\Dn 2 Мод")) 'foreign folder untouched'
}

Test-Case 'INS-022 result assembly (spec example)' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+F1', '+P2', '-Old', '+Foreign', "-$script:SEP", '+Below') -Foreign @('F1', 'Foreign', 'Below') -Ours @('Old') | Out-Null
    $m = [ordered]@{}; $m['P1'] = @{ 'a' = '1' }; $m['P2'] = @{ 'a' = '2' }
    New-Package $c.Pkg -Mods $m | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+P1|+P2|-Old|+$script:SEP|+F1|+Foreign|+Below" (Join-L (Get-Modlist $c.G))
}

Test-Case 'INS-022 "#" lines go first, empty lines dropped' {
    $c = New-InsCase
    New-Gamma $c.G $null | Out-Null
    Write-Text "$($c.G)\profiles\P\modlist.txt" "# h`r`n+A`r`n`r`n# mid`r`n+P1`r`n+$script:SEP`r`n`r`n+B`r`n"
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h`r`n# mid`r`n+A`r`n+P1`r`n+P2`r`n+$script:SEP`r`n+B`r`n" (Read-Text "$($c.G)\profiles\P\modlist.txt")
}

Test-Case 'INS-023 no separator line: block inserted after the comments' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', '+A', '+B', '+OldFix') -Foreign @('A', 'B') -Ours @('OldFix') | Out-Null
    $m = [ordered]@{}; $m['P'] = @{ 'a' = '1' }
    New-Package $c.Pkg -Mods $m | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Equal "# h|+P|+$script:SEP|+A|+B|-OldFix" (Join-L (Get-Modlist $c.G))
}

Test-Case 'INS-024 no modlist.txt -> message, exit 0, nothing created' {
    $c = New-InsCase
    New-Gamma $c.G $null | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    Assert-Out $r 'включите моды в MO2 вручную'
    Assert-PathMissing "$($c.G)\profiles\P\modlist.txt"
    Assert-PathMissing "$($c.G)\profiles\P\modlist.txt.xrrfix.bak"
    Assert-PathExists "$($c.G)\mods\P1\xrrfix_pack.txt" 'mods copied'
}

Test-Case 'INS-025 modlist read as UTF-8 (BOM ok), written without BOM, CRLF incl. last line, Cyrillic intact' {
    $c = New-InsCase
    New-Gamma $c.G $null -Foreign @('Мод Кириллица') | Out-Null
    $txt = "# h`n+P1`n+$script:SEP`n+Мод Кириллица"
    Write-Bytes "$($c.G)\profiles\P\modlist.txt" ([byte[]](@(0xEF, 0xBB, 0xBF) + @($script:UTF8NoBom.GetBytes($txt))))
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    $r = Ins $c @('-NoWait', '-GammaRoot', $c.G)
    Assert-Code 0 $r
    $b = [IO.File]::ReadAllBytes("$($c.G)\profiles\P\modlist.txt")
    Assert-False ($b[0] -eq 0xEF) 'no BOM'
    Assert-Equal "# h`r`n+P1`r`n+P2`r`n+$script:SEP`r`n+Мод Кириллица`r`n" ($script:UTF8NoBom.GetString($b))
}

Test-Case 'INS-030 INS-004 legacy call "install.ps1 -NoWait" (powershell -File): saved root + active profile' {
    $c = New-InsCase
    New-Gamma $c.G @('# h', "+$script:SEP") -Profile 'Active' | Out-Null
    New-Package $c.Pkg -Mods (Std-Mods) | Out-Null
    Set-Saved $c $c.G
    $r = Ins $c @('-NoWait') -File
    Assert-Code 0 $r
    Assert-Equal '+P1|+P2' (Join-L (Get-Section $c.G $script:SEP 'Active'))
}

Skip-Case 'INS-004 drive scan (step 3) / folder dialog (step 4)' 'not automated: would scan real drives (a real GAMMA may exist) / needs UI'
