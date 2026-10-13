# Публикует фиксы xrRazom (включённые моды секции-разделителя MO2) в репозиторий GitHub.
# GitHub Actions затем собирает релиз, а агент у друга ставит его автоматически.
# Запуск: publish.bat  (или powershell -File publish.ps1 [-Message "текст"] [-NoPrompt])
param(
    [string]$Message = '',
    [switch]$NoPrompt
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
$OutputEncoding = New-Object Text.UTF8Encoding($false)

$hostDir  = $PSScriptRoot
$repoRoot = Split-Path $hostDir -Parent
$actionsFallback = 'https://github.com/EduardHavron/xrRazom-GAMMA-fixes/actions'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "ОШИБКА: $msg" -ForegroundColor Red
    exit 1
}

# git wrapper: never let stderr turn into terminating errors in PS 5.1.
# autocrlf=false -> files are stored byte-exact (no CRLF/LF conversion).
function RunGit {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & git.exe -c core.autocrlf=false -c core.quotepath=false @args } finally { $ErrorActionPreference = $old }
}
function GitOut {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $r = & git.exe -c core.autocrlf=false -c core.quotepath=false @args 2>$null } finally { $ErrorActionPreference = $old }
    if ($null -ne $r) { $r }
}

function JsonStr([string]$s) {
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($c -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f $c)) }
        else { [void]$sb.Append($ch) }
    }
    return '"' + $sb.ToString() + '"'
}

# ---------- config ----------
$cfg = @{}
$iniPath = Join-Path $hostDir 'publish.ini'
if (Test-Path $iniPath) {
    foreach ($l in Get-Content $iniPath -Encoding UTF8) {
        if ($l -match '^\s*[;#]') { continue }
        if ($l -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') { $cfg[$matches[1].ToLower()] = $matches[2] }
    }
}
$gammaRoot = $cfg['gamma_root']
if (-not $gammaRoot) { $gammaRoot = Split-Path $repoRoot -Parent }
elseif (-not [IO.Path]::IsPathRooted($gammaRoot)) { $gammaRoot = Join-Path $hostDir $gammaRoot }
$gammaRoot = [IO.Path]::GetFullPath($gammaRoot)
$section = $cfg['section']; if (-not $section) { $section = 'xrRazom Sync' }
$doPush = $true
if ($cfg.ContainsKey('push') -and $cfg['push'] -match '^(0|false|no|нет)$') { $doPush = $false }

if (-not (Test-Path "$gammaRoot\ModOrganizer.ini")) {
    Fail "Не найден ModOrganizer.ini в '$gammaRoot'. Укажите gamma_root в host\publish.ini."
}
if (-not (Test-Path "$repoRoot\.git")) { Fail "'$repoRoot' не является git-репозиторием." }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git не найден в PATH. Установите Git for Windows." }

$mo2Profile = $cfg['profile']
if (-not $mo2Profile) {
    $line = Get-Content "$gammaRoot\ModOrganizer.ini" -Encoding UTF8 | Where-Object { $_ -match '^selected_profile=' } | Select-Object -First 1
    if (-not $line) { Fail "В ModOrganizer.ini нет selected_profile. Укажите profile в host\publish.ini." }
    $mo2Profile = $line -replace '^selected_profile=(@ByteArray\()?', '' -replace '\)$', ''
}
$modlist = "$gammaRoot\profiles\$mo2Profile\modlist.txt"
if (-not (Test-Path $modlist)) { Fail "Не найден $modlist" }

# ---------- section ----------
# Mods of a section = lines directly above "<section>_separator" up to the previous separator.
$lines = @(Get-Content $modlist -Encoding UTF8)
$sepIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Length -gt 1 -and $lines[$i].Substring(1) -eq "${section}_separator") { $sepIdx = $i; break }
}
if ($sepIdx -lt 0) {
    Fail ("В профиле '$mo2Profile' нет разделителя '$section'.`n" +
          "Создайте его в MO2 (ПКМ по списку модов -> Create Separator, имя: $section)`n" +
          "и перетащите в него моды-фиксы, которые нужно раздавать.")
}
$mods = @()
for ($i = $sepIdx - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    if ($l.StartsWith('#') -or $l.Length -lt 2) { continue }
    if ($l.EndsWith('_separator')) { break }
    if ($l.StartsWith('+')) { $mods = @($l.Substring(1)) + $mods }
}
if ($mods.Count -eq 0) {
    Fail "В секции '$section' нет включённых модов. Перетащите фиксы под разделитель '$section' в MO2 и включите их."
}
$missing = @($mods | Where-Object { -not (Test-Path -LiteralPath "$gammaRoot\mods\$_" -PathType Container) })
if ($missing.Count -gt 0) {
    Fail ("Моды включены в секции, но их папок нет в '$gammaRoot\mods':`n" + (($missing | ForEach-Object { "  - $_" }) -join "`n"))
}

