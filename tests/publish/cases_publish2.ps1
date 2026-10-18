# publish.ps1 cases, part 2: PUB-017 .. PUB-044 (spec: specs/system/publish.md). Dot-sourced by run.ps1.

function Assert-Null-Result($r) { Assert-Equal $null (Get-ResultLine $r) 'no XRRFIX_SYNC_RESULT line in normal mode without catch-up' }

# ---------------------------------------------------------------- -TakeRemote / -TakeLocal
Test-Case 'PUB-017 PUB-022 conflict -> exit 3 also with -SyncOnly; -TakeRemote "<name>" installs R' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'zz Фикс Y' 'Y-host'; Publish-Ok $sb 'H' | Out-Null
    Set-Mod $sb.F 'zz Фикс Y' 'Y-friend'
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal 'XRRFIX_SYNC_CONFLICT: mods=zz Фикс Y' (Get-ConflictLine $r)
    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt', '-NoWait')
    Assert-Code 3 $r '-SyncOnly also stops on conflict'
    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt', '-NoWait', '-TakeRemote', 'zz Фикс Y')
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=zz Фикс Y' (Get-ResultLine $r)
    Assert-Equal 'Y-host' (Get-Mod $sb.F 'zz Фикс Y')
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Изменений нет'
}

Test-Case 'PUB-017 -TakeRemote on a local (non-conflict) mod reverts it; sync mods unaffected' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'modA' 'A-local'
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt', '-TakeRemote', 'modA,modX')
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=modA' (Get-ResultLine $r)
    Assert-Equal 'v1 modA' (Get-Mod $sb.H 'modA')
}

Test-Case 'PUB-017 -TakeLocal "A,B" resolves both conflicts locally' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Set-Mod $sb.F 'modB' 'B-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modA' 'A-H'; Set-Mod $sb.H 'modB' 'B-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-TakeLocal', 'modA,modB')
    Assert-Code 0 $r
    Assert-Equal 'A-H' (Get-OriginMod $sb 'modA')
    Assert-Equal 'B-H' (Get-OriginMod $sb 'modB')
}

Test-Case 'PUB-017 -TakeLocal "*" keeps all conflicting mods local' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'modA' 'A-host3'; Publish-Ok $sb 'H' | Out-Null
    Set-Mod $sb.F 'modA' 'A-friend3'
    $r = Invoke-Publish $sb 'F' @('-NoPrompt', '-TakeLocal', '*')
    Assert-Code 0 $r
    Assert-Equal 'A-friend3' (Get-OriginMod $sb 'modA')
}

Test-Case 'PUB-017 -TakeRemote "*" affects only conflicts (local mod stays local)' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modB' 'B-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modB' 'B-H'; Set-Mod $sb.H 'modA' 'A-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-TakeRemote', '*')
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=modB' (Get-ResultLine $r)
    Assert-Equal 'B-F' (Get-Mod $sb.H 'modB')
    Assert-Equal 'B-F' (Get-OriginMod $sb 'modB')
    Assert-Equal 'A-H' (Get-OriginMod $sb 'modA')
}

Test-Case 'PUB-017 mod named in both -> -TakeRemote wins; unknown name warns and is skipped' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modA' 'A-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-TakeRemote', 'modA', '-TakeLocal', 'modA,nope')
    Assert-Code 0 $r
    Assert-Out $r "мод 'nope' не найден ни локально, ни в репозитории"
    Assert-Equal 'A-F' (Get-Mod $sb.H 'modA')
    Assert-Equal 'A-F' (Get-OriginMod $sb 'modA')
}

