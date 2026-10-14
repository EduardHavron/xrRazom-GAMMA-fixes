# Peer mode cases (AGT-017..031, 045, 046) against fixtures\fake_github.py. Dot-sourced by run.ps1.
# All peer runs use XRRFIX_REPO=none so no clone search touches anything.

function New-PeerHome([string]$Sb, [switch]$NoRoot) {
    $g = New-Gamma "$Sb\Gamma"
    if ($NoRoot) { return (New-AgentHome "$Sb\xrrfix") }
    return (New-AgentHome "$Sb\xrrfix" $g)
}
function Peer([hashtable]$Extra = @{}) { $e = @{ XRRFIX_REPO = 'none' }; foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }; return $e }

TC 'AGT-017 200 stores ETag and body; next run sends If-None-Match; -Force does not' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-17'
    Write-State "$h\installed_version.txt" $rel.Ver
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    $q = @(Get-Requests '/latest.json')
    Assert-Equal 1 $q.Count 'one API request'
    Assert-True ($null -eq $q[0].if_none_match) 'first request without If-None-Match'
    Assert-Equal $script:UA $q[0].user_agent 'User-Agent'
    Assert-Equal 'application/vnd.github+json' $q[0].accept 'Accept'
    Assert-Equal '"abc"' (First "$h\api_etag.txt") 'api_etag.txt'
    Assert-FilesEqual (Join-Path $script:Www 'latest.json') "$h\api_latest.json" 'api_latest.json = body'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code (304)'
    Assert-Equal '"abc"' (@(Get-Requests '/latest.json'))[1].if_none_match 'second request sends If-None-Match'
    $r = Invoke-Agent $h -Env (Peer) -ArgStr '-Force'
    Assert-Equal 0 $r.Code 'exit code (-Force)'
    Assert-True ($null -eq (@(Get-Requests '/latest.json'))[2].if_none_match) '-Force sends no If-None-Match'
}

TC 'AGT-017 200 without ETag deletes api_etag.txt' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-171' -Etag $null
    Write-State "$h\installed_version.txt" $rel.Ver
    Write-State "$h\api_etag.txt" '"old"'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-PathMissing "$h\api_etag.txt" 'api_etag.txt removed'
    Assert-PathExists "$h\api_latest.json" 'cache written'
}

TC 'AGT-018 304 takes the release from api_latest.json and downloads its asset' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.13-7'
    $cache = ConvertTo-Json @{ tag_name = 'v2026.10.13-7'; assets = @(@{ name = 'xrRazom_fixes.zip'; browser_download_url = $rel.Url }) } -Depth 5
    W "$h\api_latest.json" $cache -NoBom
    Write-State "$h\api_etag.txt" '"cached"'
    Write-State "$h\installed_version.txt" '2026.10.13-6'
    W (Join-Path $script:Www 'latest.json') '{"tag_name":"v9.9.9","assets":[]}' -NoBom   # would be wrong if used
    Set-Route '/latest.json' @{ status = 304 }
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 1 @(Get-Requests $rel.ZipPath).Count 'asset of the cached release downloaded'
    Assert-Equal '2026.10.13-7' (First "$h\installed_version.txt") 'installed_version.txt'
}

TC 'AGT-019 AGT-045 404/403/429/offline: one log line, exit 0, no dl, no failed_version, no notification' {
    $cases = @(
        @{ Status = 404; Line = 'GitHub: релизов пока нет (404).' },
        @{ Status = 403; Line = 'GitHub: лимит запросов (403), попробую позже.' },
        @{ Status = 429; Line = 'GitHub: лимит запросов (429), попробую позже.' },
        @{ Status = 0; Line = 'Нет связи с GitHub (0): ' }
    )
    foreach ($c in $cases) {
        $sb = New-Sandbox; $h = New-PeerHome $sb
        Write-State "$h\mode.txt" 'peer'
        $env2 = Peer
        if ($c.Status -eq 0) { $env2['XRRFIX_API'] = "http://127.0.0.1:$(Get-FreePort)/latest.json" }
        else { W (Join-Path $script:Www 'latest.json') '{}' -NoBom; Set-Route '/latest.json' @{ status = $c.Status } }
        $r = Invoke-Agent $h -Env $env2
        Assert-Equal 0 $r.Code "exit code ($($c.Status))"
        $rec = @(Get-Records (Get-Log $h))
        Assert-Equal 1 $rec.Count "exactly one record ($($c.Status)): $($rec -join ' // ')"
        Assert-Match $rec[0] (Esc $c.Line) "line ($($c.Status))"
        Assert-PathMissing "$h\dl" "dl created ($($c.Status))"
        Assert-PathMissing "$h\failed_version.txt" "failed_version.txt ($($c.Status))"
        Assert-NoNotify (Get-Log $h) "($($c.Status))"
    }
}

