# xrRazom fixes - фоновый агент обновления (запускается Планировщиком задач каждые 10 минут).
# Проверяет последний релиз на GitHub и, если версия новая, скачивает и ставит его через install.ps1 -NoWait.
#   -Force        переустановить, даже если версия уже стоит
#   -Interactive  печатать ход работы в консоль (ярлык / setup_agent)
#   -PauseAtEnd   ждать Enter в конце (для ярлыка)
# Переопределения для тестов (env):
#   XRRFIX_HOME         папка состояния (по умолчанию %LOCALAPPDATA%\xrrfix)
#   XRRFIX_API          URL releases/latest (по умолчанию GitHub API)
#   XRRFIX_BLOCK_PROCS  имена процессов через запятую, при которых установка откладывается
#                       (по умолчанию ModOrganizer,Anomaly*)
#   XRRFIX_NO_NOTIFY=1  не показывать всплывающие уведомления
#   XRRFIX_REPO         корень клона репозитория без поиска (режим хоста); none = всегда обычный режим
# Режим хоста: если на ПК есть git-клон репозитория (.git, host\publish.ps1, agent\xrrfix_agent.ps1,
# origin = EduardHavron/xrRazom-GAMMA-fixes), вместо скачивания релиза запускается
# host\publish.ps1 -SyncOnly -NoWait -NoPrompt (подтянуть чужие публикации в свой MO2).
# Самообновление: в конце запуска файлы в <home>\agent заменяются новыми из релиза (папка agent\ в zip)
# или из <клон>\agent, если они отличаются (имя и путь xrrfix_agent.ps1 не меняются - задача работает дальше).
param([switch]$Force, [switch]$Interactive, [switch]$PauseAtEnd)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RealBase = Join-Path $env:LOCALAPPDATA 'xrrfix'
$Base = $RealBase
if ($env:XRRFIX_HOME) { $Base = $env:XRRFIX_HOME }
$TestMode = [bool]$env:XRRFIX_HOME -and ($Base.TrimEnd('\') -ne $RealBase.TrimEnd('\'))
$Api = 'https://api.github.com/repos/EduardHavron/xrRazom-GAMMA-fixes/releases/latest'
if ($env:XRRFIX_API) { $Api = $env:XRRFIX_API }
$BlockProcs = @('ModOrganizer', 'Anomaly*')
if ($env:XRRFIX_BLOCK_PROCS) { $BlockProcs = @($env:XRRFIX_BLOCK_PROCS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$AssetName = 'xrRazom_fixes.zip'
$UA = 'xrrfix-agent/1.0 (+https://github.com/EduardHavron/xrRazom-GAMMA-fixes)'
$InstallTimeoutMin = 10

$LogFile = Join-Path $Base 'agent.log'
$VerFile = Join-Path $Base 'installed_version.txt'
$FailFile = Join-Path $Base 'failed_version.txt'     # "<version>" последней неудачной установки (уведомление один раз)
$RootFile = Join-Path $Base 'gamma_root.txt'
$EtagFile = Join-Path $Base 'api_etag.txt'
$CacheFile = Join-Path $Base 'api_latest.json'
$DlDir = Join-Path $Base 'dl'
$AgentDir = Join-Path $Base 'agent'
$RepoFile = Join-Path $Base 'repo_root.txt'      # кэш пути к клону (режим хоста)
$ModeFile = Join-Path $Base 'mode.txt'           # последний режим (лог только при смене)
$HostStateFile = Join-Path $Base 'host_state.txt' # "<вид> <sha origin/main>" последнего уведомления о конфликте/ошибке
$SyncLogFile = Join-Path $Base 'sync_last.log'   # полный вывод последнего publish.ps1 -SyncOnly
$RepoMarker = 'EduardHavron/xrRazom-GAMMA-fixes'
$SyncTimeoutMin = 10
$Utf8Bom = New-Object Text.UTF8Encoding($true)
$script:SelfUpdateSrc = $null   # папка с новыми файлами агента (копируются в конце запуска)
$script:CleanDl = $false
$script:GitExe = $null
$gc = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($gc) { $script:GitExe = $gc.Source }

function Write-Log([string]$msg, [string]$color = '') {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $msg
    try { [IO.File]::AppendAllText($LogFile, $line + "`r`n", $Utf8Bom) } catch { }
    if ($Interactive) { if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg } }
}

function Trim-Log {
    try {
        if (-not (Test-Path $LogFile)) { return }
        $all = [IO.File]::ReadAllLines($LogFile, $Utf8Bom)
        if ($all.Count -gt 600) { [IO.File]::WriteAllLines($LogFile, $all[($all.Count - 500)..($all.Count - 1)], $Utf8Bom) }
    } catch { }
}

function Read-First([string]$path) {
    if (-not (Test-Path $path)) { return '' }
    $l = Get-Content $path -Encoding UTF8 -TotalCount 1
    if ($l) { return ([string]$l).Trim() } else { return '' }
}

function Save-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text + "`r`n", $Utf8Bom) }

function Test-Root($p) { $p -and (Test-Path (Join-Path $p 'ModOrganizer.exe')) -and (Test-Path (Join-Path $p 'mods')) }

function Show-Notify([string]$title, [string]$text, [string]$kind = 'Info') {
    if ($Interactive) { Write-Host "[$title] $text" -ForegroundColor Cyan }
    if ($env:XRRFIX_NO_NOTIFY -eq '1') { if ($TestMode) { Write-Log "[тест] уведомление: $title | $text" }; return }
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $ni = New-Object System.Windows.Forms.NotifyIcon
        if ($kind -eq 'Error') { $ni.Icon = [System.Drawing.SystemIcons]::Warning; $ni.BalloonTipIcon = 'Warning' }
        else { $ni.Icon = [System.Drawing.SystemIcons]::Information; $ni.BalloonTipIcon = 'Info' }
        $ni.Text = 'xrRazom fixes'
        $ni.BalloonTipTitle = $title
        if ($text.Length -gt 250) { $text = $text.Substring(0, 247) + '...' }
        $ni.BalloonTipText = $text
        $ni.Visible = $true
        $ni.ShowBalloonTip(6000)
        $end = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200 }
        $ni.Visible = $false
        $ni.Dispose()
    } catch { Write-Log "уведомление не показано: $($_.Exception.Message)" }
}