# ---------------------------------------------------------------- order
Test-Case 'PUB-019 PUB-035 PUB-021 PUB-023 local-only reorder: only pack.json changes; peer gets order (installed=0)' {
    $sb = New-Sandbox
    Set-SectionOrder $sb.H @('modX', 'zz Фикс Y', 'modB', 'modA')
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[*] порядок модов (pack.json)'
    Assert-Equal 'Update fixes: mod order' ((Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, 'log', '-1', '--format=%s', 'main')).Out.Trim())
    $names = (Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, '-c', 'core.quotepath=false', 'show', '--name-only', '--format=', 'main')).Out.Trim()
    Assert-Equal 'pack/pack.json' $names 'commit changes only pack.json'
    $exp = "{`n  `"section`": `"xrRazom Sync`",`n  `"mods`": [`n    `"modX`",`n    `"zz Фикс Y`",`n    `"modB`",`n    `"modA`"`n  ]`n}`n"
    Assert-Equal $exp (Get-OriginText $sb 'pack/pack.json') 'pack.json bytes (REPO-005 format)'
    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt', '-NoWait')
    Assert-Code 0 $r
    Assert-Out $r '[<] порядок модов (с GitHub)'
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=0 mods=' (Get-ResultLine $r)
    Assert-Equal '+modX|+zz Фикс Y|+modB|+modA' (Join-L (Get-Section $sb.F))
    Assert-PathExists "$($sb.F)\profiles\P\modlist.txt.xrrfix.bak" 'installer ran'
}

Test-Case 'PUB-019 PUB-022 order conflict -> exit 3 "(порядок модов)"; -TakeRemote * takes R order' {
    $sb = New-Sandbox
    Set-SectionOrder $sb.H @('modX', 'zz Фикс Y', 'modB', 'modA'); Publish-Ok $sb 'H' | Out-Null
    Set-SectionOrder $sb.F @('zz Фикс Y', 'modX', 'modA', 'modB')
    $ml = Get-FileSha "$($sb.F)\profiles\P\modlist.txt"
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal 'XRRFIX_SYNC_CONFLICT: mods=(порядок модов)' (Get-ConflictLine $r)
    Assert-Out $r '[!] порядок модов изменён и локально, и на GitHub'
    Assert-Out $r 'publish.bat -SyncOnly -TakeRemote "*"'
    Assert-Equal $ml (Get-FileSha "$($sb.F)\profiles\P\modlist.txt") 'modlist unchanged'
    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt', '-TakeRemote', '*')
    Assert-Code 0 $r
    Assert-Equal '+modX|+zz Фикс Y|+modB|+modA' (Join-L (Get-Section $sb.F))
}

Test-Case 'PUB-019 order conflict + -TakeLocal * publishes the local order' {
    $sb = New-Sandbox
    Set-SectionOrder $sb.H @('modX', 'zz Фикс Y', 'modB', 'modA'); Publish-Ok $sb 'H' | Out-Null
    Set-SectionOrder $sb.F @('zz Фикс Y', 'modX', 'modA', 'modB')
    $r = Invoke-Publish $sb 'F' @('-NoPrompt', '-TakeLocal', '*')
    Assert-Code 0 $r
    Assert-Equal 'zz Фикс Y|modX|modA|modB' (Join-L (Get-OriginList $sb))
    Assert-Equal '+zz Фикс Y|+modX|+modA|+modB' (Join-L (Get-Section $sb.F))
}

Test-Case 'PUB-019 additions and removals are not reorders (no conflict)' {
    $sb = New-Sandbox
    Add-NewMod $sb.F 'modN' 'N1'; Publish-Ok $sb 'F' @('-NoPrompt', '-Yes') | Out-Null
    Remove-FromModlist $sb.H 'modX'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'zz Фикс Y|modB|modA|modN' (Join-L (Get-OriginList $sb))
}

Test-Case 'PUB-020 PUB-018 result list: new local mod keeps its place' {
    $sb = New-Sandbox
    Add-NewMod $sb.H 'modD' 'D1' 'modX'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Yes')
    Assert-Code 0 $r
    Assert-Out $r '[>] modD - новый мод'
    Assert-Equal 'zz Фикс Y|modX|modD|modB|modA' (Join-L (Get-OriginList $sb))
}

Test-Case 'PUB-020 result list: mod added on GitHub at the top lands at the top' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modN' 'N1'
    Set-SectionOrder $sb.F @('modN', 'zz Фикс Y', 'modX', 'modB', 'modA')
    Publish-Ok $sb 'F' @('-NoPrompt', '-Yes') | Out-Null
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal '+modN|+zz Фикс Y|+modX|+modB|+modA' (Join-L (Get-Section $sb.H))
}

Test-Case 'PUB-020 result list: local reorder + remote insert -> N right after its R predecessor' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modN' 'N1'
    Set-SectionOrder $sb.F @('zz Фикс Y', 'modN', 'modX', 'modB', 'modA')
    Publish-Ok $sb 'F' @('-NoPrompt', '-Yes') | Out-Null
    Set-SectionOrder $sb.H @('modX', 'zz Фикс Y', 'modB', 'modA')
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal '+modX|+zz Фикс Y|+modN|+modB|+modA' (Join-L (Get-Section $sb.H))
}

Test-Case 'PUB-021 report header and "всё совпадает"' {
    $sb = New-Sandbox
    $o = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r "Сравнение с GitHub (origin/main $($o.Substring(0,7))):"
    Assert-Out $r '  всё совпадает'
    Assert-Null-Result $r
}

Test-Case 'PUB-022 PUB-042 two conflicts: line, hints, nothing changed, no temp, mutex released' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Set-Mod $sb.F 'modB' 'B-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modA' 'A-H'; Set-Mod $sb.H 'modB' 'B-H'
    $snap = Get-DirSnapshot "$($sb.H)\mods"; $ml = Get-FileSha "$($sb.H)\profiles\P\modlist.txt"
    $h0 = Get-HeadSha "$($sb.H)\repo"; $o0 = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal 'XRRFIX_SYNC_CONFLICT: mods=modB,modA' (Get-ConflictLine $r) 'names in L order'
    Assert-Out $r 'publish.bat -SyncOnly -TakeRemote "modB"'
    Assert-Out $r 'publish.bat -TakeLocal "modB"'
    Assert-True ($snap -ceq (Get-DirSnapshot "$($sb.H)\mods")) 'mods unchanged'
    Assert-Equal $ml (Get-FileSha "$($sb.H)\profiles\P\modlist.txt") 'modlist unchanged'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'
    Assert-Equal $o0 (Get-OriginSha $sb) 'origin unchanged'
    Assert-NoTempLeft $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt', '-NoWait')
    Assert-Code 3 $r 'mutex released after exit 3 (not 2)'
}

# ---------------------------------------------------------------- catch-up
Test-Case 'PUB-023 PUB-029 PUB-031 remote change outside mods/pack: no catch-up, HEAD = R' {
    $sb = New-Sandbox
    Push-Direct "$($sb.F)\repo" { Write-Text "$($sb.F)\repo\README.md" "changed`n"; Write-Text "$($sb.F)\repo\installer\README.txt" "x`r`n" } 'docs'
    $ml = Get-FileSha "$($sb.H)\profiles\P\modlist.txt"
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-NoOut $r 'Ставлю изменения'
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=0 mods=' (Get-ResultLine $r)
    Assert-PathMissing "$($sb.H)\profiles\P\modlist.txt.xrrfix.bak" 'installer not run'
    Assert-Equal $ml (Get-FileSha "$($sb.H)\profiles\P\modlist.txt")
    Assert-Equal (Get-OriginSha $sb) (Get-HeadSha "$($sb.H)\repo") 'HEAD = R'

    Push-Direct "$($sb.F)\repo" { Write-Text "$($sb.F)\repo\README.md" "changed again`n" } 'docs2'
    Set-Mod $sb.H 'modX' 'X-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Null-Result $r
    Assert-Equal 'X-H' (Get-OriginMod $sb 'modX')
}

