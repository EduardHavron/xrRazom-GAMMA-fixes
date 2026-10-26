# publish.ps1 cases: PUB-001 .. PUB-044 (spec: specs/system/publish.md). Dot-sourced by run.ps1.

function Set-PublishIni($sb, [string]$Who, [string]$Text) { Write-Text "$($sb[$Who])\repo\host\publish.ini" $Text }
function Set-Stub($sb, [string]$Who) {
    # installer stub: captures its package + args, prints two lines, exits with $env:XRRFIX_T2_RC
    $stub = @'
param([switch]$NoWait, [string]$GammaRoot = '', [Alias('Profile')][string]$ProfileName = '')
$cap = $env:XRRFIX_T2_CAPTURE
if ($cap) {
    New-Item -ItemType Directory -Path $cap -Force | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $cap -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $cap 'args.txt'), ("NoWait=$NoWait`nGammaRoot=$GammaRoot`nProfile=$ProfileName`nRoot=$PSScriptRoot`n"), (New-Object Text.UTF8Encoding($false)))
}
Write-Output 'STUB-LINE-1'
Write-Output 'STUB-LINE-2'
exit [int]$env:XRRFIX_T2_RC
'@
    Write-Text "$($sb[$Who])\repo\installer\install.ps1" ($stub.Replace("`r`n", "`n").Replace("`n", "`r`n"))
}
function Commit-Local([string]$Repo, [scriptblock]$Change, [string]$Msg = 'local') {
    & $Change
    G-Must -C $Repo add -A
    G-Must -C $Repo commit -q -m $Msg
}

# ---------------------------------------------------------------- configuration / preconditions
Test-Case 'PUB-001 relative gamma_root is resolved from host\ (trailing \ trimmed) and used' {
    $sb = New-Sandbox
    Set-PublishIni $sb 'H' "gamma_root=..\..\..\F\`r`nprofile=`r`nsection=xrRazom Sync`r`npush=1`r`n"
    Set-Mod $sb.F 'modB' 'B-from-F-root'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'B-from-F-root' (Get-OriginMod $sb 'modB') 'H repo published the MO2 of the F root'
}

Test-Case 'PUB-001 gamma_root without ModOrganizer.ini -> exit 1 before any git call' {
    $sb = New-Sandbox
    Set-PublishIni $sb 'H' "gamma_root=..\..\nowhere`r`n"
    $fh = "$($sb.H)\repo\.git\FETCH_HEAD"
    $before = Test-Path -LiteralPath $fh
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'Не найден ModOrganizer.ini'
    Assert-Out $r 'Укажите gamma_root'
    if (-not $before) { Assert-PathMissing $fh 'git fetch was not called' }
}

Test-Case 'PUB-002 no .git / no commits / git missing in PATH -> exit 1' {
    $sb = New-Sandbox
    $ng = "$($sb.Root)\nogit"
    New-Item -ItemType Directory "$ng\host" -Force | Out-Null
    Copy-Item "$($sb.H)\repo\host\publish.ps1" "$ng\host\"
    Write-Text "$ng\host\publish.ini" "gamma_root=$($sb.H)`r`n"
    $r = Invoke-PublishPs1 "$ng\host\publish.ps1" $sb @('-NoPrompt')
    Assert-Code 1 $r 'no .git'
    Assert-Out $r 'не является git-репозиторием'

    $em = "$($sb.Root)\empty"
    New-Item -ItemType Directory "$em\host" -Force | Out-Null
    Copy-Item "$($sb.H)\repo\host\publish.ps1" "$em\host\"
    Write-Text "$em\host\publish.ini" "gamma_root=$($sb.H)`r`n"
    G-Must init -q $em
    $r = Invoke-PublishPs1 "$em\host\publish.ps1" $sb @('-NoPrompt')
    Assert-Code 1 $r 'no commits'
    Assert-Out $r 'нет коммитов'

    $path = "$env:WINDIR\System32;$env:WINDIR\System32\WindowsPowerShell\v1.0"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt') @{ PATH = $path }
    Assert-Code 1 $r 'git not in PATH'
    Assert-Out $r 'git не найден в PATH'
}