TC 'AGT-020 empty tag_name: logged, exit 0' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    W (Join-Path $script:Www 'latest.json') '{"tag_name":"","assets":[]}' -NoBom
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc 'В ответе GitHub нет tag_name.') 'logged'
}

TC 'AGT-020 AGT-045 installed version equals tag (v/V stripped): no download, log unchanged' {
    foreach ($tag in 'v2026.10.13-7', 'V2026.10.13-7') {
        $sb = New-Sandbox; $h = New-PeerHome $sb
        Reset-Www
        $rel = New-Release '2026.10.13-7' -Tag $tag
        Write-State "$h\installed_version.txt" '2026.10.13-7'
        Write-State "$h\mode.txt" 'peer'
        $r = Invoke-Agent $h -Env (Peer)
        Assert-Equal 0 $r.Code "exit code ($tag)"
        Assert-Equal 0 @(Get-Records (Get-Log $h)).Count "no records besides the test-mode line ($tag)"
        Assert-Equal 0 @(Get-Requests $rel.ZipPath).Count "asset not requested ($tag)"
        Assert-PathMissing "$h\dl" "dl ($tag)"
    }
}

TC 'AGT-021 failed version younger than 60 min is skipped, older is retried' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-21'
    Write-State "$h\failed_version.txt" $rel.Ver
    (Get-Item "$h\failed_version.txt").LastWriteTime = (Get-Date).AddMinutes(-10)
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code (paused)'
    Assert-Equal 0 @(Get-Requests $rel.ZipPath).Count 'asset not requested within 60 min'
    (Get-Item "$h\failed_version.txt").LastWriteTime = (Get-Date).AddMinutes(-61)
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code (retry)'
    Assert-Equal 1 @(Get-Requests $rel.ZipPath).Count 'asset downloaded after 60 min'
    Assert-Equal $rel.Ver (First "$h\installed_version.txt") 'installed'
}

TC 'AGT-022 AGT-045 running blocker (mask) defers before download' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-22'
    $p = Start-FakeMo2
    try {
        $r = Invoke-Agent $h -Env (Peer @{ XRRFIX_BLOCK_PROCS = 'nothing_like_this,xrrfix_fake_mo2_ag*' })
    } finally { Stop-FakeMo2 $p }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Обновление $($rel.Ver) отложено: запущен $script:FAKE_PROC.") 'deferred line'
    Assert-Equal 0 @(Get-Requests $rel.ZipPath).Count 'asset not requested'
    Assert-True (-not (Test-Path "$h\dl") -or @(Get-ChildItem "$h\dl" -Force).Count -eq 0) 'dl empty or absent'
    Assert-PathMissing "$h\installed_version.txt" 'installed_version.txt'
    Assert-NoNotify (Get-Log $h)
}

TC 'AGT-023 AGT-046 wrong GAMMA root: exit 1 twice, failed_version=noroot, notification once' {
    $sb = New-Sandbox; $h = New-PeerHome $sb -NoRoot
    $rel = New-Release '2026.10.14-23'
    $r1 = Invoke-Agent $h -Env (Peer)
    $r2 = Invoke-Agent $h -Env (Peer)
    Assert-Equal 1 $r1.Code 'exit code 1'
    Assert-Equal 1 $r2.Code 'exit code 2'
    $log = Get-Log $h
    Assert-Equal 2 (Count-Of $log "Папка GAMMA не задана или неверна (''). Запустите setup_agent.bat ещё раз.") 'logged each run'
    Assert-Equal 1 (Count-Of $log '[тест] уведомление: xrRazom fixes: нужна настройка | Не найдена папка GAMMA. Запустите setup_agent.bat ещё раз.') 'one notification'
    Assert-Equal 'noroot' (First "$h\failed_version.txt") 'failed_version.txt'
    Assert-Equal 0 @(Get-Requests $rel.ZipPath).Count 'asset not requested'
}