function Get-HttpStatus($err) {
    try { $r = $err.Exception.Response; if ($r) { return [int]$r.StatusCode } } catch { }
    return 0
}

# --- latest release (ETag-кэш: ответ 304 не тратит лимит GitHub) ---
function Get-Latest {
    $h = @{ 'User-Agent' = $UA; 'Accept' = 'application/vnd.github+json' }
    $etag = Read-First $EtagFile
    if ($etag -and (Test-Path $CacheFile) -and -not $Force) { $h['If-None-Match'] = $etag }
    try {
        $r = Invoke-WebRequest -Uri $Api -Headers $h -UseBasicParsing -TimeoutSec 30
        $json = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        $rel = $json | ConvertFrom-Json
        try {
            [IO.File]::WriteAllText($CacheFile, $json, (New-Object Text.UTF8Encoding($false)))
            $newTag = $r.Headers['ETag']
            if ($newTag) { Save-Text $EtagFile $newTag } elseif (Test-Path $EtagFile) { Remove-Item $EtagFile -Force }
        } catch { }
        return $rel
    } catch {
        $code = Get-HttpStatus $_
        if ($code -eq 304) { return ([IO.File]::ReadAllText($CacheFile, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
        if ($code -eq 404) { Write-Log 'GitHub: релизов пока нет (404).'; return $null }
        if ($code -eq 403 -or $code -eq 429) { Write-Log "GitHub: лимит запросов ($code), попробую позже."; return $null }
        Write-Log "Нет связи с GitHub ($code): $($_.Exception.Message)"
        return $null
    }
}

function Get-ModNames([string]$packTxt) {
    if (Test-Path $packTxt) {
        $n = @(Get-Content $packTxt -Encoding UTF8 | Where-Object { $_ -like '[[]mod[]] *' } | ForEach-Object { $_.Substring(6).Trim() })
        if ($n.Count) { return $n }
    }
    return @()
}

# Запуск .ps1 дочерним процессом PowerShell (вывод в UTF-8, с таймаутом).
# Возвращает объект { Code; Lines } (Code 124 = таймаут, процесс остановлен вместе с дочерними).
function Invoke-PsChild([string]$ps1, [string]$argStr, [string]$dir, [int]$timeoutMin) {
    $q = $ps1.Replace("'", "''")
    $cmd = "[Console]::OutputEncoding = [Text.Encoding]::UTF8; `$ProgressPreference = 'SilentlyContinue'; `$global:LASTEXITCODE = 0; " +
           "try { & '$q' $argStr *>&1 | ForEach-Object { ''+`$_ }; exit `$LASTEXITCODE } catch { Write-Output ('ОШИБКА: ' + `$_.Exception.Message); Write-Output `$_.ScriptStackTrace; exit 1 }"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $PSHOME 'powershell.exe'
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $enc"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'   # git не должен ждать ввода в фоне
    # тест-режим: если XRRFIX_HOME = <X>\xrrfix, дочерний скрипт тоже будет читать <X>\xrrfix\gamma_root.txt
    if ($TestMode -and ((Split-Path $Base -Leaf) -eq 'xrrfix')) { $psi.EnvironmentVariables['LOCALAPPDATA'] = (Split-Path $Base -Parent) }
    $p = [System.Diagnostics.Process]::Start($psi)
    $outT = $p.StandardOutput.ReadToEndAsync()
    $errT = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutMin * 60 * 1000)) {
        try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
        try { if (-not $p.HasExited) { $p.Kill() } } catch { }
        Write-Log "$(Split-Path $ps1 -Leaf) не завершился за $timeoutMin мин - процесс остановлен."
        return [pscustomobject]@{ Code = 124; Lines = @() }
    }
    $p.WaitForExit()
    $errTxt = $errT.Result
    if ($errTxt -match '^#< CLIXML') {
        # сериализованные потоки PowerShell: оставить только текст ошибок
        $errTxt = (([regex]::Matches($errTxt, '<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value }) -join '') -replace '_x000D__x000A_', "`n" -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
    }
    $lines = @(foreach ($t in @($outT.Result, $errTxt)) { foreach ($l in ($t -split "`r?`n")) { if ($l.Trim()) { $l.TrimEnd() } } })
    return [pscustomobject]@{ Code = $p.ExitCode; Lines = $lines }
}

# Запуск install.ps1 -NoWait, вывод - в лог. Возвращает код выхода.
function Invoke-Installer([string]$dir) {
    $r = Invoke-PsChild (Join-Path $dir 'install.ps1') '-NoWait' $dir $InstallTimeoutMin
    foreach ($l in $r.Lines) { Write-Log "  | $l" }
    return $r.Code
}

# --- git / режим хоста ---
function Invoke-Git([string[]]$argv) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:GitExe
    $psi.Arguments = (@($argv | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $p = [System.Diagnostics.Process]::Start($psi)
    $outT = $p.StandardOutput.ReadToEndAsync()
    $errT = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = 124; Out = ''; Err = 'timeout' } }
    $p.WaitForExit()
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $outT.Result.Trim(); Err = $errT.Result.Trim() }
}

# Быстрая проверка по файлам (без git)
function Test-RepoFiles([string]$p) {
    if (-not $p) { return $false }
    try {
        return ((Test-Path -LiteralPath (Join-Path $p '.git')) -and
                (Test-Path -LiteralPath (Join-Path $p 'host\publish.ps1') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $p 'agent\xrrfix_agent.ps1') -PathType Leaf))
    } catch { return $false }
}

function Test-RepoOrigin([string]$p) {
    $r = Invoke-Git @('-C', $p.TrimEnd('\'), 'remote', 'get-url', 'origin')
    return ($r.Code -eq 0 -and $r.Out -like "*$RepoMarker*")
}

# Возвращает путь к клону или $null. $script:RepoNote - пояснение, если клон есть, но использовать нельзя.
function Find-Repo {
    $script:RepoNote = ''
    $forced = [string]$env:XRRFIX_REPO
    if ($forced -eq 'none') { return $null }
    $cands = New-Object System.Collections.Generic.List[string]
    if ($forced) { $cands.Add($forced) }
    else {
        $cached = Read-First $RepoFile
        if ($cached) { $cands.Add($cached) }
        if ($PSScriptRoot) { $cands.Add((Split-Path $PSScriptRoot -Parent)) }
        $root = Read-First $RootFile
        if ($root -and (Test-Path -LiteralPath $root)) {
            foreach ($d in @($root, (Split-Path $root -Parent))) {
                if ($d -and (Test-Path -LiteralPath $d)) {
                    Get-ChildItem -LiteralPath $d -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add($_.FullName) }
                }
            }
        }
    }
    $seen = @{}
    $fs = @(foreach ($c in $cands) {
        $k = $c.TrimEnd('\').ToLowerInvariant()
        if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; if (Test-RepoFiles $c) { $c.TrimEnd('\') } }
    })
    if (-not $fs.Count) {
        if ($forced) { $script:RepoNote = "XRRFIX_REPO='$forced' - не клон репозитория." }
        return $null
    }
    if (-not $script:GitExe) { $script:RepoNote = "найден клон $($fs[0]), но git не найден в PATH."; return $null }
    foreach ($c in $fs) {
        if (Test-RepoOrigin $c) {
            $full = (Resolve-Path -LiteralPath $c).Path.TrimEnd('\')
            if (-not $forced -and (Read-First $RepoFile) -ne $full) { try { Save-Text $RepoFile $full } catch { } }
            return $full
        }
    }
    $script:RepoNote = "у $($fs[0]) origin не $RepoMarker."
    return $null
}

# Записать режим в лог только при его смене
function Note-Mode([string]$key, [string]$msg) {
    if ((Read-First $ModeFile) -ne $key) { try { Save-Text $ModeFile $key } catch { }; Write-Log $msg 'Cyan' }
    elseif ($Interactive) { Write-Host $msg -ForegroundColor Cyan }
}

# Уведомление один раз на ключ (например "conflict <sha>")
function Notify-Once([string]$key, [string]$title, [string]$text) {
    $prev = Read-First $HostStateFile
    try { Save-Text $HostStateFile $key } catch { }
    if ($prev -ne $key -or $Interactive) { Show-Notify $title $text 'Error' }
}

# Режим хоста: publish.ps1 -SyncOnly -NoWait -NoPrompt
function Invoke-HostSync([string]$repo) {
    $pub = Join-Path $repo 'host\publish.ps1'
    $script:SelfUpdateSrc = Join-Path $repo 'agent'   # в любом случае: после синхронизации обновить агент из клона
    if ($Interactive) { Write-Host 'Синхронизация: publish.ps1 -SyncOnly ...' }
    $r = Invoke-PsChild $pub '-SyncOnly -NoWait -NoPrompt' $repo $SyncTimeoutMin
    try { [IO.File]::WriteAllLines($SyncLogFile, [string[]](@(('{0:yyyy-MM-dd HH:mm:ss} код {1}' -f (Get-Date), $r.Code)) + $r.Lines), $Utf8Bom) } catch { }
    $res = $r.Lines | Where-Object { $_ -match '^\s*XRRFIX_SYNC_RESULT:' } | Select-Object -Last 1
    $n = 0; $mods = ''
    if ($res -and $res -match 'installed=(\d+)') { $n = [int]$Matches[1] }
    if ($res -and $res -match 'mods=(.*)$') { $mods = $Matches[1].Trim().Trim(',') -replace '\s*,\s*', ', ' }
    $quiet = ($r.Code -eq 0 -and $n -eq 0)
    if (-not $quiet) { foreach ($l in $r.Lines) { Write-Log "  | $l" } }
    elseif ($Interactive) { foreach ($l in $r.Lines) { Write-Host "  | $l" -ForegroundColor DarkGray } }

    if ($r.Code -eq 0) {
        if (Test-Path $HostStateFile) { Remove-Item $HostStateFile -Force -ErrorAction SilentlyContinue }
        if ($n -gt 0) {
            Write-Log "Синхронизация: установлено $n ($mods)." 'Green'
            if ($mods) { $txt = "Фиксы xrRazom обновлены: $mods" } else { $txt = "Фиксы xrRazom обновлены ($n)" }
            Show-Notify 'xrRazom fixes' $txt
        } elseif ($Interactive) { Write-Host 'Синхронизация: всё актуально.' -ForegroundColor Green }
        return 0
    }
    if ($r.Code -eq 2) { Write-Log 'Синхронизация отложена (запущен MO2/игра или publish уже работает).' 'Yellow'; return 0 }

    $sha = ''
    $g = Invoke-Git @('-C', $repo, 'rev-parse', '--verify', '-q', 'origin/main')
    if ($g.Code -eq 0) { $sha = $g.Out }
    if (-not $sha) { $sha = 'unknown' }
    if ($r.Code -eq 3) {
        $cl = $r.Lines | Where-Object { $_ -match '^\s*XRRFIX_SYNC_CONFLICT:' } | Select-Object -Last 1
        $cm = ''
        if ($cl -and $cl -match 'mods=(.*)$') { $cm = $Matches[1].Trim().Trim(',') -replace '\s*,\s*', ', ' }
        Write-Log "Синхронизация: конфликт ($sha) $cm" 'Red'
        if ($cm) { $txt = "Конфликт фиксов: $cm, запустите publish.bat" }
        else {
            $pool = @($r.Lines | Where-Object { $_ -notmatch '^\s*XRRFIX_' })
            $hit = @($pool | Where-Object { $_ -match 'конфликт|conflict' })
            if ($hit.Count) { $pool = $hit }
            $head = @($pool | Select-Object -First 2 | ForEach-Object { $_.Trim() }) -join ' / '
            $txt = "Конфликт фиксов, запустите publish.bat. $head"
        }
        Notify-Once "conflict $sha" 'xrRazom fixes: конфликт' $txt
        return 3
    }
    Write-Log "Ошибка синхронизации (код $($r.Code), origin/main $sha). Полный вывод: $SyncLogFile" 'Red'
    Notify-Once "error $sha" 'xrRazom fixes: ошибка синхронизации' "publish.ps1 -SyncOnly завершился с кодом $($r.Code). Подробности: $LogFile"
    return 1
}

# --- самообновление: копировать отличающиеся файлы из $src в <home>\agent (в конце запуска) ---
function Update-Agent([string]$src) {
    if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src 'xrrfix_agent.ps1'))) { return }
    if (-not (Test-Path -LiteralPath $AgentDir)) { return }   # агент не установлен через setup_agent - нечего обновлять
    $s = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
    $d = (Resolve-Path -LiteralPath $AgentDir).Path.TrimEnd('\')
    if ($s -eq $d) { return }
    $changed = @(Get-ChildItem -LiteralPath $s -File | Where-Object { $_.Extension -in '.ps1', '.bat', '.txt' } | Where-Object {
        $t = Join-Path $d $_.Name
        -not (Test-Path -LiteralPath $t) -or (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash
    })
    if (-not $changed.Count) { return }
    # новые .ps1 должны хотя бы разбираться парсером - иначе не трогаем рабочую копию
    foreach ($f in $changed | Where-Object { $_.Extension -eq '.ps1' }) {
        $tok = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$errs)
        if ($errs -and $errs.Count) { Write-Log "Агент НЕ обновлён: ошибка синтаксиса в $($f.Name): $($errs[0].Message)" 'Red'; return }
    }
    foreach ($f in $changed) {
        $t = Join-Path $d $f.Name
        [IO.File]::Copy($f.FullName, $t, $true)
        try { Unblock-File -LiteralPath $t -ErrorAction SilentlyContinue } catch { }
    }
    Write-Log "Агент обновлён из ${s}: $(($changed | ForEach-Object { $_.Name }) -join ', ')" 'Green'
}

function Set-Failed([string]$ver, [string]$title, [string]$text) {
    $prev = Read-First $FailFile
    Save-Text $FailFile $ver
    if ($prev -ne $ver -or $Interactive) { Show-Notify $title $text 'Error' }
}

function Main {
    New-Item -ItemType Directory $Base -Force | Out-Null
    if ($TestMode) { Write-Log "[тест] XRRFIX_HOME=$Base API=$Api REPO=$env:XRRFIX_REPO" }

    $repo = Find-Repo
    if ($repo) {
        Note-Mode "host|$repo" "Режим хоста: клон репозитория $repo (синхронизация через host\publish.ps1 -SyncOnly)."
        return (Invoke-HostSync $repo)
    }
    if ($script:RepoNote) { Note-Mode "peer|$($script:RepoNote)" "Обычный режим (релизы GitHub): $($script:RepoNote)" }
    else { Note-Mode 'peer' 'Обычный режим: установка релизов с GitHub.' }

    $rel = Get-Latest
    if (-not $rel) { return 0 }
    $ver = ([string]$rel.tag_name) -replace '^[vV]', ''
    if (-not $ver) { Write-Log 'В ответе GitHub нет tag_name.'; return 0 }
    $cur = Read-First $VerFile
    if ($ver -eq $cur -and -not $Force) {
        if ($Interactive) { Write-Host "Установлена последняя версия: $cur" -ForegroundColor Green }
        return 0
    }
    # неудачная версия: повтор не чаще раза в час (без лишних скачиваний)
    if (-not $Force -and (Read-First $FailFile) -eq $ver -and ((Get-Date) - (Get-Item $FailFile).LastWriteTime).TotalMinutes -lt 60) {
        if ($Interactive) { Write-Host "Версия $ver недавно не установилась, повтор позже (или запустите с -Force)." -ForegroundColor Yellow }
        return 0
    }

    foreach ($pn in $BlockProcs) {
        $pr = Get-Process -Name $pn -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pr) { Write-Log "Обновление $ver отложено: запущен $($pr.ProcessName)." 'Yellow'; return 0 }
    }

    $root = Read-First $RootFile
    if (-not (Test-Root $root)) {
        Write-Log "Папка GAMMA не задана или неверна ('$root'). Запустите setup_agent.bat ещё раз." 'Red'
        Set-Failed 'noroot' 'xrRazom fixes: нужна настройка' 'Не найдена папка GAMMA. Запустите setup_agent.bat ещё раз.'
        return 1
    }

    $asset = @($rel.assets | Where-Object { $_.name -eq $AssetName }) | Select-Object -First 1
    if (-not $asset) { Write-Log "В релизе $ver нет файла $AssetName - пропуск."; return 0 }

    Write-Log "Обновление: $ver (установлена: $(if ($cur) { $cur } else { 'нет' })). Скачиваю..."
    New-Item -ItemType Directory $DlDir -Force | Out-Null
    Get-ChildItem $DlDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $zip = Join-Path $DlDir ("xrRazom_fixes_$ver.zip")
    $ex = Join-Path $DlDir ("pkg_$ver")
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ 'User-Agent' = $UA } -OutFile "$zip.part" -UseBasicParsing -TimeoutSec 300
        Move-Item "$zip.part" $zip -Force
    } catch {
        Write-Log "Не удалось скачать $($asset.browser_download_url): $($_.Exception.Message)"
        return 0   # сеть - попробуем на следующем запуске
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)
    } catch {
        Write-Log "Архив повреждён: $($_.Exception.Message)" 'Red'
        Set-Failed $ver 'xrRazom fixes: ошибка' "Архив версии $ver повреждён. Подробности: $LogFile"
        return 1
    }
    $pkg = $ex
    if (-not (Test-Path (Join-Path $pkg 'install.ps1'))) {
        $sub = @(Get-ChildItem $ex -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'install.ps1') })
        if ($sub.Count -eq 1) { $pkg = $sub[0].FullName }
        else {
            Write-Log "В архиве нет install.ps1." 'Red'
            Set-Failed $ver 'xrRazom fixes: ошибка' "В архиве версии $ver нет install.ps1."
            return 1
        }
    }
    $packTxt = Join-Path $pkg 'pack.txt'
    $pv = ''
    if (Test-Path $packTxt) { $pv = ((Get-Content $packTxt -Encoding UTF8 | Where-Object { $_ -like 'version=*' } | Select-Object -First 1) -replace '^version=', '').Trim() }
    if ($pv -and $pv -ne $ver) { Write-Log "Внимание: pack.txt version=$pv, тег $ver." }

    Write-Log "Устанавливаю $ver..."
    $code = Invoke-Installer $pkg
    if ($code -eq 0) {
        Save-Text $VerFile $ver
        if (Test-Path $FailFile) { Remove-Item $FailFile -Force }
        Write-Log "Установлено: $ver" 'Green'
        $mods = @(Get-ModNames $packTxt)
        $txt = "Фиксы xrRazom обновлены до $ver"
        if ($mods.Count) { $txt += "`n" + ($mods -join ', ') }
        Show-Notify 'xrRazom fixes' $txt
        # новая версия агента из релиза (agent\ в корне zip) - копируется в конце запуска, затем чистится dl\
        if (Test-Path (Join-Path $pkg 'agent\xrrfix_agent.ps1')) { $script:SelfUpdateSrc = Join-Path $pkg 'agent' }
        $script:CleanDl = $true
        return 0
    }
    if ($code -eq 2) { Write-Log "Обновление $ver отложено: запущен Mod Organizer." 'Yellow'; return 0 }
    Write-Log "Ошибка установки $ver (код $code)." 'Red'
    Set-Failed $ver 'xrRazom fixes: ошибка обновления' "Не удалось установить $ver. Подробности: $LogFile"
    return 1
}