Write-Host "Профиль: $mo2Profile    Секция: $section" -ForegroundColor Cyan
$mods | ForEach-Object { Write-Host "  + $_" }

# ---------- mirror into repo ----------
$repoMods = Join-Path $repoRoot 'mods'
$repoPack = Join-Path $repoRoot 'pack'
New-Item -ItemType Directory $repoMods -Force | Out-Null
New-Item -ItemType Directory $repoPack -Force | Out-Null

foreach ($d in @(Get-ChildItem -LiteralPath $repoMods -Directory -Force)) {
    if ($mods -notcontains $d.Name) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
}
foreach ($m in $mods) {
    $src = "$gammaRoot\mods\$m"
    $dst = Join-Path $repoMods $m
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    & robocopy.exe $src $dst /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "Не удалось скопировать '$src' (robocopy код $LASTEXITCODE)." }
    foreach ($junk in 'meta.ini', 'xrrfix_pack.txt') {
        $p = Join-Path $dst $junk
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}
$global:LASTEXITCODE = 0

$json = "{`n  `"section`": " + (JsonStr $section) + ",`n  `"mods`": [`n" +
        (($mods | ForEach-Object { '    ' + (JsonStr $_) }) -join ",`n") + "`n  ]`n}`n"
[IO.File]::WriteAllText((Join-Path $repoPack 'pack.json'), $json, (New-Object Text.UTF8Encoding($false)))

