# Host mode cases with a stub host\publish.ps1 (AGT-032..038, 045). Dot-sourced by run.ps1.

function New-HostCase([string]$Sb, [switch]$NoOriginMain) {
    $c = New-StubClone "$Sb\repo" -NoOriginMain:$NoOriginMain
    $h = New-AgentHome "$Sb\xrrfix"
    return [pscustomobject]@{ C = $c; H = $h }
}
function HostEnv($k, [hashtable]$Extra = @{}) { $e = @{ XRRFIX_REPO = $k.C }; foreach ($x in $Extra.Keys) { $e[$x] = $Extra[$x] }; return $e }
$script:Quiet0 = 'XRRFIX_SYNC_RESULT: installed=0 mods='

TC 'AGT-032 sync runs publish.ps1 -SyncOnly -NoWait -NoPrompt in the clone (no blocker check, no API), writes sync_last.log' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $p = Start-FakeMo2
    try { $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_MARK = "$sb\mark.txt"; STUB_LINES = $script:Quiet0 }) } finally { Stop-FakeMo2 $p }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 'ran -SyncOnly -NoWait -NoPrompt' (First "$sb\mark.txt") 'publish args (ran despite the running blocker)'
    $sl = [IO.File]::ReadAllLines("$($k.H)\sync_last.log")
    Assert-Match $sl[0] '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d код 0$' 'sync_last.log header'
    $st = $sl -join "`n"
    Assert-Match $st (Esc "STUB publish args=-SyncOnly -NoWait -NoPrompt cwd=$($k.C)") 'cwd = clone'
    Assert-Match $st (Esc "STUB env BLOCK=$script:FAKE_PROC GTP=0") 'XRRFIX_BLOCK_PROCS inherited, GIT_TERMINAL_PROMPT=0'
    Assert-Match $st (Esc 'Проверка кириллицы: секция xrRazom Sync') 'UTF-8 output'
    Assert-Equal 0 @(Get-Requests).Count 'no HTTP requests'
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_CODE = '2' })
    Assert-Match (First "$($k.H)\sync_last.log") ' код 2$' 'sync_last.log overwritten each run'
}

TC 'AGT-033 AGT-045 installed=0 (or no installed=) keeps agent.log silent' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $null = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $script:Quiet0 })
    foreach ($lines in @($script:Quiet0, 'XRRFIX_SYNC_RESULT: mods=Z')) {
        $before = Get-Log $k.H
        $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $lines })
        Assert-Equal 0 $r.Code "exit code ($lines)"
        $new = Get-NewLog $k.H $before
        Assert-Equal 0 @(Get-Records $new).Count "only the test-mode line ($lines): $new"
    }
}

TC 'AGT-033 last XRRFIX_SYNC_RESULT line wins, mods normalised, output logged with "  | "' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=5 mods=X|   XRRFIX_SYNC_RESULT: installed=2 mods=,A , B,|tail line' })
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $k.H
    Assert-Match $log (Esc 'Синхронизация: установлено 2 (A, B).') 'parsed result'
    Assert-Match $log (Esc '  | tail line') 'output logged'
    Assert-Match $log (Esc '  | STUB publish args=-SyncOnly') 'output logged (first line)'
}

TC 'AGT-034 AGT-044 installed>0 notifies with the mod list and removes host_state.txt' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    Write-State "$($k.H)\host_state.txt" 'conflict old'
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=2 mods=A,B' })
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $k.H
    Assert-Match $log (Esc 'Синхронизация: установлено 2 (A, B).') 'logged'
    Assert-Match $log (Esc '[тест] уведомление: xrRazom fixes | Фиксы xrRazom обновлены: A, B') 'notification'
    Assert-PathMissing "$($k.H)\host_state.txt" 'host_state.txt removed'
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=3 mods=' })
    Assert-Match (Get-Log $k.H) (Esc '[тест] уведомление: xrRazom fixes | Фиксы xrRazom обновлены (3)') 'empty list -> count'
}

TC 'AGT-035 AGT-045 exit 2 defers silently, host_state.txt unchanged' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    Write-State "$($k.H)\host_state.txt" 'error zzz'
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_CODE = '2'; STUB_LINES = 'deferred' })
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $k.H
    Assert-Match $log (Esc 'Синхронизация отложена (запущен MO2/игра или publish уже работает).') 'logged'
    Assert-NoNotify $log
    Assert-Equal 'error zzz' (First "$($k.H)\host_state.txt") 'host_state.txt unchanged'
}

