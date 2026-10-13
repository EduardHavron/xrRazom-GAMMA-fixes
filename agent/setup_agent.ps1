# Однократная настройка автообновления фиксов xrRazom (запускать через setup_agent.bat).
#   -DryRun         ничего не менять, только показать, что будет сделано
#   -GammaRoot <p>  папка GAMMA без вопросов
#   -NoRun          не запускать первую проверку сразу
#   -Shortcut / -NoShortcut   создать ярлык на рабочем столе без вопроса / не создавать
#   -PlainPowerShell  задача запускает powershell.exe напрямую (без conhost --headless;
#                     тогда раз в 10 минут может мелькать окно консоли)
# Если задана переменная XRRFIX_HOME (тест), задача в Планировщике НЕ регистрируется.
# Режим хоста: если setup запущен из git-клона репозитория (или клон лежит в папке GAMMA / рядом с ней),
# путь к клону сохраняется в repo_root.txt и агент синхронизирует через host\publish.ps1 -SyncOnly.
# XRRFIX_REPO=<путь> - задать клон явно; XRRFIX_REPO=none - всегда обычный режим.
param([switch]$DryRun, [string]$GammaRoot, [switch]$NoRun, [switch]$Shortcut, [switch]$NoShortcut, [switch]$PlainPowerShell)

$ErrorActionPreference = 'Stop'
$TaskName = 'xrRazom fixes updater'
$RealBase = Join-Path $env:LOCALAPPDATA 'xrrfix'
$Base = $RealBase
if ($env:XRRFIX_HOME) { $Base = $env:XRRFIX_HOME }
$TestMode = [bool]$env:XRRFIX_HOME -and ($Base.TrimEnd('\') -ne $RealBase.TrimEnd('\'))
$AgentDir = Join-Path $Base 'agent'
$AgentPs1 = Join-Path $AgentDir 'xrrfix_agent.ps1'
$RootFile = Join-Path $Base 'gamma_root.txt'
$RepoFile = Join-Path $Base 'repo_root.txt'
$RepoMarker = 'EduardHavron/xrRazom-GAMMA-fixes'
$Src = $PSScriptRoot
$Files = 'xrrfix_agent.ps1', 'setup_agent.ps1', 'setup_agent.bat', 'uninstall_agent.ps1', 'uninstall_agent.bat', 'README.txt'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Обновить фиксы xrRazom.lnk'
$PsExe = Join-Path $PSHOME 'powershell.exe'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ask-YesNo([string]$q, [bool]$def) {
    $s = if ($def) { '[Д/н]' } else { '[д/Н]' }
    $a = (Read-Host "$q $s").Trim().ToLower()
    if (-not $a) { return $def }
    return ($a -in 'y', 'yes', 'д', 'да', 'l')
}
function Test-Root($p) { $p -and (Test-Path (Join-Path $p 'ModOrganizer.exe')) -and (Test-Path (Join-Path $p 'mods')) }

function Find-Root {
    foreach ($f in @($RootFile, (Join-Path $RealBase 'gamma_root.txt')) | Select-Object -Unique) {
        if (Test-Path $f) {
            $p = ([string](Get-Content $f -Encoding UTF8 -TotalCount 1)).Trim()
            if (Test-Root $p) { return $p }
        }
    }
    $p = $Src
    while ($p) { if (Test-Root $p) { return $p }; $p = Split-Path $p -Parent }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
        foreach ($s in 'GAMMA', 'G.A.M.M.A', 'Gamma', 'Games\GAMMA', 'Games\Gamma', 'Games\G.A.M.M.A', 'Stalker\GAMMA') {
            $c = Join-Path $d $s
            if (Test-Root $c) { return $c }
        }
    }
    return $null
}

function Pick-Root {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Выберите папку GAMMA (где лежит ModOrganizer.exe)'
    while ($dlg.ShowDialog() -eq 'OK') {
        if (Test-Root $dlg.SelectedPath) { return $dlg.SelectedPath }
        [System.Windows.Forms.MessageBox]::Show('В этой папке нет ModOrganizer.exe и папки mods.') | Out-Null
    }
    return $null
}

function Test-RepoFiles([string]$p) {
    if (-not $p) { return $false }
    try {
        return ((Test-Path -LiteralPath (Join-Path $p '.git')) -and
                (Test-Path -LiteralPath (Join-Path $p 'host\publish.ps1') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $p 'agent\xrrfix_agent.ps1') -PathType Leaf))
    } catch { return $false }
}