Test-Case 'PUB-024 PUB-044 SYS-009 blocking process + -SyncOnly -NoWait -> exit 2, MO2 and HEAD untouched' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modB' 'B5'; Publish-Ok $sb 'F' | Out-Null
    $snap = Get-DirSnapshot "$($sb.H)\mods"; $ml = Get-FileSha "$($sb.H)\profiles\P\modlist.txt"; $h0 = Get-HeadSha "$($sb.H)\repo"
    $p = Start-FakeMO2 120
    try {
        $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt') @{ XRRFIX_BLOCK_PROCS = "zzz_none_t2, $($script:FAKE_PROC.Substring(0, 12))*" } -TimeoutSec 90
    } finally { Stop-FakeMO2 $p }
    Assert-Code 2 $r
    Assert-Out $r 'установка изменений с GitHub отложена'
    Assert-True ($r.Sec -lt 60) "finished in $($r.Sec)s"
    Assert-True ($snap -ceq (Get-DirSnapshot "$($sb.H)\mods")) 'mods unchanged'
    Assert-Equal $ml (Get-FileSha "$($sb.H)\profiles\P\modlist.txt") 'modlist unchanged'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'
    Assert-NoTempLeft $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r 'after the process is gone'
    Assert-Equal 'B5' (Get-Mod $sb.H 'modB')
    Assert-PathExists "$($sb.H)\mods\modB\xrrfix_pack.txt" 'marker written by installer'
}

Test-Case 'PUB-024 blocking process does not matter when no catch-up is needed' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'modX' 'X-H'
    $p = Start-FakeMO2 120
    try { $r = Invoke-Publish $sb 'H' @('-NoPrompt') -TimeoutSec 60 } finally { Stop-FakeMO2 $p }
    Assert-Code 0 $r
    Assert-Equal 'X-H' (Get-OriginMod $sb 'modX')
}

Test-Case 'PUB-024 -NoPrompt without -NoWait polls until the process exits' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-e4'; Publish-Ok $sb 'F' | Out-Null
    $p = Start-FakeMO2 6
    try { $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt') -TimeoutSec 90 } finally { Stop-FakeMO2 $p }
    Assert-Code 0 $r
    Assert-Out $r 'Жду закрытия Mod Organizer и игры...'
    Assert-Equal 'A-e4' (Get-Mod $sb.H 'modA')
}

