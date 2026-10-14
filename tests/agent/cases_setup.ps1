# setup_agent.ps1 / uninstall_agent.ps1 cases (AGT-001..004, 007, 009, 052). Dot-sourced by run.ps1.

# a copy of agent\ outside any clone (so setup's "parent of setup folder" candidate is not a clone)
function New-SetupSource([string]$Dir) {
    New-Item -ItemType Directory $Dir -Force | Out-Null
    Copy-Item "$script:SrcAgent\*" "$Dir\" -Force
    return $Dir
}

TC 'AGT-001 setup copies the six agent files byte-exact and unblocks them' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    foreach ($f in $script:AgentFiles) { Set-Content -LiteralPath "$src\$f" -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" }
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Match $r.Out (Esc "Файлы агента скопированы в $h\agent") 'copy message'
    foreach ($f in $script:AgentFiles) {
        Assert-FilesEqual "$src\$f" "$h\agent\$f" "$f byte-exact"
        $zi = Get-Item -LiteralPath "$h\agent\$f" -Stream Zone.Identifier -ErrorAction SilentlyContinue
        Assert-True ($null -eq $zi) "$f still has Zone.Identifier"
    }
}

TC 'AGT-001 setup without xrrfix_agent.ps1 fails and creates no agent folder' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    Remove-Item -LiteralPath "$src\xrrfix_agent.ps1"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-True ($r.Code -ne 0) "exit code must be non-zero (got $($r.Code))"
    Assert-Match $r.Out (Esc 'Не найден xrrfix_agent.ps1 рядом с setup_agent.ps1') 'error text'
    Assert-PathMissing "$h\agent" 'agent folder created'
}

TC 'AGT-001 setup started from <home>\agent does not copy' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"; $h = New-AgentHome "$sb\home\xrrfix"
    $before = FHash "$h\agent\xrrfix_agent.ps1"
    $r = Invoke-Setup $h "$h\agent" "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Match $r.Out (Esc "Файлы агента уже в $h\agent") 'already-there message'
    Assert-NotMatch $r.Out 'Файлы агента скопированы' 'no copy'
    Assert-Equal $before (FHash "$h\agent\xrrfix_agent.ps1") 'agent unchanged'
}

TC 'AGT-002 -GammaRoot without mods throws and writes no gamma_root.txt' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $bad = "$sb\NotGamma"; New-Item -ItemType Directory $bad | Out-Null; W "$bad\ModOrganizer.exe" 'x' -NoBom
    $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $bad) -NoRun -NoShortcut"
    Assert-True ($r.Code -ne 0) "exit code must be non-zero (got $($r.Code))"
    Assert-Match $r.Out (Esc "В '$bad' нет ModOrganizer.exe и папки mods") 'error text'
    Assert-PathMissing "$h\gamma_root.txt" 'gamma_root.txt written'
}

TC 'AGT-002 saved <home>\gamma_root.txt is offered and confirmed via stdin (no dialog)' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    Write-State "$h\gamma_root.txt" $g
    $r = Invoke-Setup $h $src '-NoRun -NoShortcut' -StdIn "д`r`n" -TimeoutSec 90
    Assert-Match $r.Out (Esc "Найдена папка GAMMA: $g") 'found message'
    Assert-NotMatch $r.Out 'Выберите папку GAMMA' 'dialog must not open'
    Assert-Equal $g (First "$h\gamma_root.txt") 'gamma_root.txt'
}

TC 'AGT-002 %LOCALAPPDATA%\xrrfix\gamma_root.txt is the second source' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $shared = Join-Path $script:Lad 'xrrfix\gamma_root.txt'
    try {
        Write-State $shared $g
        $r = Invoke-Setup $h $src '-NoRun -NoShortcut' -StdIn "y`r`n" -TimeoutSec 90
        Assert-Match $r.Out (Esc "Найдена папка GAMMA: $g") 'found message'
        Assert-Equal $g (First "$h\gamma_root.txt") 'gamma_root.txt'
    } finally { Remove-Item -LiteralPath (Split-Path $shared) -Recurse -Force -ErrorAction SilentlyContinue }
}

