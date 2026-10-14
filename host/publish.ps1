# Публикует фиксы xrRazom (включённые моды секции-разделителя MO2) в репозиторий GitHub.
# GitHub Actions затем собирает релиз, а агент у друга ставит его автоматически.
# Публикуются только моды, изменённые ЛОКАЛЬНО (3-way сравнение: MO2 / последняя синхронизация / GitHub),
# поэтому чужие изменения не откатываются. Изменения с GitHub сначала ставятся в свой MO2.
# Запуск: publish.bat [параметры]   (или powershell -File publish.ps1 [параметры])
#   -Message "текст"     описание коммита
#   -NoPrompt            без вопросов (новые моды НЕ публикуются, если нет -Yes)
#   -Yes                 новые моды в секции публиковать без вопроса
#   -SyncOnly            только получить изменения с GitHub в свой MO2, ничего не публиковать
#   -NoWait              если MO2/игра запущены или publish уже идёт - выйти с кодом 2
#   -TakeRemote "мод"    при конфликте взять версию с GitHub (* = все конфликты и порядок)
#   -TakeLocal "мод"     при конфликте оставить свою версию (* = все конфликты и порядок)
# Коды выхода: 0 ок, 1 ошибка, 2 отложено (MO2/игра запущены или publish уже идёт), 3 конфликт.
param(
    [string]$Message = '',
    [switch]$NoPrompt,
    [switch]$SyncOnly,
    [switch]$NoWait,
    [switch]$Yes,
    [string[]]$TakeRemote = @(),
    [string[]]$TakeLocal = @()
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
$OutputEncoding = New-Object Text.UTF8Encoding($false)

$hostDir  = $PSScriptRoot
$repoRoot = Split-Path $hostDir -Parent
$actionsFallback = 'https://github.com/EduardHavron/xrRazom-GAMMA-fixes/actions'
$IGNORE = @('meta.ini', 'xrrfix_pack.txt')   # top-level files of a mod that are not compared/published
$ABSENT = '<absent>'
$BlockProcs = @('ModOrganizer', 'Anomaly*')
if ($env:XRRFIX_BLOCK_PROCS) { $BlockProcs = @($env:XRRFIX_BLOCK_PROCS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$script:mutex = $null
$script:tempDir = $null

function Quit([int]$code) {
    if ($script:tempDir -and (Test-Path -LiteralPath $script:tempDir)) {
        try { Remove-Item -LiteralPath $script:tempDir -Recurse -Force } catch { }
    }
    if ($script:mutex) {
        try { $script:mutex.ReleaseMutex() } catch { }
        $script:mutex.Dispose(); $script:mutex = $null
    }
    exit $code
}
function Fail([string]$msg) {
    Write-Host ""
    Write-Host "ОШИБКА: $msg" -ForegroundColor Red
    Quit 1
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
# git with stdout read as UTF-8 regardless of the console code page (for parsing).
function QArg([string]$a) {
    if ($a -eq '') { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}
function GitRead([string[]]$GitArgs) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $script:gitExe
    $psi.Arguments = ((@('-c', 'core.autocrlf=false', '-c', 'core.quotepath=false') + $GitArgs) | ForEach-Object { QArg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.WorkingDirectory = $repoRoot
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $err = ''
    try { $err = $errTask.Result } catch { }
    return New-Object PSObject -Property @{ Code = $p.ExitCode; Out = $out; Err = ([string]$err).Trim() }
}
function GitLine([string[]]$GitArgs) {
    $r = GitRead $GitArgs
    if ($r.Code -ne 0) { return '' }
    return $r.Out.Trim()
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

# ---------- content keys (git blob ids) ----------
$sha1 = [Security.Cryptography.SHA1]::Create()
function Get-BlobId([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $hdr = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)" + [char]0)
    $all = New-Object byte[] ($hdr.Length + $bytes.Length)
    [Array]::Copy($hdr, 0, $all, 0, $hdr.Length)
    [Array]::Copy($bytes, 0, $all, $hdr.Length, $bytes.Length)
    return ([BitConverter]::ToString($sha1.ComputeHash($all)) -replace '-', '').ToLower()
}
function Join-Sorted($list) {
    $arr = [string[]]@($list)
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return ($arr -join "`n")
}
# Local mod folder -> "rel<TAB>blob" lines (sorted).
function Get-LocalKey([string]$dir) {
    $base = (Get-Item -LiteralPath $dir -Force).FullName.TrimEnd('\') + '\'
    $items = New-Object Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($base.Length).Replace('\', '/')
        if ($rel.IndexOf('/') -lt 0 -and $IGNORE -contains $rel) { continue }
        $items.Add($rel + "`t" + (Get-BlobId $f.FullName))
    }
    return (Join-Sorted $items)
}
# Commit -> @{ modName = key }
function Get-TreeKeys([string]$rev) {
    $h = @{}
    $r = GitRead @('ls-tree', '-r', '-z', $rev, '--', 'mods')
    if ($r.Code -ne 0) { Fail "git ls-tree $rev : $($r.Err)" }
    $tmp = @{}
    foreach ($e in $r.Out.Split([char]0)) {
        $tab = $e.IndexOf("`t")
        if ($tab -lt 0) { continue }
        $meta = $e.Substring(0, $tab).Split(' ')
        $path = $e.Substring($tab + 1)
        if ($meta.Count -lt 3 -or $meta[1] -ne 'blob') { continue }
        if ($path -notmatch '^mods/([^/]+)/(.+)$') { continue }
        $n = $matches[1]; $rel = $matches[2]
        if ($rel.IndexOf('/') -lt 0 -and $IGNORE -contains $rel) { continue }
        if (-not $tmp.ContainsKey($n)) { $tmp[$n] = New-Object Collections.Generic.List[string] }
        $tmp[$n].Add($rel + "`t" + $meta[2])
    }
    foreach ($n in @($tmp.Keys)) { $h[$n] = Join-Sorted $tmp[$n] }
    return $h
}
# Commit -> pack.json object (or $null)
function Get-Pack([string]$rev) {
    $r = GitRead @('cat-file', 'blob', "${rev}:pack/pack.json")
    if ($r.Code -ne 0 -or -not $r.Out.Trim()) { return $null }
    return ($r.Out.TrimStart([char]0xFEFF) | ConvertFrom-Json)
}
function Get-PackMods($pk) {
    if ($null -eq $pk) { return }
    foreach ($m in @($pk.mods)) { if ($m) { [string]$m } }
}
function Get-State($list, $keys, [string]$n) {
    if ($list -notcontains $n) { return $ABSENT }
    if ($keys.ContainsKey($n)) { return $keys[$n] }
    return ''
}
function Test-Blocking {
    $found = @()
    foreach ($p in $BlockProcs) { $found += @(Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName }) }
    return @($found | Select-Object -Unique)
}
# Insert names of $src missing in $base after their nearest preceding neighbour (from $src) present in $base.
function Merge-Order($base, $src, $set) {
    $res = New-Object Collections.Generic.List[string]
    foreach ($n in $base) { if ($set -contains $n -and -not $res.Contains($n)) { $res.Add($n) } }
    for ($i = 0; $i -lt $src.Count; $i++) {
        $n = $src[$i]
        if ($set -notcontains $n -or $res.Contains($n)) { continue }
        $pos = 0
        for ($j = $i - 1; $j -ge 0; $j--) {
            $k = $res.IndexOf($src[$j])
            if ($k -ge 0) { $pos = $k + 1; break }
        }
        $res.Insert($pos, $n)
    }
    return , $res.ToArray()
}
function Same-Seq($a, $b) { return ((@($a) -join "`n") -ceq (@($b) -join "`n")) }
function Filter-In($list, $set) { return , @($list | Where-Object { $set -contains $_ }) }

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
$gammaRoot = [IO.Path]::GetFullPath($gammaRoot).TrimEnd('\')
$section = $cfg['section']; if (-not $section) { $section = 'xrRazom Sync' }
$doPush = $true
if ($cfg.ContainsKey('push') -and $cfg['push'] -match '^(0|false|no|нет)$') { $doPush = $false }

if (-not (Test-Path "$gammaRoot\ModOrganizer.ini")) {
    Fail "Не найден ModOrganizer.ini в '$gammaRoot'. Укажите gamma_root в host\publish.ini."
}
if (-not (Test-Path "$repoRoot\.git")) { Fail "'$repoRoot' не является git-репозиторием." }
$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $gitCmd) { Fail "git не найден в PATH. Установите Git for Windows." }
$script:gitExe = @($gitCmd)[0].Source

# ---------- single instance ----------
$script:mutex = New-Object Threading.Mutex($false, 'Local\xrrfix_publish')
$got = $false
try { $got = $script:mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
if (-not $got) {
    if ($NoWait) {
        Write-Host "publish уже выполняется - отложено."
        $script:mutex.Dispose(); $script:mutex = $null
        exit 2
    }
    Write-Host "publish уже выполняется в другом окне - жду его завершения..." -ForegroundColor Yellow
    try { [void]$script:mutex.WaitOne() } catch [Threading.AbandonedMutexException] { }
}

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

$repoMods = Join-Path $repoRoot 'mods'
$repoPack = Join-Path $repoRoot 'pack'

Push-Location $repoRoot
try {

# ---------- repo state ----------
$gitDir = GitLine @('rev-parse', '--absolute-git-dir')
if (-not $gitDir) { Fail "git rev-parse не работает в '$repoRoot'." }
foreach ($p in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD') {
    if (Test-Path -LiteralPath (Join-Path $gitDir $p)) {
        Fail "В репозитории '$repoRoot' не завершён rebase/merge. Завершите или отмените его (git rebase --abort / git merge --abort)."
    }
}
$headSha = GitLine @('rev-parse', '--verify', '-q', 'HEAD^{commit}')
if (-not $headSha) { Fail "В репозитории нет коммитов." }

# repo mods/ and pack/ are generated from MO2: drop leftovers of an interrupted run
$dirty = (GitRead @('status', '--porcelain', '--', 'mods', 'pack')).Out.Trim()
if ($dirty) {
    Write-Host "Сбрасываю незакоммиченные изменения в mods/ и pack/ репозитория (они берутся из MO2)." -ForegroundColor DarkYellow
    RunGit reset -q -- mods pack | Out-Null
    RunGit checkout -q -- mods pack 2>$null | Out-Null
    RunGit clean -fdq -- mods pack | Out-Null
    $global:LASTEXITCODE = 0
}

$upRef = GitLine @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
if (-not $upRef) { $upRef = 'origin/main' }
Write-Host "git fetch ..."
RunGit fetch -q
if ($LASTEXITCODE -ne 0) { Fail "git fetch не удался. Проверьте интернет/доступ к GitHub и запустите снова." }
$remoteSha = GitLine @('rev-parse', '--verify', '-q', "$upRef^{commit}")
if (-not $remoteSha) { $remoteSha = $headSha }
$baseSha = GitLine @('merge-base', 'HEAD', $remoteSha)
if (-not $baseSha) { Fail "Нет общей истории между HEAD и $upRef." }
$remoteAhead = ((GitRead @('merge-base', '--is-ancestor', $remoteSha, 'HEAD')).Code -ne 0)

# local uncommitted edits outside mods/pack that the update would overwrite
if ($remoteAhead) {
    $incoming = @((GitRead @('diff', '--name-only', '-z', 'HEAD', $remoteSha)).Out.Split([char]0) | Where-Object { $_ })
    $dirtyOther = @()
    foreach ($e in (GitRead @('status', '--porcelain', '-z', '--untracked-files=no')).Out.Split([char]0)) {
        if ($e.Length -lt 4) { continue }
        $p = $e.Substring(3)
        if ($p -like 'mods/*' -or $p -like 'pack/*') { continue }
        if ($incoming -contains $p) { $dirtyOther += $p }
    }
    if ($dirtyOther.Count -gt 0) {
        Fail ("Незакоммиченные изменения в репозитории мешают обновлению с GitHub:`n" +
              (($dirtyOther | ForEach-Object { "  - $_" }) -join "`n") + "`nЗакоммитьте или отмените их (git stash) и запустите снова.")
    }
}

# ---------- 3-way comparison ----------
$Llist = @($mods)
$Bpack = Get-Pack $baseSha
$Rpack = Get-Pack $remoteSha
$Blist = @(Get-PackMods $Bpack)
$Rlist = @(Get-PackMods $Rpack)
$Bkeys = Get-TreeKeys $baseSha
if ($remoteSha -eq $baseSha) { $Rkeys = $Bkeys } else { $Rkeys = Get-TreeKeys $remoteSha }
$Lkeys = @{}
foreach ($n in $Llist) { $Lkeys[$n] = Get-LocalKey "$gammaRoot\mods\$n" }

$allNames = New-Object Collections.Generic.List[string]
foreach ($n in @($Llist) + @($Rlist) + @($Blist)) { if (-not $allNames.Contains($n)) { $allNames.Add($n) } }

function Resolve-Names($tokens, [ref]$all) {
    $h = @{}
    foreach ($t in @($tokens)) {
        if (-not $t) { continue }
        $parts = @($t.Trim())
        if ($allNames -notcontains $parts[0] -and $parts[0] -ne '*') { $parts = @($t.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        foreach ($p in $parts) {
            if ($p -eq '*') { $all.Value = $true }
            elseif ($allNames -contains $p) { $h[$p] = $true }
            else { Write-Host "Внимание: мод '$p' не найден ни локально, ни в репозитории - пропущен." -ForegroundColor Yellow }
        }
    }
    return $h
}
$takeAllR = $false; $takeAllL = $false
$takeR = Resolve-Names $TakeRemote ([ref]$takeAllR)
$takeL = Resolve-Names $TakeLocal ([ref]$takeAllL)

$status = @{}     # name -> sync|remote|local|equal|conflict
$finalKey = @{}   # name -> resulting state (key or ABSENT)
$conflicts = @()
foreach ($n in $allNames) {
    $L = Get-State $Llist $Lkeys $n
    $B = Get-State $Blist $Bkeys $n
    $R = Get-State $Rlist $Rkeys $n
    $lc = ($L -cne $B); $rc = ($R -cne $B)
    if ($L -ceq $R) { if ($lc) { $s = 'equal' } else { $s = 'sync' } }
    elseif (-not $lc) { $s = 'remote' }
    elseif (-not $rc) { $s = 'local' }
    else { $s = 'conflict' }
    if ($s -ne 'sync' -and $s -ne 'equal') {
        if ($takeR.ContainsKey($n) -or ($s -eq 'conflict' -and $takeAllR)) { $s = 'remote' }
        elseif ($takeL.ContainsKey($n) -or ($s -eq 'conflict' -and $takeAllL)) { $s = 'local' }
    }
    $status[$n] = $s
    if ($s -eq 'remote') { $finalKey[$n] = $R } else { $finalKey[$n] = $L }
    if ($s -eq 'conflict') { $conflicts += $n }
}
$finalSet = @($allNames | Where-Object { $finalKey[$_] -cne $ABSENT })

# list order: membership comes from the per-mod result, order from the side that reordered
$lReorder = -not (Same-Seq (Filter-In $Llist $Blist) (Filter-In $Blist $Llist))
$rReorder = -not (Same-Seq (Filter-In $Rlist $Blist) (Filter-In $Blist $Rlist))
$orderConflict = $false
if ($takeAllR) { $lReorder = $false }
elseif ($takeAllL) { $rReorder = $false }
if ($lReorder -and $rReorder -and -not (Same-Seq (Filter-In $Llist $Rlist) (Filter-In $Rlist $Llist))) { $orderConflict = $true }
if ($lReorder) { $resList = Merge-Order $Llist $Rlist $finalSet }
else { $resList = Merge-Order $Rlist $Llist $finalSet }
$resList = @($resList)

# ---------- report ----------
$shortR = $remoteSha.Substring(0, 7)
$isNew = @{}
foreach ($n in $Llist) { if ($Blist -notcontains $n -and $Rlist -notcontains $n) { $isNew[$n] = $true } }
$incomingMods = @($allNames | Where-Object { $status[$_] -eq 'remote' -and ($finalKey[$_] -cne (Get-State $Llist $Lkeys $_)) })
$localMods = @($allNames | Where-Object { $status[$_] -eq 'local' })
$orderIncoming = (-not $orderConflict) -and -not (Same-Seq $resList $Llist)

Write-Host ""
Write-Host "Сравнение с GitHub ($upRef $shortR):" -ForegroundColor Cyan
$any = $false
foreach ($n in $allNames) {
    switch ($status[$n]) {
        'remote'   { if ($incomingMods -contains $n) { $any = $true; if ($finalKey[$n] -ceq $ABSENT) { Write-Host "  [<] $n - удалён на GitHub, будет выключен" -ForegroundColor Cyan } else { Write-Host "  [<] $n - изменён на GitHub, будет установлен" -ForegroundColor Cyan } } }
        'local'    { $any = $true; if ($isNew.ContainsKey($n)) { Write-Host "  [>] $n - новый мод" -ForegroundColor Green } elseif ($finalKey[$n] -ceq $ABSENT) { Write-Host "  [>] $n - убран локально" -ForegroundColor Green } else { Write-Host "  [>] $n - изменён локально" -ForegroundColor Green } }
        'conflict' { $any = $true; Write-Host "  [!] $n - изменён и локально, и на GitHub" -ForegroundColor Red }
    }
}
if ($orderConflict) { $any = $true; Write-Host "  [!] порядок модов изменён и локально, и на GitHub" -ForegroundColor Red }
elseif ($orderIncoming -and $incomingMods.Count -eq 0) { $any = $true; Write-Host "  [<] порядок модов (с GitHub)" -ForegroundColor Cyan }
if (-not $any) { Write-Host "  всё совпадает" }

if ($conflicts.Count -gt 0 -or $orderConflict) {
    $names = @($conflicts)
    if ($orderConflict) { $names += '(порядок модов)' }
    Write-Host ""
    Write-Host "КОНФЛИКТ: эти изменения сделаны и у вас, и на GitHub (другим игроком):" -ForegroundColor Red
    $names | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Ничего не изменено. Решите, чья версия остаётся:"
    $ex = '*'; if ($conflicts.Count -gt 0) { $ex = $conflicts[0] }
    Write-Host "  взять версию с GitHub (ваши правки будут заменены):"
    Write-Host "      publish.bat -SyncOnly -TakeRemote `"$ex`""
    Write-Host "  оставить свою (перезапишет версию на GitHub):"
    Write-Host "      publish.bat -TakeLocal `"$ex`""
    Write-Host "  (вместо имени мода * - все конфликты сразу, включая порядок модов)"
    Write-Host "XRRFIX_SYNC_CONFLICT: mods=$($names -join ',')"
    Quit 3
}

# ---------- catch up: install remote changes into local MO2 ----------
$needInstall = ($incomingMods.Count -gt 0) -or $orderIncoming
if ($needInstall) {
    $blk = @(Test-Blocking)
    if ($blk.Count -gt 0) {
        if ($NoWait) {
            Write-Host "Mod Organizer/игра запущены ($($blk -join ', ')) - установка изменений с GitHub отложена."
            Quit 2
        }
        while (@(Test-Blocking).Count -gt 0) {
            if ($NoPrompt) {
                Write-Host "Жду закрытия Mod Organizer и игры..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            } else {
                Write-Host "Нужно поставить изменения с GitHub: закройте Mod Organizer (и игру), затем нажмите Enter..." -ForegroundColor Yellow
                [void](Read-Host)
            }
        }
    }

    $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) ("xrrfix_sync_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $pkMods = Join-Path $script:tempDir 'mods'
    New-Item -ItemType Directory $pkMods -Force | Out-Null

    # remote content of the mods that must come from GitHub
    $fromRemote = @($resList | Where-Object { $finalKey[$_] -cne (Get-State $Llist $Lkeys $_) })
    $rx = $null
    if ($fromRemote.Count -gt 0) {
        $zip = Join-Path $script:tempDir 'remote.zip'
        $rx = Join-Path $script:tempDir 'remote'
        $r = GitRead @('archive', '--format=zip', '-o', $zip, $remoteSha, '--', 'mods')
        if ($r.Code -ne 0) { Fail "git archive не удался: $($r.Err)" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $rx)
    }
    foreach ($n in $resList) {
        $dst = Join-Path $pkMods $n
        $loc = "$gammaRoot\mods\$n"
        if ($fromRemote -contains $n) {
            $src = Join-Path $rx "mods\$n"
            if (-not (Test-Path -LiteralPath $src)) { New-Item -ItemType Directory $dst -Force | Out-Null }
            else { Copy-Item -LiteralPath $src -Destination $dst -Recurse }
            if (Test-Path -LiteralPath "$loc\meta.ini") { Copy-Item -LiteralPath "$loc\meta.ini" -Destination (Join-Path $dst 'meta.ini') -Force }
        } else {
            & robocopy.exe $loc $dst /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { Fail "Не удалось скопировать '$loc' (robocopy код $LASTEXITCODE)." }
        }
    }
    $global:LASTEXITCODE = 0
    $ver = "sync-$shortR"
    $txt = "version=$ver`nprofile=github`nsection=$section`n`n" + (($resList | ForEach-Object { "[mod] $_" }) -join "`n") + "`n"
    [IO.File]::WriteAllText((Join-Path $script:tempDir 'pack.txt'), $txt, (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath (Join-Path $repoRoot 'installer\install.ps1') -Destination (Join-Path $script:tempDir 'install.ps1')

    # mods removed by the sync: mark them as ours so the installer switches them off
    foreach ($n in $Llist) {
        if ($resList -notcontains $n) {
            Set-Content -LiteralPath "$gammaRoot\mods\$n\xrrfix_pack.txt" "xrRazom fixes pack $ver" -Encoding UTF8
        }
    }

    Write-Host ""
    Write-Host "Ставлю изменения с GitHub в MO2..." -ForegroundColor Cyan
    # -Command (not -EncodedCommand: that makes the child write CLIXML to stderr)
    function Q1([string]$s) { "'" + $s.Replace("'", "''") + "'" }
    $cmd = "`$ProgressPreference = 'SilentlyContinue'; try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false) } catch { }; " +
           "& $(Q1 (Join-Path $script:tempDir 'install.ps1')) -NoWait -GammaRoot $(Q1 $gammaRoot) -Profile $(Q1 $mo2Profile); exit `$LASTEXITCODE"
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -NonInteractive -Command $cmd | ForEach-Object { Write-Host "  $_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) {
        if ($code -eq 2) { Write-Host "Установка отложена (Mod Organizer/игра запущены)." }
        else { Write-Host "ОШИБКА: установка изменений с GitHub не удалась (код $code)." -ForegroundColor Red }
        Quit $code
    }
    Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    $script:tempDir = $null
    Write-Host "XRRFIX_SYNC_RESULT: installed=$($incomingMods.Count) mods=$($incomingMods -join ',')"
} elseif ($SyncOnly) {
    Write-Host "XRRFIX_SYNC_RESULT: installed=0 mods="
}

# ---------- bring the repo to origin ----------
if ($remoteAhead) {
    $headIsBase = ((GitRead @('merge-base', '--is-ancestor', 'HEAD', $remoteSha)).Code -eq 0)
    if ($headIsBase) {
        RunGit merge -q --ff-only $remoteSha
        if ($LASTEXITCODE -ne 0) {
            if ($SyncOnly) { Write-Host "Внимание: не удалось обновить репозиторий (git merge --ff-only)." -ForegroundColor Yellow }
            else { Fail "git merge --ff-only $upRef не удался." }
        }
    } elseif (-not $SyncOnly) {
        # unpushed local commits: replay them on top of origin
        RunGit rebase -q --autostash $remoteSha
        if ($LASTEXITCODE -ne 0) {
            RunGit rebase --abort 2>$null | Out-Null
            Fail "git rebase $upRef не удался (конфликт с неотправленными коммитами). Разрешите вручную и запустите снова."
        }
    }
    $global:LASTEXITCODE = 0
}

if ($SyncOnly) {
    if ($localMods.Count -gt 0) {
        Write-Host "Неопубликованные локальные изменения: $($localMods -join ', ') (запустите publish.bat)." -ForegroundColor Yellow
    }
    Quit 0
}

# ---------- publish only local changes ----------
$skipNew = @()
foreach ($n in @($localMods | Where-Object { $isNew.ContainsKey($_) })) {
    $ok = $false
    if ($Yes) { $ok = $true }
    elseif (-not $NoPrompt) {
        $a = Read-Host "Новый мод в секции: '$n'. Публиковать? (y/N)"
        $a = (([string]$a) -replace '^[^\p{L}]+', '').Trim()  # redirected stdin may start with a BOM (in any code page)
        $ok = ($a -match '^(y|yes|д|да)$')
    }
    if (-not $ok) { $skipNew += $n; Write-Host "  не публикуется (новый, не подтверждён): $n" -ForegroundColor DarkYellow }
}
$pubList = @($resList | Where-Object { $skipNew -notcontains $_ })

New-Item -ItemType Directory $repoMods -Force | Out-Null
New-Item -ItemType Directory $repoPack -Force | Out-Null
foreach ($n in $localMods) {
    if ($skipNew -contains $n) { continue }
    $dst = Join-Path $repoMods $n
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    if ($finalKey[$n] -ceq $ABSENT) { continue }
    $src = "$gammaRoot\mods\$n"
    & robocopy.exe $src $dst /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "Не удалось скопировать '$src' (robocopy код $LASTEXITCODE)." }
    foreach ($junk in $IGNORE) {
        $p = Join-Path $dst $junk
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}
$global:LASTEXITCODE = 0

$headPack = Get-Pack 'HEAD'
$headList = @(Get-PackMods $headPack)
$headSection = ''; if ($headPack) { $headSection = [string]$headPack.section }
if (-not (Same-Seq $pubList $headList) -or $headSection -cne $section) {
    $json = "{`n  `"section`": " + (JsonStr $section) + ",`n  `"mods`": [`n" +
            (($pubList | ForEach-Object { '    ' + (JsonStr $_) }) -join ",`n") + "`n  ]`n}`n"
    [IO.File]::WriteAllText((Join-Path $repoPack 'pack.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

# ---------- git ----------
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
            Quit 0
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
        $desc = ([string]$desc).TrimStart([char]0xFEFF).Trim()  # redirected stdin may carry a BOM
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
        Quit 0
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
        Quit 0
    }

    $run = $null
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        for ($t = 0; $t -lt 10 -and -not $run; $t++) {
            Start-Sleep -Seconds 3
            $raw = & $gh run list --limit 5 --json databaseId,url,status,headSha 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $list = @(($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })  # PS 5.1 emits the array as one object
                $run = $list | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1
            }
        }
    } finally { $ErrorActionPreference = $old }
    if (-not $run) {
        Write-Host "Не удалось найти запуск сборки через gh. Смотрите: $actionsUrl" -ForegroundColor Yellow
        Quit 0
    }
    Write-Host "Сборка: $($run.url)  ($($run.status))" -ForegroundColor Cyan
    if ($NoPrompt) { Quit 0 }
    $ans = Read-Host "Следить за сборкой? (y/N)"
    $ans = (([string]$ans) -replace '^[^\p{L}]+', '').Trim()  # redirected stdin may start with a BOM (in any code page)
    if ($ans -notmatch '^(y|yes|д|да)$') { Quit 0 }

    $ErrorActionPreference = 'Continue'
    & $gh run watch $run.databaseId --exit-status
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Сборка завершилась с ошибкой: $($run.url)" -ForegroundColor Red
        Quit 1
    }
    $rel = & $gh release view --json url --jq .url 2>$null
    if ($LASTEXITCODE -eq 0 -and $rel) { Write-Host "Релиз: $rel" -ForegroundColor Green }
    else { Write-Host "Релиз: $($actionsUrl -replace '/actions$', '/releases/latest')" -ForegroundColor Green }
}
finally {
    Pop-Location
}
Quit 0