Test-Case 'PUB-025 PUB-026 PUB-028 PUB-029 temp package: content, pack.txt, installer copy, args, indented output' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    Push-Direct "$($sb.F)\repo" { Write-PackJson "$($sb.F)\repo\pack\pack.json" 'xrRazom Sync' (@($script:SEED_ORDER) + 'modE') } 'modE without files'
    Set-Mod $sb.H 'modX' 'X-local-unpub'
    Write-Text "$($sb.H)\mods\modA\meta.ini" "[General]`r`nmodid=42`r`n"
    Set-Stub $sb 'H'
    $stubSha = Get-FileSha "$($sb.H)\repo\installer\install.ps1"
    $cap = Join-Path $sb.Cap 'pkg'
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt') @{ XRRFIX_T2_CAPTURE = $cap; XRRFIX_T2_RC = '0' }
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=2 mods=modA,modE' (Get-ResultLine $r)
    Assert-Match $r.Out '(?m)^  STUB-LINE-1\r?$' 'installer output indented by 2 spaces'
    $sha7 = (Get-OriginSha $sb).Substring(0, 7)
    $exp = "version=sync-$sha7`nprofile=github`nsection=xrRazom Sync`n`n[mod] zz Фикс Y`n[mod] modX`n[mod] modB`n[mod] modA`n[mod] modE`n"
    $bytes = [IO.File]::ReadAllBytes("$cap\pack.txt")
    Assert-False ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF) 'pack.txt without BOM'
    Assert-Equal $exp (Read-Text "$cap\pack.txt") 'pack.txt'
    Assert-Equal $stubSha (Get-FileSha "$cap\install.ps1") 'install.ps1 copied from the working tree'
    Assert-Equal "A-F`r`n" (Read-Text "$cap\mods\modA\gamedata\scripts\modA.script") 'incoming mod = R'
    Assert-Equal "[General]`r`nmodid=42`r`n" (Read-Text "$cap\mods\modA\meta.ini") 'incoming mod keeps local meta.ini'
    Assert-Equal "X-local-unpub`r`n" (Read-Text "$cap\mods\modX\gamedata\scripts\modX.script") 'local mod = local folder'
    Assert-PathExists "$cap\mods\modX\meta.ini"
    Assert-PathExists "$cap\mods\modE" 'mod without files in R -> empty folder'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath "$cap\mods\modE" -Force).Count 'modE empty'
    Assert-Equal 5 @(Get-ChildItem -LiteralPath "$cap\mods" -Directory).Count 'one folder per result list entry'
    $a = Read-Text "$cap\args.txt"
    Assert-Match $a '(?m)^NoWait=True$'
    Assert-Equal "GammaRoot=$($sb.H)" (($a -split "`n") | Where-Object { $_ -like 'GammaRoot=*' })
    Assert-Match $a '(?m)^Profile=P$'
    Assert-Match $a ('(?m)^Root=' + [regex]::Escape($sb.Tmp) + '\\xrrfix_sync_[0-9a-f]{8}$') 'temp folder %TEMP%\xrrfix_sync_<8 hex>'
    Assert-NoTempLeft $sb
}

Test-Case 'PUB-028 PUB-030 PUB-042 installer exit 2 / 1 / 5 is passed through, HEAD not moved, temp removed; next run installs' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Stub $sb 'H'
    $h0 = Get-HeadSha "$($sb.H)\repo"; $o0 = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ XRRFIX_T2_RC = '2' }
    Assert-Code 2 $r 'rc 2'
    Assert-Out $r 'Установка отложена'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged (2)'
    Assert-NoTempLeft $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-NoWait') @{ XRRFIX_T2_RC = '1' }
    Assert-Code 1 $r 'rc 1 (and mutex was released)'
    Assert-Out $r 'ОШИБКА: установка изменений с GitHub не удалась (код 1)'
    Assert-NoTempLeft $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt', '-NoWait') @{ XRRFIX_T2_RC = '5' }
    Assert-Code 5 $r 'other code passed as is'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'
    Assert-Equal $o0 (Get-OriginSha $sb) 'origin unchanged'
    Assert-NoTempLeft $sb
    G-Must -C "$($sb.H)\repo" checkout -q -- installer/install.ps1
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[<] modA - изменён на GitHub, будет установлен' 'still remote after failed installs'
    Assert-Equal 'A-F' (Get-Mod $sb.H 'modA')
}