Test-Case 'PUB-003 PUB-038 push=No / push=НЕТ: local commit only; other value pushes' {
    $sb = New-Sandbox
    $o0 = Get-OriginSha $sb
    foreach ($v in 'No', 'НЕТ') {
        Set-PublishIni $sb 'H' "push=$v`r`n"
        Set-Mod $sb.H 'modA' "A-$v"
        $h0 = Get-HeadSha "$($sb.H)\repo"
        $r = Invoke-Publish $sb 'H' @('-NoPrompt')
        Assert-Code 0 $r "push=$v"
        Assert-Out $r 'push=0 в publish.ini'
        Assert-Out $r 'коммит создан локально, отправка пропущена'
        Assert-NoOut $r 'git push ...'
        Assert-True ((Get-HeadSha "$($sb.H)\repo") -ne $h0) "commit created (push=$v)"
        Assert-Equal $o0 (Get-OriginSha $sb) "origin unchanged (push=$v)"
    }
    Set-PublishIni $sb 'H' "push=off`r`n"
    Set-Mod $sb.H 'modA' 'A-off'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r 'push=off'
    Assert-Equal (Get-HeadSha "$($sb.H)\repo") (Get-OriginSha $sb) 'push=off pushes'
    Assert-Equal 'A-off' (Get-OriginMod $sb 'modA')
}

# ---------------------------------------------------------------- mutex
Test-Case 'PUB-004 PUB-044 mutex held + -SyncOnly -NoWait -> exit 2 fast, nothing changed' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    $snap = Get-DirSnapshot $sb.H; $h0 = Get-HeadSha "$($sb.H)\repo"
    $holder = Start-MutexHolder 40
    try {
        $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt') -TimeoutSec 90
    } finally { Stop-FakeMO2 $holder }
    Assert-Code 2 $r
    Assert-Out $r 'publish уже выполняется - отложено.'
    Assert-True ($r.Sec -lt 60) "finished in $($r.Sec)s (< 60)"
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'
    Assert-True ($snap -ceq (Get-DirSnapshot $sb.H)) 'H root (MO2 + repo) unchanged'
}

Test-Case 'PUB-004 mutex taken after ini/.git/git checks and before the profile is read' {
    $sb = New-Sandbox
    $holder = Start-MutexHolder 40
    try {
        Set-PublishIni $sb 'H' "gamma_root=..\..\nowhere`r`n"
        $r = Invoke-Publish $sb 'H' @('-NoWait', '-NoPrompt')
        Assert-Code 1 $r 'ModOrganizer.ini check happens before the mutex'
        Set-PublishIni $sb 'H' "profile=NoSuchProfile`r`n"
        $r = Invoke-Publish $sb 'H' @('-NoWait', '-NoPrompt')
        Assert-Code 2 $r 'profile is read after the mutex'
    } finally { Stop-FakeMO2 $holder }
}

Test-Case 'PUB-004 without -NoWait waits for the mutex, then continues' {
    $sb = New-Sandbox
    $holder = Start-MutexHolder 4
    try { $r = Invoke-Publish $sb 'H' @('-NoPrompt') -TimeoutSec 90 } finally { Stop-FakeMO2 $holder }
    Assert-Code 0 $r
    Assert-Out $r 'publish уже выполняется в другом окне - жду его завершения...'
    Assert-Out $r 'Изменений нет'
}

Test-Case 'PUB-004 abandoned mutex counts as acquired' {
    $sb = New-Sandbox
    $keep = New-Object Threading.Mutex($false, 'Local\xrrfix_publish')   # keeps the named object alive
    try {
        $holder = Start-MutexHolder 0 -Abandon
        $holder.WaitForExit(20000) | Out-Null
        $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    } finally { $keep.Dispose() }
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=0 mods=' (Get-ResultLine $r)
}

