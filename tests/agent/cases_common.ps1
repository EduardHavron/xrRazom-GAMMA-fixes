# Every-run cases: home, mutex, clone detection, mode log, notifications switch, log format/trim, exceptions
# (AGT-010..016, 044, 047..049). Dot-sourced by run.ps1.

function Get-MutexName([string]$H) { 'Local\xrrfix_agent_' + ($H.ToLowerInvariant().TrimEnd('\') -replace '[^a-z0-9]', '_') }

TC 'AGT-010 agent creates a missing <home> and logs the test-mode line first' {
    $sb = New-Sandbox
    $h = "$sb\new\xrrfix"
    $dead = "http://127.0.0.1:$(Get-FreePort)/latest.json"
    $r = Invoke-Agent $h -Script "$script:SrcAgent\xrrfix_agent.ps1" -Env @{ XRRFIX_REPO = 'none'; XRRFIX_API = $dead }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-PathExists $h '<home> created'
    $lines = @((Get-Log $h) -split "`r`n" | Where-Object { $_ })
    Assert-Match $lines[0] ('^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ' + (Esc "[тест] XRRFIX_HOME=$h API=$dead REPO=none") + '$') 'first record'
    Assert-Match (Get-Log $h) (Esc 'Нет связи с GitHub (0)') 'offline logged'
}

TC 'AGT-011 held mutex: agent exits 0 without touching the log or state; other <home> runs' {
    $sb = New-Sandbox
    $h = New-AgentHome "$sb\a\xrrfix"; $h2 = New-AgentHome "$sb\b\xrrfix"
    Write-State "$h\agent.log" 'sentinel'; Write-State "$h\mode.txt" 'sentinel'
    $logHash = FHash "$h\agent.log"; $modeHash = FHash "$h\mode.txt"
    $m = New-Object Threading.Mutex($false, (Get-MutexName $h))
    $null = $m.WaitOne(0)
    try {
        $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
        Assert-Equal 0 $r.Code 'exit code (busy)'
        $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' } -ArgStr '-Interactive'
        Assert-Equal 0 $r.Code 'exit code (busy, interactive)'
        Assert-Match $r.Out (Esc 'Агент уже работает, попробуйте через минуту.') 'interactive message'
        Assert-Equal $logHash (FHash "$h\agent.log") 'agent.log changed'
        Assert-Equal $modeHash (FHash "$h\mode.txt") 'mode.txt changed'
        $r = Invoke-Agent $h2 -Env @{ XRRFIX_REPO = 'none' }
        Assert-Equal 0 $r.Code 'other home exit code'
        Assert-Match (Get-Log $h2) (Esc '[тест] XRRFIX_HOME=') 'other home ran'
    } finally { try { $m.ReleaseMutex() } catch { }; $m.Dispose() }
}

TC 'AGT-011 abandoned mutex counts as acquired' {
    $sb = New-Sandbox
    $h = New-AgentHome "$sb\xrrfix"
    $name = Get-MutexName $h
    $holder = "$sb\holder.ps1"
    W $holder "`$x = New-Object Threading.Mutex(`$false, '$name'); [void]`$x.WaitOne(0); exit 0`r`n"
    $keep = New-Object Threading.Mutex($false, $name)   # keeps the kernel object alive -> it becomes abandoned
    try {
        $r = Invoke-Ps -Script $holder
        Assert-Equal 0 $r.Code 'holder exit'
        $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
        Assert-Equal 0 $r.Code 'exit code'
        Assert-Match (Get-Log $h) (Esc '[тест] XRRFIX_HOME=') 'agent ran despite the abandoned mutex'
    } finally { $keep.Dispose() }
}

TC 'AGT-012 AGT-015 clone beside GAMMA (ssh origin) found via the gamma_root parent scan and cached' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $c = New-StubClone "$sb\repo" -Origin 'git@github.com:EduardHavron/xrRazom-GAMMA-fixes.git'
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ STUB_MARK = "$sb\mark.txt"; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Режим хоста: клон репозитория $c (синхронизация через host\publish.ps1 -SyncOnly).") 'host mode line'
    Assert-PathExists "$sb\mark.txt" 'publish ran'
    Assert-Equal $c (First "$h\repo_root.txt") 'repo_root.txt cached'
}

TC 'AGT-012 clone inside the GAMMA folder found via the gamma_root scan' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $c = New-StubClone "$g\xrRazom-GAMMA-fixes"
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal $c (First "$h\repo_root.txt") 'repo_root.txt'
    Assert-Equal "host|$c" (First "$h\mode.txt") 'mode.txt'
}

TC 'AGT-012 XRRFIX_REPO=none forces peer mode even with a clone beside GAMMA' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $null = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none'; STUB_MARK = "$sb\mark.txt" }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc 'Обычный режим: установка релизов с GitHub.') 'peer mode'
    Assert-PathMissing "$sb\mark.txt" 'publish must not run'
    Assert-PathMissing "$h\repo_root.txt" 'no repo_root.txt'
    Assert-Equal 1 @(Get-Requests '/latest.json').Count 'API queried'
}