TC 'AGT-002 setup inside <gamma>\tools\agent finds the GAMMA root by walking up' {
    $sb = New-Sandbox
    $g = New-Gamma "$sb\Gamma"
    $src = New-SetupSource "$g\tools\agent"
    $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h $src '-NoRun -NoShortcut' -StdIn "д`r`n" -TimeoutSec 90
    Assert-Match $r.Out (Esc "Найдена папка GAMMA: $g") 'found by parent walk'
    Assert-Equal $g (First "$h\gamma_root.txt") 'gamma_root.txt'
}

TC 'AGT-003 setup saves gamma_root.txt and deletes failed_version.txt' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    Write-State "$h\failed_version.txt" 'noroot'
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal $g (First "$h\gamma_root.txt") 'gamma_root.txt = full path'
    Assert-PathMissing "$h\failed_version.txt" 'failed_version.txt removed'
}

TC 'AGT-004 setup from a clone with the right origin records repo_root.txt and removes host_state.txt' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\clone"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    Write-State "$h\host_state.txt" 'conflict abc'
    $r = Invoke-Setup $h "$c\agent" "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Match $r.Out (Esc "Режим: ХОСТ - клон репозитория $c") 'host mode message'
    Assert-Equal $c (First "$h\repo_root.txt") 'repo_root.txt'
    Assert-PathMissing "$h\host_state.txt" 'host_state.txt removed'
}

TC 'AGT-004 setup from a clone with a foreign origin prints the skip line, peer mode, removes repo_root.txt' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\clone" -Origin 'https://example.com/other.git'
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    Write-State "$h\repo_root.txt" "$sb\gone"
    $r = Invoke-Setup $h "$c\agent" "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Match $r.Out (Esc "$c - origin 'https://example.com/other.git' не EduardHavron/xrRazom-GAMMA-fixes, пропуск.") 'skip line'
    Assert-Match $r.Out (Esc 'Режим: обычный - установка релизов с GitHub.') 'peer mode'
    Assert-PathMissing "$h\repo_root.txt" 'repo_root.txt removed'
}

TC 'AGT-004 XRRFIX_REPO=none makes setup choose peer mode' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\clone"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h "$c\agent" "-GammaRoot $(Q $g) -NoRun -NoShortcut" -Env @{ XRRFIX_REPO = 'none' }
    Assert-Match $r.Out (Esc 'Режим: обычный - установка релизов с GitHub.') 'peer mode'
    Assert-PathMissing "$h\repo_root.txt" 'no repo_root.txt'
}

TC 'AGT-004 setup with a clone but no git on PATH warns and chooses peer mode' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\clone"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h "$c\agent" "-GammaRoot $(Q $g) -NoRun -NoShortcut" -Env @{ PATH = (Get-PathWithoutGit) }
    Assert-Match $r.Out (Esc "Найден клон $c, но git не найден в PATH - режим хоста недоступен.") 'warning'
    Assert-Match $r.Out (Esc 'Режим: обычный - установка релизов с GitHub.') 'peer mode'
    Assert-PathMissing "$h\repo_root.txt" 'no repo_root.txt'
}

TC 'AGT-004 AGT-007 setup -DryRun in a clone reports host mode and writes nothing' {
    $sb = New-Sandbox
    $c = New-StubClone "$sb\clone"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $r = Invoke-Setup $h "$c\agent" "-DryRun -GammaRoot $(Q $g)"
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match $r.Out (Esc "Режим: ХОСТ - клон репозитория $c") 'host mode reported'
    Assert-Match $r.Out (Esc "Записал бы '$c' в $h\repo_root.txt") 'would write repo_root.txt'
    Assert-PathMissing $h 'DryRun created <home>'
}

TC 'AGT-007 setup -DryRun (peer) changes nothing and prints the task definition' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    New-Item -ItemType Directory $h | Out-Null
    $task = Get-TaskSnapshot
    $r = Invoke-Setup $h $src "-DryRun -GammaRoot $(Q $g)"
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $h -Force).Count '<home> must stay empty'
    Assert-Match $r.Out 'MultipleInstances=IgnoreNew' 'task settings printed'
    Assert-Match $r.Out (Esc '/SC MINUTE /MO 10') 'schtasks fallback printed'
    Assert-Match $r.Out (Esc 'Режим: обычный') 'peer mode reported'
    Assert-Match $r.Out (Esc "[DryRun] запустил бы: $h\agent\xrrfix_agent.ps1 -Interactive") 'last DryRun line'
    Assert-Equal $task (Get-TaskSnapshot) 'scheduled task changed'
}