# ---------------------------------------------------------------- profile / section
Test-Case 'PUB-005 profile from selected_profile=@ByteArray(...), from publish.ini, errors' {
    $sb = New-Sandbox
    Rename-Item "$($sb.H)\profiles\P" 'G.A.M.M.A'
    Write-Text "$($sb.H)\ModOrganizer.ini" "[General]`r`nselected_profile=@ByteArray(G.A.M.M.A)`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r '@ByteArray profile'
    Assert-Out $r 'Профиль: G.A.M.M.A'

    Copy-Item "$($sb.H)\profiles\G.A.M.M.A" "$($sb.H)\profiles\Q" -Recurse
    Set-PublishIni $sb 'H' "profile=Q`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r 'profile from ini'
    Assert-Out $r 'Профиль: Q'

    Set-PublishIni $sb 'H' "profile=`r`n"
    Write-Text "$($sb.H)\ModOrganizer.ini" "[General]`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'no selected_profile'
    Assert-Out $r 'нет selected_profile'

    Set-PublishIni $sb 'H' "profile=Missing`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'no modlist'
    Assert-Out $r 'profiles\Missing\modlist.txt'
}

Test-Case 'PUB-006 PUB-047 separator: missing -> first install from GitHub; "-" prefix accepted; custom section name' {
    $sb = New-Sandbox
    $orig = Get-Modlist $sb.H
    $head0 = Get-HeadSha "$($sb.Origin)"
    Set-Modlist $sb.H @($orig | Where-Object { $_ -ne "+$script:SEP" })
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r 'no separator'
    Assert-Out $r "Секция 'xrRazom Sync' пуста или отсутствует - первая установка"
    Assert-Equal (Join-L @($script:SEED_ORDER | ForEach-Object { "+$_" })) (Join-L (Get-Section $sb.H)) 'pack installed into a new section'
    Assert-Equal $head0 (Get-HeadSha "$($sb.Origin)") 'nothing published'

    Set-Modlist $sb.H @($orig | ForEach-Object { if ($_ -eq "+$script:SEP") { "-$script:SEP" } else { $_ } })
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r '-separator'
    Assert-Out $r 'Изменений нет'

    Set-Modlist $sb.H @($orig | ForEach-Object { if ($_ -eq "+$script:SEP") { '+My Fixes_separator' } else { $_ } })
    Set-PublishIni $sb 'H' "section=My Fixes`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r 'custom section'
    Assert-Out $r 'Секция: My Fixes'
    Assert-Equal 'My Fixes' ([string](Get-OriginPack $sb).section) 'PUB-035: pack.json section = configured section'
    Assert-Equal (Join-L $script:SEED_ORDER) (Join-L (Get-OriginList $sb)) 'list unchanged'
}

Test-Case 'PUB-007 PUB-034 L = "+" lines between previous separator and ours; removed mods deleted from repo' {
    $sb = New-Sandbox
    Set-Modlist $sb.H @('# header', '+modX', '+Other_separator', '+modB', '-zz Фикс Y', '*Foo', '+modA', "+$script:SEP", '+Other mod')
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Match $r.Out '(?m)^  \+ modB\r?\n  \+ modA\r?$' 'L printed = [modB, modA]'
    Assert-NoOut $r '  + modX'
    Assert-Out $r '[>] modX - убран локально' 'PUB-021'
    Assert-Equal 'modB|modA' (Join-L (Get-OriginList $sb)) 'pack.json'
    $paths = Get-OriginPaths $sb
    Assert-Equal 0 @($paths | Where-Object { $_ -like 'mods/modX/*' -or $_ -like 'mods/zz Фикс Y/*' }).Count 'removed mods deleted in commit'
    Assert-Equal 'Update fixes: modX, zz Фикс Y' ((Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, 'log', '-1', '--format=%s', 'main')).Out.Trim()) 'PUB-036 auto message'
}

Test-Case 'PUB-047 empty section on a fresh machine: -SyncOnly installs the whole pack, nothing published' {
    $sb = New-Sandbox
    $head0 = Get-HeadSha "$($sb.Origin)"
    foreach ($n in $script:SEED_ORDER) { Remove-Item -LiteralPath "$($sb.H)\mods\$n" -Recurse -Force }
    Set-Modlist $sb.H @('# h', "+$script:SEP", '+Other mod', '+Below')
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'первая установка'
    Assert-Equal "# h|$(Join-L @($script:SEED_ORDER | ForEach-Object { "+$_" }))|+$script:SEP|+Other mod|+Below" (Join-L (Get-Modlist $sb.H)) 'section filled, foreign mods untouched'
    foreach ($n in $script:SEED_ORDER) { Assert-PathExists "$($sb.H)\mods\$n" }
    Assert-Equal $head0 (Get-HeadSha "$($sb.Origin)") 'nothing published'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r 'second run'
    Assert-Out $r 'всё совпадает'
}

