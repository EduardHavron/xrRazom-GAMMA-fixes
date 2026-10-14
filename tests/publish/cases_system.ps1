# End-to-end invariants from specs/system/overview.md (SYS-*) that involve publish/installer. Dot-sourced by run.ps1.
# SYS-004 -> INS-021 case, SYS-009 -> PUB-024 case, SYS-013 -> PUB-034 case (names carry the IDs).

Test-Case 'SYS-002 byte-exact: MO2 -> repo -> (catch-up | build_pack zip + installer) -> MO2 for CRLF/LF/BOM/binary files' {
    $sb = New-Sandbox
    $n = 'zz Bytes Мод'
    $files = [ordered]@{
        'gamedata\scripts\crlf.script' = $script:UTF8NoBom.GetBytes("a`r`nb`r`n")
        'gamedata\scripts\lf.script'   = $script:UTF8NoBom.GetBytes("a`nb`n")
        'gamedata\configs\bom.ltx'     = [byte[]](@(0xEF, 0xBB, 0xBF) + @($script:UTF8NoBom.GetBytes("[x]`r`nk = Привет`r`n")))
        'gamedata\textures\t.dds'      = [byte[]](0..255 + 0..255)
        'gamedata\mixed.xml'           = $script:UTF8NoBom.GetBytes("<a>`r`n<b/>`n</a>")
    }
    foreach ($k in $files.Keys) { Write-Bytes "$($sb.H)\mods\$n\$k" $files[$k] }
    Write-Text "$($sb.H)\mods\$n\meta.ini" "[General]`r`n"
    $l = Get-Modlist $sb.H; $out = @(); foreach ($x in $l) { $out += $x; if ($x -eq '+modA') { $out += "+$n" } }; Set-Modlist $sb.H $out
    Publish-Ok $sb 'H' @('-NoPrompt', '-Yes') | Out-Null
    $src = Get-DirSnapshot "$($sb.H)\mods\$n"
    $src = (($src -split "`n") | Where-Object { $_ -notlike 'meta.ini|*' -and $_ -notlike 'xrrfix_pack.txt|*' }) -join "`n"

    $r = Invoke-Publish $sb 'F' @('-SyncOnly', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal $src (Get-DirSnapshot "$($sb.F)\repo\mods\$n") 'repo checkout (F) = publisher MO2'
    $f = (((Get-DirSnapshot "$($sb.F)\mods\$n") -split "`n") | Where-Object { $_ -notlike 'xrrfix_pack.txt|*' }) -join "`n"
    Assert-Equal $src $f 'peer MO2 after catch-up = publisher MO2'

    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { Write-Host '  (python not found: release-zip leg skipped)' -ForegroundColor DarkGray; return }
    $dist = "$($sb.Root)\dist"
    $b = Invoke-Proc $py.Source @((Join-Path $script:RepoRoot '.github\scripts\build_pack.py'), 'build', '--repo', "$($sb.F)\repo", '--version', '2026.10.14-1', '--out', $dist)
    Assert-Code 0 $b 'build_pack.py build'
    $recv = New-Gamma "$($sb.Root)\R" @('# h', "+$script:SEP")
    $pkg = "$($sb.Root)\R\dl\pkg"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory("$dist\xrRazom_fixes.zip", $pkg)
    $r = Invoke-Installer $pkg @('-NoWait', '-GammaRoot', $recv) -Lad "$($sb.Lad)"
    Assert-Code 0 $r 'install from release zip'
    $g = (((Get-DirSnapshot "$recv\mods\$n") -split "`n") | Where-Object { $_ -notlike 'xrrfix_pack.txt|*' }) -join "`n"
    Assert-Equal $src $g 'receiver MO2 (release zip) = publisher MO2'
}

Test-Case 'SYS-003 only enabled mods of the section are published (first publish with -Yes)' {
    $sb = New-Sandbox
    foreach ($m in 'newA', 'newB', 'newC') { Set-Mod $sb.H $m "$m-1" }
    Set-Modlist $sb.H @('# h', '+newC', '+Prev_separator', '+newA', '-newB', "+$script:SEP", '+Other mod')
    $r = Invoke-Publish $sb 'H' @('-NoPrompt', '-Yes')
    Assert-Code 0 $r
    Assert-Equal 'newA' (Join-L (Get-OriginList $sb))
    $p = Get-OriginPaths $sb
    Assert-Equal 0 @($p | Where-Object { $_ -like 'mods/newB/*' -or $_ -like 'mods/newC/*' -or $_ -like 'mods/Other mod/*' }).Count 'no disabled / out-of-section mods'
    Assert-True ($p -contains 'mods/newA/gamedata/scripts/newA.script')
}

Test-Case 'SYS-005 SYS-007 PUB-034 friend change is not reverted; catch-up happens before the own commit' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-friend'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modX' 'X-host'
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 0 $r
    $i1 = $r.Out.IndexOf('XRRFIX_SYNC_RESULT: installed=1 mods=modA'); $i2 = $r.Out.IndexOf('Коммит:')
    Assert-True ($i1 -ge 0 -and $i2 -gt $i1) 'install result printed before the commit'
    Assert-Equal 'A-friend' (Get-OriginMod $sb 'modA') 'not reverted'
    Assert-Equal 'X-host' (Get-OriginMod $sb 'modX')
    Assert-Equal 'A-friend' (Get-Mod $sb.H 'modA') 'host MO2 got the friend version'
    $names = @((Invoke-Proc 'git.exe' @('--git-dir', $sb.Origin, 'show', '--name-only', '--format=', 'main')).Out -split "`n" | Where-Object { $_ })
    Assert-Equal 'mods/modX/gamedata/scripts/modX.script' (Join-L $names) 'host commit has only modX'
}

Test-Case 'SYS-006 conflict: exit 3, no commit, MO2 untouched until a side is chosen' {
    $sb = New-Sandbox
    Set-Mod $sb.F 'modA' 'A-F'; Publish-Ok $sb 'F' | Out-Null
    Set-Mod $sb.H 'modA' 'A-H'
    $ml = Get-FileSha "$($sb.H)\profiles\P\modlist.txt"; $h0 = Get-HeadSha "$($sb.H)\repo"; $o0 = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-NoPrompt')
    Assert-Code 3 $r
    Assert-Equal 'XRRFIX_SYNC_CONFLICT: mods=modA' (Get-ConflictLine $r)
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo"); Assert-Equal $o0 (Get-OriginSha $sb)
    Assert-Equal $ml (Get-FileSha "$($sb.H)\profiles\P\modlist.txt")
    Assert-Equal 'A-H' (Get-Mod $sb.H 'modA')
}

Test-Case 'SYS-011 (publish side) -SyncOnly -NoWait -NoPrompt with a local edit: no commit, no push, installed=0' {
    $sb = New-Sandbox
    Set-Mod $sb.H 'modX' 'X-local'
    $h0 = Get-HeadSha "$($sb.H)\repo"; $o0 = Get-OriginSha $sb
    $r = Invoke-Publish $sb 'H' @('-SyncOnly', '-NoWait', '-NoPrompt')
    Assert-Code 0 $r
    Assert-Equal 'XRRFIX_SYNC_RESULT: installed=0 mods=' (Get-ResultLine $r)
    Assert-Equal $h0 (Get-HeadSha "$($sb.H)\repo"); Assert-Equal $o0 (Get-OriginSha $sb)
    Assert-Equal 'X-local' (Get-Mod $sb.H 'modX')
}