TC 'AGT-007 test-mode setup copies files but does not register the scheduled task' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $task = Get-TaskSnapshot
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $g) -NoRun -NoShortcut"
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match $r.Out (Esc "[тест] XRRFIX_HOME=$h") 'test-mode banner'
    Assert-Match $r.Out (Esc 'определение задачи собрано (не зарегистрировано)') 'definition built only'
    Assert-PathExists "$h\agent\xrrfix_agent.ps1" 'files copied'
    Assert-Equal $task (Get-TaskSnapshot) 'scheduled task changed'
}

TC 'AGT-009 setup without -NoRun runs the agent once and installs the release' {
    $sb = New-Sandbox
    $src = New-SetupSource "$sb\src\agent"
    $g = New-Gamma "$sb\Gamma"; $h = "$sb\home\xrrfix"
    $rel = New-Release '2026.10.14-9'
    $r = Invoke-Setup $h $src "-GammaRoot $(Q $g) -NoShortcut" -Env @{ XRRFIX_REPO = 'none' }
    Assert-Match $r.Out (Esc '=== Первая проверка обновлений ===') 'first run started'
    Assert-Match $r.Out (Esc 'Установлено: 2026.10.14-9') 'agent output (-Interactive) visible'
    Assert-Match $r.Out (Esc 'Готово.') 'done line'
    Assert-Match $r.Out (Esc "Журнал: $h\agent.log") 'log path'
    Assert-Equal '2026.10.14-9' (First "$h\installed_version.txt") 'installed_version.txt'
}

function New-FullStateHome([string]$H) {
    New-AgentHome $H | Out-Null
    New-Item -ItemType Directory "$H\dl\pkg_1" -Force | Out-Null; W "$H\dl\pkg_1\x.txt" 'x'
    foreach ($f in 'agent.log', 'failed_version.txt', 'api_etag.txt', 'api_latest.json', 'repo_root.txt', 'mode.txt', 'host_state.txt', 'sync_last.log', 'gamma_root.txt', 'installed_version.txt') { Write-State "$H\$f" $f }
}

TC 'AGT-052 uninstall -RemoveFiles keeps only gamma_root.txt and installed_version.txt, task untouched' {
    $sb = New-Sandbox
    $h = "$sb\xrrfix"; New-FullStateHome $h
    $task = Get-TaskSnapshot
    $r = Invoke-Uninstall $h '-RemoveFiles'
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match $r.Out (Esc "[DryRun] удалил бы задачу '$script:TaskName'") 'test mode: task not touched'
    $left = (@(Get-ChildItem -LiteralPath $h -Force | ForEach-Object { $_.Name } | Sort-Object) -join ',')
    Assert-Equal 'gamma_root.txt,installed_version.txt' $left 'remaining files'
    Assert-Equal $task (Get-TaskSnapshot) 'scheduled task changed'
}

TC 'AGT-052 uninstall -DryRun deletes nothing' {
    $sb = New-Sandbox
    $h = "$sb\xrrfix"; New-FullStateHome $h
    $before = (@(Get-ChildItem -LiteralPath $h -Recurse -Force | ForEach-Object { $_.FullName }) -join ',')
    $r = Invoke-Uninstall $h '-DryRun'
    Assert-Equal 0 $r.Code 'exit code'
    Assert-Match $r.Out (Esc '[DryRun] при удалении файлов') 'plan printed'
    Assert-Equal $before (@(Get-ChildItem -LiteralPath $h -Recurse -Force | ForEach-Object { $_.FullName }) -join ',') 'files changed'
}

TC 'AGT-052 uninstall question: default (Enter) keeps files, "д" deletes them' {
    $sb = New-Sandbox
    $h = "$sb\xrrfix"; New-FullStateHome $h
    $r = Invoke-Uninstall $h '' -StdIn "`r`n"
    Assert-Equal 0 $r.Code 'exit code (keep)'
    Assert-PathExists "$h\agent" 'agent kept on default answer'
    $r = Invoke-Uninstall $h '' -StdIn "д`r`n"
    Assert-Equal 0 $r.Code 'exit code (delete)'
    Assert-PathMissing "$h\agent" 'agent deleted on yes'
    Assert-PathExists "$h\gamma_root.txt" 'gamma_root.txt kept'
}