# ---------- git ----------
Push-Location $repoRoot
try {
    RunGit add -A -- mods pack
    if ($LASTEXITCODE -ne 0) { Fail "git add завершился с ошибкой." }
    RunGit diff --cached --quiet -- mods pack
    $hasChanges = ($LASTEXITCODE -ne 0)
    if (-not $hasChanges) {
        # nothing new, but an earlier commit may still be unpushed (failed push)
        $ahead = 0
        if ($doPush) { [int]::TryParse(((GitOut rev-list --count '@{u}..HEAD') | Select-Object -First 1), [ref]$ahead) | Out-Null }
        if ($ahead -le 0) {
            Write-Host ""
            Write-Host "Изменений нет" -ForegroundColor Green
            exit 0
        }
        Write-Host ""
        Write-Host "Новых изменений нет, но $ahead коммит(ов) ещё не отправлено - отправляю." -ForegroundColor Yellow
    }
    if ($hasChanges) {

    # Summary by top-level mod folder
    $changed = @{}
    $packChanged = $false
    foreach ($row in (GitOut diff --cached --no-renames --name-status -- mods pack)) {
        $parts = $row -split "`t"
        if ($parts.Count -lt 2) { continue }
        $path = $parts[1]
        if ($path -like 'pack/*') { $packChanged = $true; continue }
        if ($path -match '^mods/([^/]+)/') { $changed[$matches[1]] = $true }
    }
    $hasHead = (GitOut rev-parse --verify -q HEAD).Count -gt 0
    $added = @(); $removed = @(); $modified = @()
    foreach ($n in ($changed.Keys | Sort-Object)) {
        $inHead = $false
        if ($hasHead) { $inHead = (GitOut ls-tree --name-only HEAD -- "mods/$n").Count -gt 0 }
        $now = Test-Path -LiteralPath (Join-Path $repoMods $n)
        if (-not $inHead) { $added += $n } elseif (-not $now) { $removed += $n } else { $modified += $n }
    }
    Write-Host ""
    Write-Host "Изменения:" -ForegroundColor Cyan
    $added    | ForEach-Object { Write-Host "  [+] $_" -ForegroundColor Green }
    $removed  | ForEach-Object { Write-Host "  [-] $_" -ForegroundColor Red }
    $modified | ForEach-Object { Write-Host "  [*] $_" -ForegroundColor Yellow }
    if ($changed.Count -eq 0 -and $packChanged) { Write-Host "  [*] порядок модов (pack.json)" -ForegroundColor Yellow }

    $desc = $Message
    if (-not $desc -and -not $NoPrompt) {
        Write-Host ""
        $desc = Read-Host "Описание изменений (Enter - автоматически)"
    }
    # PS 5.1 mangles embedded double quotes in native args
    if ($desc) { $desc = $desc.Replace('"', "'").Trim() }
    if (-not $desc) {
        $names = @($added + $removed + $modified)
        if ($names.Count -gt 0) { $desc = "Update fixes: " + ($names -join ', ') }
        else { $desc = "Update fixes: mod order" }
    }

    RunGit commit -q -m $desc -- mods pack
    if ($LASTEXITCODE -ne 0) { Fail "git commit завершился с ошибкой." }
    $sha = (GitOut rev-parse HEAD) | Select-Object -First 1
    Write-Host "Коммит: $desc" -ForegroundColor Green
    }

    if (-not $doPush) {
        Write-Host "push=0 в publish.ini - коммит создан локально, отправка пропущена." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "git pull --rebase ..."
    RunGit pull --rebase --autostash -q
    if ($LASTEXITCODE -ne 0) {
        Fail "git pull --rebase не удался (конфликт?). Коммит остался локально. Разрешите вручную: git status / git rebase --abort, затем запустите снова."
    }
    Write-Host "git push ..."
    RunGit push -q
    if ($LASTEXITCODE -ne 0) { Fail "git push не удался. Проверьте доступ к GitHub (логин git) и запустите снова." }
    $sha = (GitOut rev-parse HEAD) | Select-Object -First 1
    Write-Host "Опубликовано." -ForegroundColor Green

    # ---------- GitHub Actions ----------
    $actionsUrl = $actionsFallback
    $origin = (GitOut remote get-url origin) | Select-Object -First 1
    if ($origin -match 'github\.com[/:]([^/]+)/(.+?)(\.git)?/?$') { $actionsUrl = "https://github.com/$($matches[1])/$($matches[2])/actions" }

    $gh = $null
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { $gh = $cmd.Source }
    elseif (Test-Path 'C:\Program Files\GitHub CLI\gh.exe') { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
    if (-not $gh -or $origin -notmatch 'github\.com') {
        Write-Host "Сборка релиза: $actionsUrl"
        exit 0
    }

    $run = $null
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        for ($t = 0; $t -lt 10 -and -not $run; $t++) {
            Start-Sleep -Seconds 3
            $raw = & $gh run list --limit 5 --json databaseId,url,status,headSha 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $list = @(($raw -join "`n") | ConvertFrom-Json)
                $run = $list | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1
            }
        }
    } finally { $ErrorActionPreference = $old }
    if (-not $run) {
        Write-Host "Не удалось найти запуск сборки через gh. Смотрите: $actionsUrl" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "Сборка: $($run.url)  ($($run.status))" -ForegroundColor Cyan
    if ($NoPrompt) { exit 0 }
    $ans = Read-Host "Следить за сборкой? (y/N)"
    if ($ans -notmatch '^(y|yes|д|да)$') { exit 0 }

    $ErrorActionPreference = 'Continue'
    & $gh run watch $run.databaseId --exit-status
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Сборка завершилась с ошибкой: $($run.url)" -ForegroundColor Red
        exit 1
    }
    $rel = & $gh release view --json url --jq .url 2>$null
    if ($LASTEXITCODE -eq 0 -and $rel) { Write-Host "Релиз: $rel" -ForegroundColor Green }
    else { Write-Host "Релиз: $($actionsUrl -replace '/actions$', '/releases/latest')" -ForegroundColor Green }
}
finally {
    Pop-Location
}
exit 0