Test-Case 'PUB-008 empty L -> exit 1; missing mod folders listed -> exit 1' {
    $sb = New-Sandbox
    Set-Modlist $sb.H @('# h', '-modA', '-modB', "+$script:SEP")
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'empty'
    Assert-Out $r 'нет включённых модов'
    Set-Modlist $sb.H @('# h', '+modQ', '+modA', '+modR', "+$script:SEP")
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'missing'
    Assert-Out $r '  - modQ'
    Assert-Out $r '  - modR'
}

Test-Case 'PUB-009 unfinished merge / rebase -> exit 1' {
    $sb = New-Sandbox
    $gd = "$($sb.H)\repo\.git"
    $h0 = Get-HeadSha "$($sb.H)\repo"
    Write-Text "$gd\MERGE_HEAD" "$h0`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'MERGE_HEAD'
    Assert-Out $r 'не завершён rebase/merge'
    Remove-Item -LiteralPath "$gd\MERGE_HEAD"
    New-Item -ItemType Directory "$gd\rebase-merge" | Out-Null
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r 'rebase-merge'
    Assert-Out $r 'не завершён rebase/merge'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'
}

Test-Case 'PUB-010 leftovers in repo mods/ and pack/ are reset, other files untouched' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Write-Text "$repo\mods\modA\gamedata\scripts\modA.script" "junk`r`n"
    Write-Text "$repo\mods\modZ\y.txt" "y"
    Write-Text "$repo\pack\pack.json" "{}`n"; G-Must -C $repo add pack/pack.json
    Write-Text "$repo\host\publish.ini" "gamma_root=`r`nprofile=`r`nsection=xrRazom Sync`r`npush=1`r`n; local`r`n"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Сбрасываю незакоммиченные изменения в mods/ и pack/'
    Assert-Out $r 'Изменений нет'
    Assert-Equal "v1 modA`r`n" (Read-Text "$repo\mods\modA\gamedata\scripts\modA.script") 'mods/modA = HEAD'
    Assert-PathMissing "$repo\mods\modZ"
    $st = @(G -C $repo status --porcelain)
    Assert-Equal ' M host/publish.ini' (Join-L $st) 'only host/publish.ini still modified'
}

Test-Case 'PUB-011 git fetch failure -> exit 1' {
    $sb = New-Sandbox
    G-Must -C "$($sb.H)\repo" remote set-url origin "$($sb.Root)\nonexistent.git"
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'git fetch не удался'
}

Test-Case 'PUB-011 no upstream -> R = origin/main; no origin/main -> R = HEAD' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    G-Must -C $repo checkout -q -b work
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    $o = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r 'no upstream'
    Assert-Out $r "Сравнение с GitHub (origin/main $($o.Substring(0,7))):"
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=modA' (Get-ResultLine $r)

    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    G-Must -C $repo checkout -q -b work
    G-Must -C $repo config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/other'
    G-Must -C $repo update-ref -d refs/remotes/origin/main
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    $h = Get-HeadSha $repo
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r 'no origin/main'
    Assert-Out $r "Сравнение с GitHub (origin/main $($h.Substring(0,7))):"
    Assert-Out $r '  всё совпадает'
    Assert-Equal 'v1 modA' (Get-Mod $sb.H 'modA') 'nothing installed'
}

Test-Case 'PUB-012 PUB-031 unpushed local commit + remote change: merge-base, rebase, publish' {
    $sb = New-Sandbox
    $repo = "$($sb.H)\repo"
    Commit-Local $repo { Write-Text "$repo\notes.txt" "note`n" } 'local unpushed'
    Set-Mod $sb.F 'modB' 'B-e1'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modA' 'A-e1'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Message', 'e1h')
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=modB' (Get-ResultLine $r) 'B = merge-base: modB is remote, not local'
    Assert-Equal 'A-e1' (Get-OriginMod $sb 'modA')
    Assert-Equal 'B-e1' (Get-OriginMod $sb 'modB')
    Assert-Equal 'B-e1' (Get-Mod $sb.H 'modB')
    Assert-Equal "note`n" (Get-OriginText $sb 'notes.txt') 'unpushed commit rebased and pushed'
}