Test-Case 'PUB-027 mod removed on GitHub is disabled in the section, folder kept with marker' {
    $sb = New-Sandbox
    Remove-FromModlist $sb.F 'modA'; Publish-Ok $sb 'F' | Out-Null
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[<] modA - удалён на GitHub, будет выключен'
    Assert-Equal '+zz Фикс Y|+modX|+modB|-modA' (Join-L (Get-Section $sb.H))
    Assert-PathExists "$($sb.H)\mods\modA\gamedata\scripts\modA.script"
    $sha7 = (Get-OriginSha $sb).Substring(0, 7)
    Assert-Equal "xrRazom fixes pack sync-$sha7" (Read-Text "$($sb.H)\mods\modA\xrrfix_pack.txt").TrimStart([char]0xFEFF).Trim()
}

Test-Case 'PUB-031 -SyncOnly with unpushed commit does not move HEAD; publish then pushes it' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Commit-Local $repo { Write-Text "$repo\n2.txt" "n2`n" } 'unpushed2'
    $hh = Get-HeadSha $repo
    Set-Mod $sb.F 'modX' 'X-e2'; Publish-Ok $sb 'F' | Out-Null
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'X-e2' (Get-Mod $sb.H 'modX')
    Assert-Equal $hh (Get-HeadSha $repo) 'HEAD not rewritten'
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=0 mods=' (Get-ResultLine $r) 'second sync: nothing'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'X-e2' (Get-OriginMod $sb 'modX')
    Assert-Equal "n2`n" (Get-OriginText $sb 'n2.txt') 'unpushed commit pushed'
}

Test-Case 'PUB-031 rebase conflict -> rebase aborted, exit 1' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Commit-Local $repo { Write-Text "$repo\README.md" "host version`n" } 'host readme'
    $hh = Get-HeadSha $repo
    Push-Direct "$($sb.F)\repo" { Write-Text "$($sb.F)\repo\README.md" "friend version`n" } 'friend readme'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'git rebase'
    Assert-PathMissing "$repo\.git\rebase-merge" 'rebase aborted'
    Assert-Equal $hh (Get-HeadSha $repo)
}

Test-Case 'PUB-031 ff-only failure: -SyncOnly warns and exits 0, publish exits 1' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Push-Direct "$($sb.F)\repo" { Write-Text "$($sb.F)\repo\extra.txt" "remote`n" } 'extra'
    Write-Text "$repo\extra.txt" "local untracked`n"
    $hh = Get-HeadSha $repo
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r 'SyncOnly'
    Assert-Out $r 'не удалось обновить репозиторий'
    Assert-Equal $hh (Get-HeadSha $repo)
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'publish'
    Assert-Out $r 'git merge --ff-only'
}

Test-Case 'PUB-032 PUB-025 -SyncOnly: catch-up keeps unpublished local edit, no commit, notice' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'zz Фикс Y' 'Y8'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modX' 'X-local-unpub'
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'Y8' (Get-Mod $sb.H 'zz Фикс Y')
    Assert-Equal 'X-local-unpub' (Get-Mod $sb.H 'modX')
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=zz Фикс Y' (Get-ResultLine $r)
    Assert-Out $r 'Неопубликованные локальные изменения: modX (запустите publish.bat)'
    Assert-Equal (Get-OriginSha $sb) (Get-HeadSha "$($sb.H)\repo") 'no own commit'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'X-local-unpub' (Get-OriginMod $sb 'modX')
    Assert-Equal 'Y8' (Get-OriginMod $sb 'zz Фикс Y')
}

# ---------------------------------------------------------------- publishing
Test-Case 'PUB-033 new mod with -NoPrompt is not published (and stays new); -Yes publishes; peer gets it' {
    $sb = New-Sandbox
    Add-NewMod $sb.F 'modN' 'N1'
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'не публикуется (новый, не подтверждён): modN'
    Assert-Equal $null (Get-OriginMod $sb 'modN')
    Assert-False ((Get-OriginList $sb) -contains 'modN')
    Assert-Equal '+zz Фикс Y|+modX|+modB|+modA|+modN' (Join-L (Get-Section $sb.F)) 'stays in MO2'
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Out $r '[>] modN - новый мод' 'still new on the next run'
    $r = Invoke-Publish $sb 'F' @('-NoPrompt', '-Yes')
    Assert-Code 0 $r
    Assert-Equal 'N1' (Get-OriginMod $sb 'modN')
    Assert-Equal 'zz Фикс Y|modX|modB|modA|modN' (Join-L (Get-OriginList $sb))
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'N1' (Get-Mod $sb.H 'modN')
    Assert-Equal '+zz Фикс Y|+modX|+modB|+modA|+modN' (Join-L (Get-Section $sb.H))
}