TC 'AGT-024 AGT-045 release without the asset: exit 0, no failed_version, no notification' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-24' -NoAsset
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "В релизе $($rel.Ver) нет файла xrRazom_fixes.zip - пропуск.") 'logged'
    Assert-PathMissing "$h\failed_version.txt" 'failed_version.txt'
    Assert-NoNotify (Get-Log $h)
}

TC 'AGT-025 AGT-045 download error: dl cleared, exit 0, no failed_version, retried next run' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-25'
    Set-Route $rel.ZipPath @{ status = 500 }
    W "$h\dl\junk\old.txt" 'junk'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Не удалось скачать $($rel.Url): ") 'logged'
    Assert-PathMissing "$h\dl\junk" 'dl cleared before download'
    Assert-PathMissing "$h\failed_version.txt" 'failed_version.txt'
    Assert-NoNotify (Get-Log $h)
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 2 @(Get-Requests $rel.ZipPath).Count 'asset requested again'
    Set-Route $rel.ZipPath @{ status = 200 }
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal $rel.Ver (First "$h\installed_version.txt") 'installed once the asset works'
}

TC 'AGT-026 AGT-046 corrupt archive: exit 1, failed_version=ver, notification' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-26' -Corrupt
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 1 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log (Esc 'Архив повреждён: ') 'logged'
    Assert-Equal $rel.Ver (First "$h\failed_version.txt") 'failed_version.txt'
    Assert-Match $log (Esc "[тест] уведомление: xrRazom fixes: ошибка | Архив версии $($rel.Ver) повреждён. Подробности: $h\agent.log") 'notification'
}

TC 'AGT-026 zip without install.ps1: exit 1 with notification' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-261' -NoInstaller
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 1 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log (Esc 'В архиве нет install.ps1.') 'logged'
    Assert-Match $log (Esc "[тест] уведомление: xrRazom fixes: ошибка | В архиве версии $($rel.Ver) нет install.ps1.") 'notification'
    Assert-Equal $rel.Ver (First "$h\failed_version.txt") 'failed_version.txt'
}

TC 'AGT-026 package in a single subfolder runs from it; pack.txt version mismatch is only a warning' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-262' -Nested -PackVersion 'other'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log (Esc "  | STUB-CWD=$h\dl\pkg_$($rel.Ver)\xrRazom_fixes") 'installer cwd = subfolder'
    Assert-Match $log (Esc "Внимание: pack.txt version=other, тег $($rel.Ver).") 'warning'
    Assert-Equal $rel.Ver (First "$h\installed_version.txt") 'installed'
}

TC 'AGT-027 installer stdout/stderr logged with "  | ", -NoWait passed, child LOCALAPPDATA = parent of <home>' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-27'
    $r = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_LINES = 'hello'; STUB_INSTALL_STDERR = 'stub-stderr-line' })
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log '\d\d:\d\d:\d\d   \| hello\r\n' 'stdout line'
    Assert-Match $log (Esc '  | stub-stderr-line') 'stderr line'
    Assert-Match $log (Esc '  | STUB-INSTALL NoWait=True') '-NoWait passed'
    Assert-Match $log ((Esc "  | STUB-LAD=$sb") + '\r\n') 'LOCALAPPDATA = parent of <home>'
}

TC 'AGT-028 AGT-044 success: installed_version (BOM+CRLF), failed_version removed, dl emptied, notification with mods' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-28'
    Write-State "$h\failed_version.txt" 'older'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal $rel.Ver (First "$h\installed_version.txt") 'installed_version.txt'
    $b = [IO.File]::ReadAllBytes("$h\installed_version.txt")
    Assert-True ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF -and $b[-2] -eq 13 -and $b[-1] -eq 10) 'UTF-8 BOM + CRLF'
    Assert-PathMissing "$h\failed_version.txt" 'failed_version.txt removed'
    Assert-Equal 0 @(Get-ChildItem "$h\dl" -Force).Count 'dl emptied'
    $log = Get-Log $h
    Assert-Match $log (Esc "Установлено: $($rel.Ver)") 'installed line'
    Assert-Match $log ((Esc "[тест] уведомление: xrRazom fixes | Фиксы xrRazom обновлены до $($rel.Ver)") + '\r?\n' + (Esc 'Мод Один, Mod B')) 'notification with mod names'
}