Test-Case 'PUB-012 no common history with origin -> exit 1' {
    $sb = New-Sandbox
    $u = "$($sb.Root)\unrelated"; $ub = "$($sb.Root)\unrelated.git"
    G-Must init -q --bare $ub
    G-Must init -q $u
    Write-Text "$u\x.txt" 'x'
    G-Must -C $u add -A
    G-Must -C $u -c user.name=u -c user.email=u@example.invalid commit -q -m u
    G-Must -C $u push -q $ub HEAD:refs/heads/main
    G-Must -C "$($sb.H)\repo" remote set-url origin $ub
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'Нет общей истории'
}

Test-Case 'PUB-013 dirty tracked file outside mods/pack that R changes -> exit 1; untouched by R -> ok' {
    $sb = New-Sandbox
    Push-Direct "$($sb.F)\repo" { Add-Content -LiteralPath "$($sb.F)\repo\host\publish.ini" '; remote edit' -Encoding UTF8 } 'ini'
    Set-Mod $sb.F 'modB' 'B-F'; Publish-Ok $sb 'F' | Out-Null
    Add-Content -LiteralPath "$($sb.H)\repo\host\publish.ini" '; local dirty' -Encoding UTF8
    $snap = Get-DirSnapshot "$($sb.H)\mods"; $ml = Get-FileSha "$($sb.H)\profiles\P\modlist.txt"; $h0 = Get-HeadSha "$($sb.H)\repo"
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 1 $r
    Assert-Out $r 'мешают обновлению'
    Assert-Out $r '  - host/publish.ini'
    Assert-Out $r 'git stash'
    Assert-True ($snap -ceq (Get-DirSnapshot "$($sb.H)\mods")) 'MO2 mods unchanged'
    Assert-Equal $ml (Get-FileSha "$($sb.H)\profiles\P\modlist.txt") 'modlist unchanged'
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo") 'HEAD unchanged'

    $sb = New-Sandbox
    Set-Mod $sb.F 'modB' 'B-F'; Publish-Ok $sb 'F' | Out-Null
    Add-Content -LiteralPath "$($sb.H)\repo\host\publish.ini" '; local dirty' -Encoding UTF8
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r 'R does not touch publish.ini'
    Assert-Equal 'B-F' (Get-Mod $sb.H 'modB')
}

# ---------------------------------------------------------------- comparison
Test-Case 'PUB-014 PUB-031 byte-identical CRLF content equals R (L==R no-op, repo fast-forwarded)' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'modA' 'A4'; Publish-Ok $sb 'H' | Out-Null
    Set-Mod $sb.F 'modA' 'A4'
    Write-Text "$($sb.F)\mods\modA\xrrfix_pack.txt" 'xrRazom fixes pack 1'
    $o = Get-OriginSha $sb
    $ml = Get-FileSha "$($sb.F)\profiles\P\modlist.txt"
    $r = Invoke-Publish $sb 'F' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Изменений нет'
    Assert-Equal $o (Get-OriginSha $sb) 'origin unchanged'
    Assert-Equal $o (Get-HeadSha "$($sb.F)\repo") 'F repo fast-forwarded to R'
    Assert-Equal $ml (Get-FileSha "$($sb.F)\profiles\P\modlist.txt") 'modlist not rewritten'
}

Test-Case 'PUB-014 one byte / line endings differ -> changed; top-level meta.ini+marker ignored; nested meta.ini and hidden files count' {
    $sb = New-Sandbox
    Write-Text "$($sb.H)\mods\modX\gamedata\scripts\modX.script" "v1 modX`n"     # same text, LF instead of CRLF
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[>] modX - изменён локально'
    Assert-Equal "v1 modX`n" (Get-OriginText $sb 'mods/modX/gamedata/scripts/modX.script') 'bytes published as-is'

    Write-Text "$($sb.H)\mods\modA\meta.ini" "[General]`r`nmodid=999`r`n"
    Write-Text "$($sb.H)\mods\modA\xrrfix_pack.txt" 'xrRazom fixes pack 5'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Изменений нет' 'meta.ini / marker do not count'

    Write-Text "$($sb.H)\mods\modA\gamedata\meta.ini" 'nested'
    Write-Text "$($sb.H)\mods\modA\.hidden" 'h'
    (Get-Item -LiteralPath "$($sb.H)\mods\modA\.hidden" -Force).Attributes = 'Hidden'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[>] modA - изменён локально'
    $p = Get-OriginPaths $sb
    Assert-True ($p -contains 'mods/modA/gamedata/meta.ini') 'nested meta.ini published'
    Assert-True ($p -contains 'mods/modA/.hidden') 'hidden file published'
    Assert-False ($p -contains 'mods/modA/meta.ini') 'top-level meta.ini not published'
    Assert-False ($p -contains 'mods/modA/xrrfix_pack.txt') 'marker not published'
}