TC 'AGT-012 XRRFIX_REPO pointing to a non-clone folder gives peer mode with a note' {
    $sb = New-Sandbox
    $nc = "$sb\notaclone"; New-Item -ItemType Directory $nc | Out-Null
    $h = New-AgentHome "$sb\home\xrrfix"
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = $nc }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Обычный режим (релизы GitHub): XRRFIX_REPO='$nc' - не клон репозитория.") 'note'
}

TC 'AGT-012 repo_root.txt candidate has priority over the GAMMA scan' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $null = New-StubClone "$sb\a_repo"
    $c2 = New-StubClone "$sb\other\second"
    $h = New-AgentHome "$sb\home\xrrfix" $g
    Write-State "$h\repo_root.txt" $c2
    $r = Invoke-Agent $h -Env @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal "host|$c2" (First "$h\mode.txt") 'cached clone chosen'
}

TC 'AGT-013 first candidate with the right origin wins (a foreign, b right)' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $null = New-StubClone "$sb\a" -Origin 'https://github.com/someone/other-repo.git'
    $b = New-StubClone "$sb\b"
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal "host|$b" (First "$h\mode.txt") 'host mode with b'
}

TC 'AGT-013 folder without agent\xrrfix_agent.ps1 is not a clone' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $null = New-StubClone "$sb\repo" -NoAgentScript      # right origin, files incomplete
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 'peer' (First "$h\mode.txt") 'plain peer mode (no origin note -> origin never checked)'
}

TC 'AGT-013 .git as a file and a case-insensitive origin marker are accepted' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $c = New-StubClone "$sb\repo" -SeparateGitDir -Origin 'https://github.com/eduardhavron/XRRAZOM-gamma-fixes.git'
    Assert-True (Test-Path -LiteralPath "$c\.git" -PathType Leaf) '.git must be a file'
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal "host|$c" (First "$h\mode.txt") 'host mode'
}

TC 'AGT-013 only foreign origins: peer mode with the "origin не" note, no repo_root.txt' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $c = New-StubClone "$g\some-fork" -Origin 'https://github.com/someone/other-repo.git'
    $h = New-AgentHome "$sb\home\xrrfix" $g
    $r = Invoke-Agent $h -Env @{ STUB_MARK = "$sb\mark.txt" }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Обычный режим (релизы GitHub): у $c origin не EduardHavron/xrRazom-GAMMA-fixes.") 'note'
    Assert-PathMissing "$h\repo_root.txt" 'no repo_root.txt'
    Assert-PathMissing "$sb\mark.txt" 'publish must not run'
}

TC 'AGT-014 no git on PATH: peer mode with a note, API queried, publish not run' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\home\xrrfix"
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = $c; PATH = (Get-PathWithoutGit); STUB_MARK = "$sb\mark.txt" }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc "Обычный режим (релизы GitHub): найден клон $c, но git не найден в PATH.") 'note'
    Assert-Equal 1 @(Get-Requests '/latest.json').Count 'API queried'
    Assert-PathMissing "$sb\mark.txt" 'publish must not run'
}