TC 'AGT-029 AGT-045 installer exit 2 defers: both runs download and run the installer' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-29'
    $r1 = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_CODE = '2' })
    $r2 = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_CODE = '2' })
    Assert-Equal 0 $r1.Code 'exit code 1'
    Assert-Equal 0 $r2.Code 'exit code 2'
    $log = Get-Log $h
    Assert-Equal 2 @(Get-Requests $rel.ZipPath).Count 'downloaded twice'
    Assert-Equal 2 (Count-Of $log '  | STUB-INSTALL') 'installer ran twice'
    Assert-Equal 2 (Count-Of $log "Обновление $($rel.Ver) отложено: запущен Mod Organizer.") 'deferred line'
    Assert-PathMissing "$h\failed_version.txt" 'failed_version.txt'
    Assert-PathMissing "$h\installed_version.txt" 'installed_version.txt'
    Assert-NoNotify $log
}

TC 'AGT-030 AGT-039 installer exit 5: exit 1, failed_version, dl kept, notification, no self-update' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-30' -WithAgent
    $before = FHash "$h\agent\xrrfix_agent.ps1"
    $r = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_CODE = '5' })
    Assert-Equal 1 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log (Esc "Ошибка установки $($rel.Ver) (код 5).") 'logged'
    Assert-Match $log (Esc "[тест] уведомление: xrRazom fixes: ошибка обновления | Не удалось установить $($rel.Ver). Подробности: $h\agent.log") 'notification'
    Assert-Equal $rel.Ver (First "$h\failed_version.txt") 'failed_version.txt'
    Assert-PathExists "$h\dl\pkg_$($rel.Ver)" 'dl kept'
    Assert-Equal $before (FHash "$h\agent\xrrfix_agent.ps1") 'agent must not self-update'
    Assert-NotMatch $log 'Агент обновлён' 'no update line'
}

TC 'AGT-031 -Force reinstalls the installed version and ignores the failure pause' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-31'
    Write-State "$h\installed_version.txt" $rel.Ver
    Write-State "$h\failed_version.txt" $rel.Ver
    $r = Invoke-Agent $h -Env (Peer) -ArgStr '-Force'
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 1 @(Get-Requests $rel.ZipPath).Count 'asset downloaded'
    Assert-Match (Get-Log $h) (Esc '  | STUB-INSTALL') 'installer ran'
}

TC 'AGT-031 -Force still defers on a blocker and still checks the GAMMA root' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-311'
    Write-State "$h\installed_version.txt" $rel.Ver
    $p = Start-FakeMo2
    try { $r = Invoke-Agent $h -Env (Peer) -ArgStr '-Force' } finally { Stop-FakeMo2 $p }
    Assert-Equal 0 $r.Code 'exit code (blocker)'
    Assert-Match (Get-Log $h) (Esc "Обновление $($rel.Ver) отложено: запущен $script:FAKE_PROC.") 'deferred'
    Assert-Equal 0 @(Get-Requests $rel.ZipPath).Count 'asset not requested'
    $sb2 = New-Sandbox; $h2 = New-PeerHome $sb2 -NoRoot
    $r = Invoke-Agent $h2 -Env (Peer) -ArgStr '-Force'
    Assert-Equal 1 $r.Code 'exit code (no root)'
    Assert-Equal 'noroot' (First "$h2\failed_version.txt") 'noroot'
}

TC 'AGT-046 repeated failure of the same version: no notification, mtime refreshed; -Force -Interactive notifies' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $rel = New-Release '2026.10.14-46'
    Write-State "$h\failed_version.txt" $rel.Ver
    (Get-Item "$h\failed_version.txt").LastWriteTime = (Get-Date).AddMinutes(-61)
    $r = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_CODE = '5' })
    Assert-Equal 1 $r.Code 'exit code'
    Assert-NoNotify (Get-Log $h) '(same key)'
    Assert-True (((Get-Date) - (Get-Item "$h\failed_version.txt").LastWriteTime).TotalMinutes -lt 5) 'mtime refreshed'
    $r = Invoke-Agent $h -Env (Peer @{ STUB_INSTALL_CODE = '5' }) -ArgStr '-Force -Interactive'
    Assert-Equal 1 $r.Code 'exit code (interactive)'
    Assert-Match (Get-Log $h) (Esc '[тест] уведомление: xrRazom fixes: ошибка обновления') 'notified when interactive'
    Assert-Match $r.Out (Esc '[xrRazom fixes: ошибка обновления]') 'console echo'
}