Test-Case 'PUB-015 PUB-018 R folder not in pack.json is <absent>: local new mod of same name is "new", not a conflict' {
    $sb = New-Sandbox
    Push-Direct "$($sb.F)\repo" { Write-Text "$($sb.F)\repo\mods\modZ\z.script" "remote z`r`n" } 'stray folder'
    Add-NewMod $sb.H 'modZ' 'local z'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Yes')
    Assert-Code 0 $r
    Assert-Out $r '[>] modZ - новый мод'
    Assert-Equal 'local z' (Get-OriginMod $sb 'modZ')
    Assert-True ((Get-OriginList $sb) -contains 'modZ') 'in pack.json'
}

Test-Case 'PUB-015 PUB-021 PUB-027 no pack.json in R -> empty list: every mod removed and switched off' {
    $sb = New-Sandbox
    Push-Direct "$($sb.F)\repo" { G-Must -C "$($sb.F)\repo" rm -q pack/pack.json } 'drop pack'
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    foreach ($n in $script:SEED_ORDER) { Assert-Out $r "[<] $n - удалён на GitHub, будет выключен" }
    Assert-Equal 'installed=4' ((Get-ResultLine $r) -replace '^XRRFIX_SYNC_RESULT: (installed=\d+).*$', '$1')
    Assert-Equal (Join-L @($script:SEED_ORDER | ForEach-Object { "-$_" })) (Join-L (Get-Section $sb.H)) 'all disabled in the section'
    foreach ($n in $script:SEED_ORDER) { Assert-PathExists "$($sb.H)\mods\$n\gamedata" "folder $n kept" }
}

Test-Case 'PUB-016 PUB-021 PUB-029 statuses remote / local / equal / sync in one run' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Set-Mod $sb.F 'modB' 'B2'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modX' 'X-H'; Set-Mod $sb.H 'modB' 'B2'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r '[<] modA - изменён на GitHub, будет установлен'
    Assert-Out $r '[>] modX - изменён локально'
    Assert-NoOut $r '] modB' 'equal: no report line'
    Assert-NoOut $r '] zz Фикс Y' 'sync: no report line'
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=1 mods=modA' (Get-ResultLine $r)
    Assert-Equal 'X-H' (Get-OriginMod $sb 'modX')
    Assert-Equal 'A-F' (Get-OriginMod $sb 'modA')
    Assert-Equal 'B2' (Get-OriginMod $sb 'modB')
    Assert-Equal 'A-F' (Get-Mod $sb.H 'modA')
}

Test-Case 'PUB-016 removed on GitHub + modified locally -> conflict' {
    $sb = New-Sandbox
    Remove-FromModlist $sb.F 'modB'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modB' 'B-H'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal 'XRRFIX_SYNC_CONFLICT: mods=modB' (Get-ConflictLine $r)
    Assert-Out $r '[!] modB - изменён и локально, и на GitHub'
}

Test-Case 'PUB-016 only in B (removed on both sides) -> equal, not in the result' {
    $sb = New-Sandbox
    Remove-FromModlist $sb.F 'modB'; Publish-Ok $sb 'F' | Out-Null
    Remove-FromModlist $sb.H 'modB'
    $o = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    Assert-Out $r 'Изменений нет'
    Assert-NoOut $r 'modB -'
    Assert-Equal $o (Get-OriginSha $sb)
    Assert-Equal 0 @((Get-Modlist $sb.H) | Where-Object { $_ -match 'modB' }).Count 'modB not re-added'
}
