# Self-update cases (AGT-039..042). Dot-sourced by run.ps1. Uses New-HostCase / HostEnv / New-PeerHome / Peer.

TC 'AGT-039 host: clone agent\ changes are copied after any sync outcome (0, 1, 2, 3)' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    foreach ($code in 0, 1, 2, 3) {
        W "$($k.C)\agent\README.txt" "новый README $code`r`n"
        $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_CODE = "$code"; STUB_LINES = $script:Quiet0 })
        Assert-Equal (@{ 0 = 0; 1 = 1; 2 = 0; 3 = 3 })[$code] $r.Code "agent exit code (publish $code)"
        Assert-FilesEqual "$($k.C)\agent\README.txt" "$($k.H)\agent\README.txt" "README updated after publish exit $code"
    }
    Assert-Equal 4 (Count-Of (Get-Log $k.H) "Агент обновлён из $($k.C)\agent: README.txt") 'update logged each time'
}

TC 'AGT-040 only changed/new top-level .ps1/.bat/.txt are copied; others kept; equal -> no update' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $old = (Get-Date).AddYears(-3)
    (Get-Item "$($k.H)\agent\xrrfix_agent.ps1").LastWriteTime = $old
    W "$($k.H)\agent\local_only.txt" 'keep me'
    [IO.File]::AppendAllText("$($k.C)\agent\uninstall_agent.ps1", "`r`n# changed`r`n")
    W "$($k.C)\agent\extra.txt" 'extra'
    W "$($k.C)\agent\notes.md" 'not copied'
    W "$($k.C)\agent\sub\deep.txt" 'not copied'
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $script:Quiet0 })
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $k.H) ((Esc "Агент обновлён из $($k.C)\agent: extra.txt, uninstall_agent.ps1") + '\r\n') 'exactly the two files'
    Assert-FilesEqual "$($k.C)\agent\uninstall_agent.ps1" "$($k.H)\agent\uninstall_agent.ps1" 'uninstall copied'
    Assert-PathExists "$($k.H)\agent\extra.txt" 'new file copied'
    Assert-PathMissing "$($k.H)\agent\notes.md" '.md must not be copied'
    Assert-PathMissing "$($k.H)\agent\sub" 'subfolders must not be copied'
    Assert-PathExists "$($k.H)\agent\local_only.txt" 'files missing in the source are kept'
    Assert-Equal $old.Ticks (Get-Item "$($k.H)\agent\xrrfix_agent.ps1").LastWriteTime.Ticks 'xrrfix_agent.ps1 untouched (mtime)'
    $before = Get-Log $k.H
    $null = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $script:Quiet0 })
    Assert-NotMatch (Get-NewLog $k.H $before) 'Агент обновлён' 'all equal -> no update'
}

TC 'AGT-040 no <home>\agent: nothing is copied' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\xrrfix" -NoAgent
    W "$c\agent\README.txt" "changed`r`n"
    $r = Invoke-Agent $h -Script "$c\agent\xrrfix_agent.ps1" -Env @{ XRRFIX_REPO = $c; STUB_LINES = $script:Quiet0 }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-PathMissing "$h\agent" '<home>\agent must not be created'
    Assert-NotMatch (Get-Log $h) 'Агент обновлён' 'no update line'
}

TC 'AGT-041 a syntax-broken .ps1 blocks the whole update' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    $hA = FHash "$($k.H)\agent\xrrfix_agent.ps1"; $hR = FHash "$($k.H)\agent\README.txt"
    W "$($k.C)\agent\README.txt" "новый`r`n"
    [IO.File]::AppendAllText("$($k.C)\agent\xrrfix_agent.ps1", "`r`nfunction broken {`r`n")
    $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $script:Quiet0 })
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal $hA (FHash "$($k.H)\agent\xrrfix_agent.ps1") 'xrrfix_agent.ps1 unchanged'
    Assert-Equal $hR (FHash "$($k.H)\agent\README.txt") 'README.txt unchanged'
    Assert-Match (Get-Log $k.H) (Esc 'Агент НЕ обновлён: ошибка синтаксиса в xrrfix_agent.ps1: ') 'refusal logged'
}

