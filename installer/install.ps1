# Ставит фиксы xrRazom из этого пакета в GAMMA (MO2).
# Меняется только секция-разделитель пакета (по умолчанию "xrRazom Sync") в активном профиле:
# моды вне секции не трогаются, кроме случая, когда мод из пакета включён где-то ещё.
# Запускать через install.bat из распакованного архива.
# -GammaRoot <папка>  без поиска GAMMA (сохранённый путь не меняется); -Profile <имя>  вместо активного профиля.
# XRRFIX_BLOCK_PROCS (env): процессы через запятую, при которых установка ждёт/откладывается (по умолчанию ModOrganizer).
param(
    [switch]$NoWait,
    [string]$GammaRoot = '',
    [Alias('Profile')][string]$ProfileName = ''
)
$ErrorActionPreference = 'Stop'
$pack = $PSScriptRoot
$saved = Join-Path $env:LOCALAPPDATA 'xrrfix\gamma_root.txt'
$MARKER = 'xrrfix_pack.txt'
$LEGACY = @('zz xrRazom Fixes')   # старый общий мод: выключается, если его нет в пакете
$BlockProcs = @('ModOrganizer')
if ($env:XRRFIX_BLOCK_PROCS) { $BlockProcs = @($env:XRRFIX_BLOCK_PROCS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
function Test-Blocking { foreach ($n in $BlockProcs) { if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true } }; return $false }

function Test-Root($p) { $p -and (Test-Path (Join-Path $p 'ModOrganizer.exe')) -and (Test-Path (Join-Path $p 'mods')) }

function Find-Root {
    if (Test-Path $saved) {
        $p = (Get-Content $saved -Encoding UTF8 | Select-Object -First 1).Trim()
        if (Test-Root $p) { return $p }
    }
    $p = $pack
    while ($p) { if (Test-Root $p) { return $p }; $p = Split-Path $p -Parent }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
        foreach ($s in 'GAMMA', 'G.A.M.M.A', 'Gamma', 'Games\GAMMA', 'Games\Gamma', 'Games\G.A.M.M.A', 'Stalker\GAMMA') {
            $c = Join-Path $d $s
            if (Test-Root $c) { return $c }
        }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Выберите папку GAMMA (где лежит ModOrganizer.exe)'
    while ($dlg.ShowDialog() -eq 'OK') {
        if (Test-Root $dlg.SelectedPath) { return $dlg.SelectedPath }
        [System.Windows.Forms.MessageBox]::Show('В этой папке нет ModOrganizer.exe и папки mods.') | Out-Null
    }
    throw 'Папка GAMMA не выбрана'
}

if ($GammaRoot) {
    $root = [IO.Path]::GetFullPath($GammaRoot).TrimEnd('\')
    if (-not (Test-Root $root)) { throw "В '$root' нет ModOrganizer.exe и папки mods" }
} else {
    $root = Find-Root
    New-Item -ItemType Directory (Split-Path $saved) -Force | Out-Null
    Set-Content $saved $root -Encoding UTF8
}
Write-Host "GAMMA: $root"

if (Test-Blocking) {
    if ($NoWait) { Write-Host 'Mod Organizer запущен - установка отложена.'; exit 2 }
    while (Test-Blocking) {
        Write-Host 'Закройте Mod Organizer (и игру), затем нажмите Enter...' -ForegroundColor Yellow
        [void](Read-Host)
    }
}

$info = Get-Content "$pack\pack.txt" -Encoding UTF8
$version = ($info | Where-Object { $_ -like 'version=*' }) -replace '^version=', ''
$section = ($info | Where-Object { $_ -like 'section=*' }) -replace '^section=', ''
if (-not $section) { $section = 'xrRazom Sync' }
$sepName = "${section}_separator"
# порядок модов как у хоста
$names = @($info | Where-Object { $_ -like '[[]mod[]] *' } | ForEach-Object { $_.Substring(6) })
if ($names.Count -eq 0) { $names = @(Get-ChildItem "$pack\mods" -Directory | ForEach-Object { $_.Name }) }

# 1. файлы модов: папка заменяется целиком, чтобы не осталось удалённых файлов
foreach ($n in $names) {
    $dst = Join-Path $root "mods\$n"
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath "$pack\mods\$n" -Destination $dst -Recurse
    Set-Content -LiteralPath (Join-Path $dst $MARKER) "xrRazom fixes pack $version" -Encoding UTF8
    Write-Host "  установлен: $n"
}
$sepDir = Join-Path $root "mods\$sepName"
if (-not (Test-Path -LiteralPath $sepDir)) {
    New-Item -ItemType Directory -Path $sepDir | Out-Null
    Set-Content -LiteralPath (Join-Path $sepDir 'meta.ini') "[General]`r`nmodid=0`r`nversion=`r`nnewestVersion=`r`ncategory=0`r`ninstallationFile=" -Encoding UTF8
}

# 2. профиль MO2: пересобирается только секция пакета
$ini = Get-Content (Join-Path $root 'ModOrganizer.ini') -Encoding UTF8
$profile = ($ini | Where-Object { $_ -match '^selected_profile=' }) -replace '^selected_profile=(@ByteArray\()?', '' -replace '\)$', ''
if ($ProfileName) { $profile = $ProfileName }
$modlist = Join-Path $root "profiles\$profile\modlist.txt"
if (-not (Test-Path $modlist)) {
    Write-Host "Не найден $modlist - включите моды в MO2 вручную." -ForegroundColor Yellow
} else {
    Copy-Item $modlist "$modlist.xrrfix.bak" -Force
    $lines = @(Get-Content $modlist -Encoding UTF8)

    # границы старой секции: строки над разделителем до предыдущего разделителя
    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Length -gt 1 -and $lines[$i].Substring(1) -eq $sepName) { $sepIdx = $i; break }
    }
    $start = $sepIdx
    if ($sepIdx -ge 0) {
        while ($start -gt 0 -and -not ($lines[$start - 1].StartsWith('#') -or $lines[$start - 1].EndsWith('_separator'))) { $start-- }
    }

    $head = New-Object System.Collections.Generic.List[string]
    $before = New-Object System.Collections.Generic.List[string]   # над секцией (выше приоритет)
    $after = New-Object System.Collections.Generic.List[string]    # под разделителем секции
    $leftovers = New-Object System.Collections.Generic.List[string] # старые моды секции, которых нет в пакете
    $moved = New-Object System.Collections.Generic.List[string]     # чужие моды, оказавшиеся в секции
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.StartsWith('#')) { $head.Add($l); continue }
        if ($l.Length -lt 2) { continue }
        $name = $l.Substring(1)
        $inSection = ($sepIdx -ge 0) -and ($i -ge $start) -and ($i -le $sepIdx)
        if ($i -eq $sepIdx) { continue }
        if ($names -contains $name) { continue }   # моды пакета переезжают в секцию
        $ours = ($LEGACY -contains $name) -or (Test-Path -LiteralPath (Join-Path $root "mods\$name\$MARKER"))
        if ($inSection) {
            if ($ours) {
                if ($l.StartsWith('+')) { Write-Host "  выключен (нет в пакете): $name" -ForegroundColor DarkYellow }
                $leftovers.Add('-' + $name)
            } else {
                # чужой мод в секции: сохраняет состояние, переезжает сразу под разделитель
                $moved.Add($l)
                Write-Host "  перенесён из секции: $name"
            }
            continue
        }
        if ($ours -and $l.StartsWith('+')) {
            $l = '-' + $name
            Write-Host "  выключен старый фикс вне секции: $name" -ForegroundColor DarkYellow
        }
        if ($sepIdx -ge 0 -and $i -lt $start) { $before.Add($l) } else { $after.Add($l) }
    }
    $block = @($names | ForEach-Object { '+' + $_ }) + @($leftovers) + @('+' + $sepName)
    $out = @($head) + @($before) + $block + @($moved) + @($after)
    [IO.File]::WriteAllLines($modlist, $out, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Профиль '$profile': секция '$section' обновлена (копия: modlist.txt.xrrfix.bak)"
}

Write-Host ""
Write-Host "Готово: пакет $version установлен." -ForegroundColor Green