TC 'AGT-015 invalid repo_root.txt is replaced by the re-detected clone' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $c = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\home\xrrfix" $g
    Write-State "$h\repo_root.txt" "$sb\deleted\clone"
    $r = Invoke-Agent $h -Env @{ STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal $c (First "$h\repo_root.txt") 'repo_root.txt re-detected'
}

TC 'AGT-015 XRRFIX_REPO neither creates nor changes repo_root.txt' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\h1\xrrfix"
    $null = Invoke-Agent $h -Env @{ XRRFIX_REPO = $c; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal "host|$c" (First "$h\mode.txt") 'forced host mode'
    Assert-PathMissing "$h\repo_root.txt" 'repo_root.txt created'
    $h2 = New-AgentHome "$sb\h2\xrrfix"
    Write-State "$h2\repo_root.txt" "$sb\elsewhere"
    $null = Invoke-Agent $h2 -Env @{ XRRFIX_REPO = $c; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal "$sb\elsewhere" (First "$h2\repo_root.txt") 'repo_root.txt changed'
}

TC 'AGT-015 invalid repo_root.txt is kept when no clone is found' {
    $sb = New-Sandbox
    $h = New-AgentHome "$sb\home\xrrfix"
    Write-State "$h\repo_root.txt" "$sb\gone"
    $r = Invoke-Agent $h
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal "$sb\gone" (First "$h\repo_root.txt") 'repo_root.txt must stay'
}

TC 'AGT-016 mode line logged only on change; mode.txt keys; -Interactive prints it every run' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $nc = "$sb\plain"; New-Item -ItemType Directory $nc | Out-Null
    $h = New-AgentHome "$sb\home\xrrfix"
    $peer = 'Обычный режим: установка релизов с GitHub.'
    $null = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    $null = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    Assert-Equal 1 (Count-Of (Get-Log $h) $peer) 'peer line once after two runs'
    Assert-Equal 'peer' (First "$h\mode.txt") 'mode.txt = peer'
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' } -ArgStr '-Interactive'
    Assert-Match $r.Out (Esc $peer) 'interactive run prints the mode'
    Assert-Equal 1 (Count-Of (Get-Log $h) $peer) 'still once in the log'
    $null = Invoke-Agent $h -Env @{ XRRFIX_REPO = $nc }
    Assert-Equal "peer|XRRFIX_REPO='$nc' - не клон репозитория." (First "$h\mode.txt") 'mode.txt = peer|note'
    $null = Invoke-Agent $h -Env @{ XRRFIX_REPO = $c; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=0 mods=' }
    Assert-Equal "host|$c" (First "$h\mode.txt") 'mode.txt = host|path'
    Assert-Equal 1 (Count-Of (Get-Log $h) 'Режим хоста: клон репозитория') 'host line logged on change'
}

TC 'AGT-044 XRRFIX_NO_NOTIFY=1 outside test mode: no notification at all' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $lad2 = "$sb\lad2"
    $h = New-AgentHome "$lad2\xrrfix"      # <home> == LOCALAPPDATA\xrrfix of this child -> not test mode (agent only, all in temp)
    $r = Invoke-Agent $h -NonTestMode -Env @{ LOCALAPPDATA = $lad2; XRRFIX_REPO = $c; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=1 mods=A' }
    Assert-Equal 0 $r.Code 'exit code'
    $log = Get-Log $h
    Assert-Match $log (Esc 'Синхронизация: установлено 1 (A).') 'sync logged'
    Assert-NotMatch $log 'уведомление' 'no notification / no [тест] line'
    Assert-NotMatch $log '\[тест\]' 'not test mode'
}

TC 'AGT-044 test mode: notification becomes a log line; -Interactive echoes [title] text' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\repo"
    $h = New-AgentHome "$sb\xrrfix"
    $r = Invoke-Agent $h -ArgStr '-Interactive' -Env @{ XRRFIX_REPO = $c; STUB_LINES = 'XRRFIX_SYNC_RESULT: installed=1 mods=A' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc '[тест] уведомление: xrRazom fixes | Фиксы xrRazom обновлены: A') 'log line'
    Assert-Match $r.Out (Esc '[xrRazom fixes] Фиксы xrRazom обновлены: A') 'console echo'
}