# --- single instance ---
$mutexName = 'Local\xrrfix_agent_' + ($Base.ToLowerInvariant().TrimEnd('\') -replace '[^a-z0-9]', '_')
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$have = $false
try { $have = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $have = $true }
if (-not $have) {
    if ($Interactive) { Write-Host 'Агент уже работает, попробуйте через минуту.' -ForegroundColor Yellow; if ($PauseAtEnd) { [void](Read-Host 'Enter - закрыть') } }
    exit 0
}
$rc = 0
try {
    $rc = [int](@(Main) | Select-Object -Last 1)
} catch {
    $rc = 1
    Write-Log "Непредвиденная ошибка: $($_.Exception.Message) $($_.ScriptStackTrace)" 'Red'
} finally {
    # самообновление - в самом конце (скрипт уже прочитан PowerShell целиком, замена файла безопасна)
    if ($script:SelfUpdateSrc) { try { Update-Agent $script:SelfUpdateSrc } catch { Write-Log "Самообновление не удалось: $($_.Exception.Message)" 'Red' } }
    if ($script:CleanDl) { Get-ChildItem $DlDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    Trim-Log
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
if ($Interactive) { Write-Host "Журнал: $LogFile" -ForegroundColor DarkGray }
if ($PauseAtEnd) { [void](Read-Host 'Enter - закрыть') }
exit $rc