TC 'AGT-036 AGT-037 conflict: exit 3 each run, notified once per origin/main sha, again with -Interactive or a new sha' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $sha = (Invoke-Git $k.C rev-parse origin/main).Trim()
    $e = HostEnv $k @{ STUB_CODE = '3'; STUB_LINES = 'КОНФЛИКТ: A|XRRFIX_SYNC_CONFLICT: mods=A,(порядок модов)' }
    $note = '[тест] уведомление: xrRazom fixes: конфликт | Конфликт фиксов: A, (порядок модов), запустите publish.bat'
    foreach ($i in 1..3) { $r = Invoke-Agent $k.H -Env $e; Assert-Equal 3 $r.Code "exit code run $i" }
    $log = Get-Log $k.H
    Assert-Equal 1 (Count-Of $log $note) 'one notification for 3 runs'
    Assert-Equal 3 (Count-Of $log "Синхронизация: конфликт ($sha) A, (порядок модов)") 'logged each run'
    Assert-Equal "conflict $sha" (First "$($k.H)\host_state.txt") 'host_state.txt'
    $r = Invoke-Agent $k.H -Env $e -ArgStr '-Interactive'
    Assert-Equal 3 $r.Code 'exit code (interactive)'
    Assert-Equal 2 (Count-Of (Get-Log $k.H) $note) 'interactive run notifies again'
    Assert-Match $r.Out (Esc '[xrRazom fixes: конфликт] Конфликт фиксов: A') 'console echo'
    Invoke-Git $k.C commit -q --allow-empty -m two | Out-Null
    Invoke-Git $k.C update-ref refs/remotes/origin/main HEAD | Out-Null
    $sha2 = (Invoke-Git $k.C rev-parse origin/main).Trim()
    $r = Invoke-Agent $k.H -Env $e
    Assert-Equal 3 (Count-Of (Get-Log $k.H) $note) 'new origin/main sha -> notified again'
    Assert-Equal "conflict $sha2" (First "$($k.H)\host_state.txt") 'host_state.txt = new sha'
}

TC 'AGT-036 conflict without the machine line: generic text with two "конфликт" lines; no origin/main -> unknown' {
    $sb = New-Sandbox; $k = New-HostCase $sb -NoOriginMain
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_CODE = '3'; STUB_LINES = 'начало|Конфликт: моды X, Y|ещё conflict строка|третья conflict строка' })
    Assert-Equal 3 $r.Code 'exit code'
    $log = Get-Log $k.H
    Assert-Match $log ((Esc '[тест] уведомление: xrRazom fixes: конфликт | Конфликт фиксов, запустите publish.bat. Конфликт: моды X, Y / ещё conflict строка') + '\r\n') 'generic text'
    Assert-Match $log (Esc 'Синхронизация: конфликт (unknown)') 'unknown sha logged'
    Assert-Equal 'conflict unknown' (First "$($k.H)\host_state.txt") 'host_state.txt'
}

TC 'AGT-038 AGT-037 sync error: exit 1 twice, notified once, host_state = error <sha>' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $sha = (Invoke-Git $k.C rev-parse origin/main).Trim()
    $e = HostEnv $k @{ STUB_CODE = '1'; STUB_LINES = 'ОШИБКА: что-то' }
    $r1 = Invoke-Agent $k.H -Env $e
    $r2 = Invoke-Agent $k.H -Env $e
    Assert-Equal 1 $r1.Code 'exit code 1'
    Assert-Equal 1 $r2.Code 'exit code 2'
    $log = Get-Log $k.H
    Assert-Equal 2 (Count-Of $log "Ошибка синхронизации (код 1, origin/main $sha). Полный вывод: $($k.H)\sync_last.log") 'logged each run'
    Assert-Equal 1 (Count-Of $log "[тест] уведомление: xrRazom fixes: ошибка синхронизации | publish.ps1 -SyncOnly завершился с кодом 1. Подробности: $($k.H)\agent.log") 'one notification'
    Assert-Equal "error $sha" (First "$($k.H)\host_state.txt") 'host_state.txt'
    Assert-Match $log (Esc '  | ОШИБКА: что-то') 'publish output logged'
}