function Get-OriginUrl([string]$git, [string]$p) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $git
    $psi.Arguments = "-C `"$($p.TrimEnd('\'))`" remote get-url origin"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $pr = [System.Diagnostics.Process]::Start($psi)
    $o = $pr.StandardOutput.ReadToEndAsync(); $e = $pr.StandardError.ReadToEndAsync()
    if (-not $pr.WaitForExit(30000)) { try { $pr.Kill() } catch { }; return '' }
    $pr.WaitForExit()
    if ($pr.ExitCode -ne 0) { return '' }
    return $o.Result.Trim()
}

# Поиск клона репозитория: XRRFIX_REPO, папка над setup_agent, repo_root.txt, папки в GAMMA и рядом с ней.
function Find-Repo([string]$root) {
    $forced = [string]$env:XRRFIX_REPO
    if ($forced -eq 'none') { return $null }
    $cands = New-Object System.Collections.Generic.List[string]
    if ($forced) { $cands.Add($forced) }
    else {
        $cands.Add((Split-Path $Src -Parent))
        if (Test-Path $RepoFile) { $c = ([string](Get-Content $RepoFile -Encoding UTF8 -TotalCount 1)).Trim(); if ($c) { $cands.Add($c) } }
        if ($root) {
            foreach ($d in @($root, (Split-Path $root -Parent))) {
                if ($d -and (Test-Path -LiteralPath $d)) { Get-ChildItem -LiteralPath $d -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add($_.FullName) } }
            }
        }
    }
    $fs = @($cands | Where-Object { Test-RepoFiles $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    if (-not $fs.Count) { if ($forced) { Say "XRRFIX_REPO='$forced' - это не клон репозитория." 'Yellow' }; return $null }
    $gc = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gc) { Say "Найден клон $($fs[0]), но git не найден в PATH - режим хоста недоступен." 'Yellow'; return $null }
    foreach ($c in $fs) {
        $u = Get-OriginUrl $gc.Source $c
        if ($u -like "*$RepoMarker*") { return (Resolve-Path -LiteralPath $c).Path.TrimEnd('\') }
        Say "  $c - origin '$u' не $RepoMarker, пропуск." 'DarkGray'
    }
    return $null
}

Say '=== Автообновление фиксов xrRazom: настройка ===' 'Cyan'
if ($DryRun) { Say '[DryRun] ничего не будет изменено' 'Yellow' }
if ($TestMode) { Say "[тест] XRRFIX_HOME=$Base - задача в Планировщике регистрироваться не будет" 'Yellow' }

# 1. файлы агента
foreach ($f in $Files) { if (-not (Test-Path (Join-Path $Src $f))) { if ($f -eq 'xrrfix_agent.ps1') { throw "Не найден $f рядом с setup_agent.ps1" } } }
$same = (Resolve-Path $Src).Path.TrimEnd('\') -eq $AgentDir.TrimEnd('\')
if ($same) { Say "Файлы агента уже в $AgentDir" }
elseif ($DryRun) { Say "Скопировал бы файлы агента в $AgentDir" }
else {
    New-Item -ItemType Directory $AgentDir -Force | Out-Null
    foreach ($f in $Files) {
        $s = Join-Path $Src $f
        if (Test-Path $s) { Copy-Item $s (Join-Path $AgentDir $f) -Force }
    }
    Get-ChildItem $AgentDir -File | Unblock-File -ErrorAction SilentlyContinue
    Say "Файлы агента скопированы в $AgentDir"
}

# 2. папка GAMMA
$root = $null
if ($GammaRoot) {
    if (-not (Test-Root $GammaRoot)) { throw "В '$GammaRoot' нет ModOrganizer.exe и папки mods" }
    $root = (Resolve-Path $GammaRoot).Path
} else {
    $root = Find-Root
    if ($root) {
        Say "Найдена папка GAMMA: $root" 'Green'
        if (-not (Ask-YesNo 'Это она?' $true)) { $root = $null }
    }
    if (-not $root) {
        Say 'Выберите папку GAMMA в открывшемся окне...'
        $root = Pick-Root
    }
    if (-not $root) { throw 'Папка GAMMA не выбрана - настройка прервана.' }
}
if ($DryRun) { Say "Записал бы '$root' в $RootFile" }
else {
    New-Item -ItemType Directory $Base -Force | Out-Null
    Set-Content $RootFile $root -Encoding UTF8
    Remove-Item (Join-Path $Base 'failed_version.txt') -Force -ErrorAction SilentlyContinue   # новая попытка сразу
    Say "GAMMA: $root (сохранено в $RootFile)"
}

# 2b. режим: хост (есть клон репозитория) или обычный
$repo = Find-Repo $root
if ($repo) {
    Say "Режим: ХОСТ - клон репозитория $repo" 'Green'
    Say '  агент будет запускать host\publish.ps1 -SyncOnly (подтягивать чужие публикации в ваш MO2)'
    Say '  и обновлять себя из папки agent\ клона.'
    if ($DryRun) { Say "Записал бы '$repo' в $RepoFile" }
    else {
        New-Item -ItemType Directory $Base -Force | Out-Null
        Set-Content $RepoFile $repo -Encoding UTF8
        Remove-Item (Join-Path $Base 'host_state.txt') -Force -ErrorAction SilentlyContinue
    }
} else {
    Say 'Режим: обычный - установка релизов с GitHub.' 'Green'
    if (Test-Path $RepoFile) {
        if ($DryRun) { Say "Удалил бы устаревший $RepoFile" }
        else { Remove-Item $RepoFile -Force }
    }
}

# 3. задача Планировщика
$psArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$AgentPs1`""
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$headless = (-not $PlainPowerShell) -and ([Environment]::OSVersion.Version.Build -ge 19041) -and (Test-Path $conhost)
if ($headless) { $exe = $conhost; $exeArgs = "--headless `"$PsExe`" $psArgs" } else { $exe = $PsExe; $exeArgs = $psArgs }
$user = "$env:USERDOMAIN\$env:USERNAME"

Say ''
Say "Задача '$TaskName' (пользователь $user, без прав администратора):"
Say "  команда:  $exe $exeArgs"
Say '  запуск:   при входе в Windows (+1 мин) и каждые 10 минут'
Say '  параметры: не запускать второй экземпляр, работать от батареи, лимит 15 мин'

$registered = $false
if ($DryRun -or $TestMode) {
    # собрать определение без регистрации - проверка, что параметры корректны
    try {
        $a = New-ScheduledTaskAction -Execute $exe -Argument $exeArgs
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $user; $t1.Delay = 'PT1M'
        $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
        $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $st = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        $task = New-ScheduledTask -Action $a -Trigger @($t1, $t2) -Principal $pr -Settings $st -Description 'Автообновление фиксов xrRazom для GAMMA'
        Say '[DryRun] определение задачи собрано (не зарегистрировано):' 'Yellow'
        Say ("  триггер 1: {0}, задержка {1}" -f $task.Triggers[0].CimClass.CimClassName, $task.Triggers[0].Delay)
        Say ("  триггер 2: {0}, интервал {1}, длительность '{2}' (пусто = бесконечно)" -f $task.Triggers[1].CimClass.CimClassName, $task.Triggers[1].Repetition.Interval, $task.Triggers[1].Repetition.Duration)
        Say ("  principal: {0} {1} {2}; MultipleInstances={3}; ExecutionTimeLimit={4}" -f $task.Principal.UserId, $task.Principal.LogonType, $task.Principal.RunLevel, $task.Settings.MultipleInstances, $task.Settings.ExecutionTimeLimit)
    } catch { Say "[DryRun] ошибка сборки задачи: $($_.Exception.Message)" 'Red' }
    if ($headless) { $tr = "conhost.exe --headless powershell.exe $psArgs" } else { $tr = "powershell.exe $psArgs" }
    Say "[DryRun] запасной вариант: schtasks /Create /TN `"$TaskName`" /SC MINUTE /MO 10 /IT /F /TR `"$($tr.Replace('"', '\"'))`""
} else {
    try {
        $a = New-ScheduledTaskAction -Execute $exe -Argument $exeArgs
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $user; $t1.Delay = 'PT1M'
        $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
        $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $st = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
        Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger @($t1, $t2) -Principal $pr -Settings $st -Description 'Автообновление фиксов xrRazom для GAMMA' -Force | Out-Null
        $registered = $true
        Say 'Задача зарегистрирована.' 'Green'
    } catch {
        Say "Register-ScheduledTask не сработал: $($_.Exception.Message)" 'Yellow'
        Say 'Пробую schtasks.exe (только запуск каждые 10 минут, без отдельного запуска при входе -' 'Yellow'
        Say 'это не страшно: первая проверка всё равно будет в течение 10 минут после входа).' 'Yellow'
        # короткие имена exe: у /TR лимит 261 символ
        if ($headless) { $tr = "conhost.exe --headless powershell.exe $psArgs" } else { $tr = "powershell.exe $psArgs" }
        $argLine = "/Create /TN `"$TaskName`" /SC MINUTE /MO 10 /IT /F /TR `"$($tr.Replace('"', '\"'))`""
        $sp = Start-Process schtasks.exe -ArgumentList $argLine -Wait -PassThru -NoNewWindow
        if ($sp.ExitCode -eq 0) { $registered = $true; Say 'Задача создана через schtasks.' 'Green' }
        else { Say 'Не удалось создать задачу. Обновляйте вручную ярлыком "Обновить фиксы xrRazom" или напишите хосту.' 'Red' }
    }
}

# 4. ярлык
$mk = $false
if ($Shortcut) { $mk = $true } elseif (-not $NoShortcut -and -not $DryRun) { $mk = Ask-YesNo 'Создать на рабочем столе ярлык "Обновить фиксы xrRazom"?' $true }
$scArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$AgentPs1`" -Force -Interactive -PauseAtEnd"
if ($DryRun) { Say "[DryRun] ярлык: $ShortcutPath -> $PsExe $scArgs" }
elseif ($mk) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($ShortcutPath)
    $lnk.TargetPath = $PsExe
    $lnk.Arguments = $scArgs
    $lnk.WorkingDirectory = $AgentDir
    $lnk.Description = 'Скачать и переустановить фиксы xrRazom'
    $lnk.Save()
    Say "Ярлык создан: $ShortcutPath" 'Green'
}

# 5. первая установка
if ($DryRun) { Say "[DryRun] запустил бы: $AgentPs1 -Interactive"; exit 0 }
if (-not $NoRun) {
    Say ''
    Say '=== Первая проверка обновлений ===' 'Cyan'
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgentPs1 -Interactive
}
Say ''
Say 'Готово. Дальше фиксы обновляются сами (каждые 10 минут, когда закрыты MO2 и игра).' 'Green'
Say "Журнал: $(Join-Path $Base 'agent.log')"