TC 'AGT-039 AGT-042 peer: zip without agent\ leaves the agent; zip with agent\ updates it in finally, dl emptied, task command runs it' {
    $sb = New-Sandbox; $h = New-PeerHome $sb
    $hb = FHash "$h\agent\xrrfix_agent.ps1"
    $rel1 = New-Release '2026.10.14-421'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code (no agent in zip)'
    Assert-Equal $rel1.Ver (First "$h\installed_version.txt") 'installed 1'
    Assert-Equal $hb (FHash "$h\agent\xrrfix_agent.ps1") 'agent unchanged without agent\ in the zip'
    $rel2 = New-Release '2026.10.14-422' -WithAgent -AgentMarker 'selfupdate-marker-peer' -Etag '"v2"'
    $r = Invoke-Agent $h -Env (Peer)
    Assert-Equal 0 $r.Code 'exit code (agent in zip)'
    Assert-Equal $rel2.Ver (First "$h\installed_version.txt") 'installed 2'
    Assert-FilesEqual "$($rel2.Pkg)\agent\xrrfix_agent.ps1" "$h\agent\xrrfix_agent.ps1" 'agent updated from the zip'
    Assert-Match (Get-Log $h) (Esc "Агент обновлён из $h\dl\pkg_$($rel2.Ver)\agent: xrrfix_agent.ps1") 'update logged'
    Assert-Equal 0 @(Get-ChildItem "$h\dl" -Force).Count 'dl emptied after the update'
    # the scheduled task's command line (conhost --headless when available) still runs <home>\agent\xrrfix_agent.ps1
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $ps = Join-Path $PSHOME 'powershell.exe'
    $psArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$h\agent\xrrfix_agent.ps1`""
    $psi = New-Object Diagnostics.ProcessStartInfo
    if ([Environment]::OSVersion.Version.Build -ge 19041 -and (Test-Path $conhost)) { $psi.FileName = $conhost; $psi.Arguments = "--headless `"$ps`" $psArgs" }
    else { $psi.FileName = $ps; $psi.Arguments = $psArgs }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $ev = $psi.EnvironmentVariables
    $ev['LOCALAPPDATA'] = $script:Lad; $ev['XRRFIX_HOME'] = $h; $ev['XRRFIX_REPO'] = 'none'; $ev['XRRFIX_API'] = $script:ApiUrl
    $ev['XRRFIX_NO_NOTIFY'] = '1'; $ev['XRRFIX_BLOCK_PROCS'] = $script:FAKE_PROC
    $before = Get-Log $h
    $p = [Diagnostics.Process]::Start($psi); [void]$script:Children.Add($p)
    if (-not $p.WaitForExit(120000)) { Stop-Tree $p.Id; throw 'task command timed out' }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-NewLog $h $before) -notmatch '\[тест\] XRRFIX_HOME=' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    Assert-Match (Get-NewLog $h $before) (Esc "[тест] XRRFIX_HOME=$h") 'task command runs the updated agent'
}

TC 'AGT-042 a self-update exception is logged and does not change the exit code' {
    $sb = New-Sandbox; $k = New-HostCase $sb
    W "$($k.C)\agent\README.txt" "changed`r`n"
    $ro = Get-Item "$($k.H)\agent\README.txt"
    $ro.IsReadOnly = $true
    try {
        $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_LINES = $script:Quiet0 })
        Assert-Equal 0 $r.Code 'exit code'
        Assert-Match (Get-Log $k.H) (Esc 'Самообновление не удалось: ') 'logged'
        $r = Invoke-Agent $k.H -Env (HostEnv $k @{ STUB_CODE = '3'; STUB_LINES = 'XRRFIX_SYNC_CONFLICT: mods=A' })
        Assert-Equal 3 $r.Code 'exit code 3 kept'
    } finally { (Get-Item "$($k.H)\agent\README.txt").IsReadOnly = $false }
}
