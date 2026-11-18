# Отключает автообновление фиксов xrRazom. Установленные моды остаются на месте.
#   -DryRun       только показать, что будет сделано
#   -RemoveFiles  удалить файлы агента без вопроса;  -KeepFiles  не удалять
param([switch]$DryRun, [switch]$RemoveFiles, [switch]$KeepFiles)

$ErrorActionPreference = 'Stop'
$TaskName = 'xrRazom fixes updater'
$Base = Join-Path $env:LOCALAPPDATA 'xrrfix'
if ($env:XRRFIX_HOME) { $Base = $env:XRRFIX_HOME }
$TestMode = [bool]$env:XRRFIX_HOME -and ($Base.TrimEnd('\') -ne (Join-Path $env:LOCALAPPDATA 'xrrfix'))
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Обновить фиксы xrRazom.lnk'

# schtasks.exe reports a missing task on stderr. Under $ErrorActionPreference = 'Stop' Windows PowerShell 5.1 turns
# that into a terminating error (NativeCommandError), so schtasks runs under 'Continue' and only its exit code counts.
function Invoke-Schtasks {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & schtasks.exe @args 2>$null | Out-Null; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
}

Write-Host '=== Отключение автообновления фиксов xrRazom ===' -ForegroundColor Cyan
if ($DryRun -or $TestMode) {
    Write-Host "[DryRun] удалил бы задачу '$TaskName' и ярлык $ShortcutPath" -ForegroundColor Yellow
} else {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; Write-Host 'Задача удалена.' -ForegroundColor Green }
        catch { if ((Invoke-Schtasks /Delete /TN $TaskName /F) -eq 0) { Write-Host 'Задача удалена.' -ForegroundColor Green } }
    } elseif ((Invoke-Schtasks /Query /TN $TaskName) -eq 0) {
        if ((Invoke-Schtasks /Delete /TN $TaskName /F) -eq 0) { Write-Host 'Задача удалена.' -ForegroundColor Green }
    } else {
        Write-Host 'Задачи нет - пропуск.'
    }
    if (Test-Path $ShortcutPath) { Remove-Item $ShortcutPath -Force; Write-Host 'Ярлык удалён.' }
}

$del = $RemoveFiles
if (-not $RemoveFiles -and -not $KeepFiles -and -not $DryRun) {
    $a = (Read-Host "Удалить файлы агента ($Base\agent, журнал, загрузки)? Моды останутся. [д/Н]").Trim().ToLower()
    $del = $a -in 'y', 'yes', 'д', 'да', 'l'
}
$targets = @('agent', 'dl', 'agent.log', 'failed_version.txt', 'api_etag.txt', 'api_latest.json', 'repo_root.txt', 'mode.txt', 'host_state.txt', 'sync_last.log') | ForEach-Object { Join-Path $Base $_ }
if ($DryRun) { Write-Host "[DryRun] при удалении файлов: $($targets -join ', ') (gamma_root.txt и installed_version.txt остаются)" -ForegroundColor Yellow }
elseif ($del) {
    foreach ($p in $targets) { if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Host 'Файлы агента удалены.' -ForegroundColor Green
}
Write-Host 'Готово. Установленные фиксы в MO2 не тронуты.' -ForegroundColor Green