TC 'AGT-047 agent.log records are "yyyy-MM-dd HH:mm:ss msg", CRLF, UTF-8 with BOM; -Interactive echoes them' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $h = New-AgentHome "$sb\xrrfix" $g
    $null = New-Release '2026.10.14-47'
    $r = Invoke-Agent $h -ArgStr '-Interactive' -Env @{ XRRFIX_REPO = 'none'; STUB_INSTALL_CODE = '5'; STUB_INSTALL_LINES = 'строка один|line two' }
    Assert-Equal 1 $r.Code 'exit code'
    Assert-Match $r.Out (Esc 'Ошибка установки 2026.10.14-47 (код 5).') 'console echo'
    $bytes = [IO.File]::ReadAllBytes("$h\agent.log")
    Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'UTF-8 BOM'
    $text = (New-Object Text.UTF8Encoding($true, $true)).GetString($bytes, 3, $bytes.Length - 3)   # throws on invalid UTF-8
    Assert-Match $text '  \| строка один' 'Cyrillic intact'
    Assert-True ($text.EndsWith("`r`n")) 'ends with CRLF'
    Assert-NotMatch $text '[^\r]\n' 'bare LF found'
    $lines = @($text -split "`r`n" | Where-Object { $_ })
    Assert-True ($lines.Count -ge 5) "expected several records, got $($lines.Count)"
    foreach ($l in $lines) { Assert-Match $l '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d ' "record format: $l" }
}

function Write-LogLines([string]$H, [int]$N) {
    New-Item -ItemType Directory $H -Force | Out-Null
    $l = 1..$N | ForEach-Object { '2020-01-01 00:00:00 old {0}' -f $_ }
    [IO.File]::WriteAllLines("$H\agent.log", [string[]]$l, $script:Utf8Bom)
}

TC 'AGT-048 a log over 600 lines is trimmed to the last 500, ending with this run' {
    $sb = New-Sandbox
    $h = New-AgentHome "$sb\xrrfix"
    Write-LogLines $h 700
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    Assert-Equal 0 $r.Code 'exit code'
    $lines = [IO.File]::ReadAllLines("$h\agent.log")
    Assert-Equal 500 $lines.Count 'line count'
    Assert-Match $lines[-1] (Esc 'GitHub: релизов пока нет (404).') 'last line = last record of this run'
}

TC 'AGT-048 a log of exactly 600 lines after the run is not trimmed' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $h = New-AgentHome "$sb\xrrfix" $g
    $null = New-Release '2026.10.14-48'
    Write-State "$h\installed_version.txt" '2026.10.14-48'
    Write-State "$h\mode.txt" 'peer'
    Write-LogLines $h 599
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 600 ([IO.File]::ReadAllLines("$h\agent.log")).Count 'line count'
}

TC 'AGT-049 unexpected exception (corrupt cache + 304): exit 1, logged, next run works' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $h = New-AgentHome "$sb\xrrfix" $g
    Write-State "$h\api_etag.txt" '"abc"'
    W "$h\api_latest.json" '{broken' -NoBom
    Set-Route '/latest.json' @{ status = 304 }
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    Assert-Equal 1 $r.Code 'exit code'
    Assert-Match (Get-Log $h) (Esc 'Непредвиденная ошибка:') 'logged'
    $null = New-Release '2026.10.14-49' -Etag '"fresh"'    # new ETag -> 200, cache rewritten
    Write-State "$h\installed_version.txt" '2026.10.14-49'
    $before = Get-Log $h
    $r = Invoke-Agent $h -Env @{ XRRFIX_REPO = 'none' }
    Assert-Equal 0 $r.Code 'next run exit code'
    Assert-Match (Get-NewLog $h $before) (Esc '[тест] XRRFIX_HOME=') 'next run executed'
}