Test-Case 'PUB-033 interactive confirmation (y/N) from stdin' {
    $sb = New-Sandbox
    Add-NewMod $sb.H 'modN' 'N1'
    $r = Invoke-Publish $sb 'H' @('-Message', 'm1') -Stdin "`r`n"
    Assert-Code 0 $r 'Enter = no'
    Assert-Out $r 'не публикуется (новый, не подтверждён): modN'
    $r = Invoke-Publish $sb 'H' @('-Message', 'm2') -Stdin "y`r`n"
    Assert-Code 0 $r '"y" = yes'
    Assert-Equal 'N1' (Get-OriginMod $sb 'modN') ("publish output:`n" + $r.All)
}

Test-Case 'PUB-034 SYS-013 REPO-013 mods commit holds only local mods (no meta.ini/marker); README goes in its own commit' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modX' 'X-H'
    Write-Text "$($sb.H)\mods\modX\xrrfix_pack.txt" 'xrRazom fixes pack 1'
    Write-Text "$($sb.H)\repo\README.md" "dirty readme`n"
    Write-Text "$($sb.H)\repo\untracked.txt" 'u'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'mods/modX/gamedata/scripts/modX.script' (Join-L (Get-CommitPaths $sb 'main~1')) 'only mods/modX changed in the mods commit'
    Assert-Equal 'README.md' (Join-L (Get-CommitPaths $sb 'main')) 'docs commit holds only README.md'
    Assert-Equal 'A-F' (Get-OriginMod $sb 'modA')
    $all = Get-OriginPaths $sb
    Assert-Equal 0 @($all | Where-Object { $_ -match '(^|/)(meta\.ini|xrrfix_pack\.txt|modlist\.txt)$' -or $_ -eq 'untracked.txt' }).Count 'no MO2 files, no untracked file'
    Assert-Equal "dirty readme`n" (Get-OriginText $sb 'README.md') 'README published by the docs commit'
    Assert-Equal 'test repo' ((Get-OriginText $sb 'README.md' 'main~1').TrimEnd("`n")) 'mods commit left README alone'
}

Test-Case 'PUB-036 summary [+]/[-]/[*], auto message, -Message quotes replaced' {
    $sb = New-Sandbox
    Add-NewMod $sb.H 'modN' 'N1'
    Remove-FromModlist $sb.H 'modX'
    Set-Mod $sb.H 'modA' 'A-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Yes')
    Assert-Code 0 $r
    Assert-Out $r '  [+] modN'
    Assert-Out $r '  [-] modX'
    Assert-Out $r '  [*] modA'
    Assert-Equal 'Update fixes: modN, modX, modA' ((Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, 'log', '-1', '--format=%s', 'main')).Out.Trim())
    Set-Mod $sb.H 'modA' 'A-H2'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Message', '  Fix "x"  ')
    Assert-Code 0 $r
    Assert-Equal "Fix 'x'" ((Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, 'log', '-1', '--format=%s', 'main')).Out.Trim())
}

Test-Case 'PUB-037 PUB-039 push rejected -> exit 1, commit stays local; next run sends it' {
    $sb = New-Sandbox
    $hook = "$($sb.Origin)\hooks\pre-receive"
    Write-Text $hook "#!/bin/sh`necho rejected-by-test >&2`nexit 1`n"
    Set-Mod $sb.H 'modA' 'A-H'
    $o0 = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'git push не удался'
    Assert-Equal $o0 (Get-OriginSha $sb) 'origin unchanged'
    Assert-True ((Get-HeadSha "$($sb.H)\repo") -ne $o0) 'commit kept locally'
    Remove-Item -LiteralPath $hook
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Новых изменений нет, но 1 коммит(ов) ещё не отправлено'
    Assert-Equal (Get-HeadSha "$($sb.H)\repo") (Get-OriginSha $sb)
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Out $r 'Изменений нет'
    Assert-NoOut $r 'git push ...' 'no push when everything is in sync'
}

function Set-PostCommitPush($sb, [string]$Who, [string]$OtherRepo) {
    $o = $OtherRepo.Replace('\', '/')
    Write-Text "$($sb[$Who])\repo\.git\hooks\post-commit" ("#!/bin/sh`nunset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX`ngit -C `"$o`" push -q origin main`n")
}

Test-Case 'PUB-039 friend pushes between fetch and push: pull --rebase, push succeeds' {
    $sb = New-Sandbox
    $f = "$($sb.F)\repo"
    Commit-Local $f { Write-Text "$f\mods\modB\gamedata\scripts\modB.script" "B-race`r`n" } 'race'
    Set-PostCommitPush $sb 'H' $f
    Set-Mod $sb.H 'modA' 'A-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'A-H' (Get-OriginMod $sb 'modA')
    Assert-Equal 'B-race' (Get-OriginMod $sb 'modB')
}

Test-Case 'PUB-039 pull --rebase conflict -> exit 1, commit left locally' {
    $sb = New-Sandbox
    $f = "$($sb.F)\repo"
    Commit-Local $f { Write-PackJson "$f\pack\pack.json" 'xrRazom Sync' @('modA', 'modB', 'modX', 'zz Фикс Y') } 'race order'
    Set-PostCommitPush $sb 'H' $f
    Add-NewMod $sb.H 'modN' 'N1'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Yes')
    Assert-Code 1 $r
    Assert-Out $r 'git pull --rebase не удался'
    Assert-Out $r 'Коммит остался локально'
}

Test-Case 'PUB-041 Cyrillic mod name with spaces and dash: publish, catch-up, conflict' {
    $sb = New-Sandbox
    $n = 'zz Фикс - Тест'
    Add-NewMod $sb.H $n 'T1'
    Publish-Ok $sb 'H' @('-NoPrompt', '-Yes') | Out-Null
    Assert-Equal 'T1' (Get-OriginMod $sb $n)
    Assert-True ((Get-OriginList $sb) -contains $n) 'in pack.json'
    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal "XRRFIX_SYNC_RESULT: installed=1 mods=$n" (Get-ResultLine $r)
    Assert-Equal 'T1' (Get-Mod $sb.F $n)
    Set-Mod $sb.F $n 'T-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H $n 'T-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal "XRRFIX_SYNC_CONFLICT: mods=$n" (Get-ConflictLine $r)
}

Test-Case 'PUB-043 publish.bat passes args (quoted Cyrillic name) and returns the exit code' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'zz Фикс Y' 'Y-host'; Publish-Ok $sb 'H' | Out-Null
    Set-Mod $sb.F 'zz Фикс Y' 'Y-friend'
    $bat = "$($sb.F)\repo\host\publish.bat"
    $env = Get-ChildEnv $sb
    $r = Invoke-Proc 'cmd.exe' -RawArgs "/d /s /c `"`"$bat`" -NoPrompt`"" -Env $env -TimeoutSec 120
    Assert-Code 3 $r 'conflict through publish.bat'
    Assert-Out $r 'XRRFIX_SYNC_CONFLICT'
    Assert-Out $r '. . .' 'pause ran'
    $r = Invoke-Proc 'cmd.exe' -RawArgs "/d /s /c `"`"$bat`" -SyncOnly -NoPrompt -TakeRemote `"zz Фикс Y`"`"" -Env $env -TimeoutSec 120
    Assert-Code 0 $r 'TakeRemote through publish.bat'
    Assert-Equal 'Y-host' (Get-Mod $sb.F 'zz Фикс Y')
}

Test-Case 'PUB-044 -SyncOnly -NoWait -NoPrompt with blocker and mutex held: exit 2 without waiting' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    $p = Start-FakeMO2 120
    $holder = Start-MutexHolder 60
    try { $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt') -TimeoutSec 60 }
    finally { Stop-FakeMO2 $holder; Stop-FakeMO2 $p }
    Assert-Code 2 $r
    Assert-True ($r.Sec -lt 60) "finished in $($r.Sec)s"
}

$script:NoPy = @{ XRRFIX_PYTHON = 'none' }

Test-Case 'PUB-045 docs (changed, new, under every doc path) go in a separate commit after the mods commit' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Set-Mod $sb.H 'modA' 'A-H'
    Write-Text "$repo\specs\fixes\fx-a.md" "# FX-A`n"
    Write-Text "$repo\tests\lua\test_a.lua" "-- t`n"
    Write-Text "$repo\tools\x.py" "print(1)`n"
    Write-Text "$repo\.claude\skills\s\SKILL.md" "skill`n"
    Write-Text "$repo\CLAUDE.md" "rules`n"
    Write-Text "$repo\README.md" "new readme`n"
    Write-Text "$repo\.claude\settings.local.json" "{}"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Message', 'Mods msg') $script:NoPy
    Assert-Code 0 $r
    Assert-Out $r 'Документация:'
    Assert-Out $r '  [d] specs/fixes/fx-a.md'
    Assert-Equal 'mods/modA/gamedata/scripts/modA.script' (Join-L (Get-CommitPaths $sb 'main~1')) 'mods commit first, mods only'
    Assert-Equal 'Mods msg' (Get-CommitSubject $sb 'main~1') '-Message used for the mods commit'
    Assert-Equal '.claude/skills/s/SKILL.md|CLAUDE.md|README.md|specs/fixes/fx-a.md|tests/lua/test_a.lua|tools/x.py' (Join-L (Get-CommitPaths $sb 'main')) 'docs commit'
    Assert-True ((Get-CommitSubject $sb 'main') -like 'Update docs: *(+1)') "auto docs message: $(Get-CommitSubject $sb 'main')"
    Assert-Equal '?? .claude/settings.local.json' (Join-L @(G -C $repo status --porcelain --untracked-files=all)) 'other .claude files untouched'
}

Test-Case 'PUB-045 docs only: one commit with the description, pushed; code paths stay uncommitted' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Write-Text "$repo\README.md" "readme 2`n"
    Write-Text "$repo\host\publish.ini" "gamma_root=`r`nprofile=`r`nsection=xrRazom Sync`r`npush=1`r`n; local`r`n"
    $before = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Message', 'Docs only') $script:NoPy
    Assert-Code 0 $r
    Assert-NoOut $r 'Изменений нет'
    Assert-Equal $before (G --git-dir $sb.Origin rev-parse main~1 | Select-Object -First 1) 'exactly one new commit'
    Assert-Equal 'README.md' (Join-L (Get-CommitPaths $sb 'main'))
    Assert-Equal 'Docs only' (Get-CommitSubject $sb 'main')
    Assert-Equal ' M host/publish.ini' (Join-L @(G -C $repo status --porcelain)) 'host/publish.ini not committed'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') $script:NoPy
    Assert-Out $r 'Изменений нет' 'second run: nothing left to publish'
}

Test-Case 'PUB-045 deleted doc file is committed as a deletion; -SyncOnly never commits docs' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Write-Text "$repo\specs\a.md" "a`n"
    Publish-Ok $sb 'H' @('-NoPrompt') | Out-Null
    Assert-Equal 'a' ((Get-OriginText $sb 'specs/a.md').TrimEnd("`n"))
    Remove-Item -LiteralPath "$repo\specs\a.md"
    Write-Text "$repo\README.md" "sync only`n"
    $before = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt') $script:NoPy
    Assert-Code 0 $r
    Assert-Equal $before (Get-OriginSha $sb) '-SyncOnly pushed nothing'
    Assert-Equal $before (Get-HeadSha $repo) '-SyncOnly committed nothing'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') $script:NoPy
    Assert-Code 0 $r
    Assert-Equal 'README.md|specs/a.md' (Join-L (Get-CommitPaths $sb 'main'))
    Assert-Equal $null (Get-OriginText $sb 'specs/a.md') 'specs/a.md deleted on GitHub'
}

Test-Case 'PUB-046 spec_check errors keep docs out, mods still published; clean check commits docs' {
    $py = Get-Python
    if (-not $py) { Write-Host '  (no python: skipped)' -ForegroundColor DarkGray; return }
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Write-Text "$repo\tools\spec_check.py" "import sys`nprint('ERROR   CHK-001  FX-A-001 [auto] has no test case')`nprint('spec_check: 1 error(s)')`nsys.exit(1)`n"
    Write-Text "$repo\specs\x.md" "x`n"
    Set-Mod $sb.H 'modA' 'A-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ XRRFIX_PYTHON = $py }
    Assert-Code 0 $r
    Assert-Out $r 'ERROR   CHK-001  FX-A-001'
    Assert-Out $r 'Документация не опубликована'
    Assert-Equal 'mods/modA/gamedata/scripts/modA.script' (Join-L (Get-CommitPaths $sb 'main')) 'only the mods commit'
    Assert-Equal $null (Get-OriginText $sb 'specs/x.md') 'docs not published'
    Assert-Equal '?? specs/|?? tools/' (Join-L @(G -C $repo status --porcelain)) 'docs left in the working tree'

    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ XRRFIX_PYTHON = $py }
    Assert-Out $r 'Изменений нет' 'docs rejected again, no mods: nothing to publish'

    Write-Text "$repo\tools\spec_check.py" "import sys`nsys.exit(0)`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ XRRFIX_PYTHON = $py }
    Assert-Code 0 $r
    Assert-Out $r 'spec_check: ошибок нет'
    Assert-Equal 'specs/x.md|tools/spec_check.py' (Join-L (Get-CommitPaths $sb 'main')) 'docs committed after a clean check'
}

Test-Case 'PUB-046 no python or check code 2: docs committed with a warning' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Write-Text "$repo\specs\y.md" "y`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') $script:NoPy
    Assert-Code 0 $r
    Assert-Out $r 'spec_check не выполнен'
    Assert-Equal 'specs/y.md' (Join-L (Get-CommitPaths $sb 'main'))
    $py = Get-Python
    if (-not $py) { return }
    Write-Text "$repo\tools\spec_check.py" "import sys`nsys.exit(2)`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ XRRFIX_PYTHON = $py }
    Assert-Code 0 $r
    Assert-Out $r 'spec_check не выполнен (код 2)'
    Assert-Equal 'tools/spec_check.py' (Join-L (Get-CommitPaths $sb 'main'))
}
