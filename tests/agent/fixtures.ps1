# Fixture helpers for tests/agent (dot-sourced by run.ps1). Uses $script:Root, $script:Lad, $script:Www set by run.ps1.

$script:SrcAgent = Join-Path $script:RepoRoot 'agent'
$script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
$script:AgentFiles = 'xrrfix_agent.ps1', 'setup_agent.ps1', 'setup_agent.bat', 'uninstall_agent.ps1', 'uninstall_agent.bat', 'README.txt'
$script:Utf8Bom = New-Object Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:OriginHttps = 'https://github.com/EduardHavron/xrRazom-GAMMA-fixes.git'
$script:FAKE_PROC = 'xrrfix_fake_mo2_agent'     # own name: does not collide with tests/publish running in parallel
$script:TaskName = 'xrRazom fixes updater'
$script:UA = 'xrrfix-agent/1.0 (+https://github.com/EduardHavron/xrRazom-GAMMA-fixes)'
$script:Children = New-Object System.Collections.ArrayList
$script:CaseN = 0
$script:RelN = 0
$script:Routes = @{}
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:StubPublish = @'
# test stub of host\publish.ps1
$ErrorActionPreference = 'Continue'
Write-Output ('STUB publish args=' + ($args -join ' ') + ' cwd=' + (Get-Location).Path)
Write-Output ('STUB env BLOCK=' + $env:XRRFIX_BLOCK_PROCS + ' GTP=' + $env:GIT_TERMINAL_PROMPT)
if ($env:STUB_MARK) { Add-Content -LiteralPath $env:STUB_MARK ('ran ' + ($args -join ' ')) }
Write-Output 'Проверка кириллицы: секция xrRazom Sync'
if ($env:STUB_LINES) { $env:STUB_LINES -split '\|' | ForEach-Object { Write-Output $_ } }
exit [int]$env:STUB_CODE
'@

$script:StubInstall = @'
# test stub of install.ps1
param([switch]$NoWait)
Write-Output ('STUB-INSTALL NoWait=' + $NoWait)
Write-Output ('STUB-CWD=' + (Get-Location).Path)
Write-Output ('STUB-LAD=' + $env:LOCALAPPDATA)
if ($env:STUB_INSTALL_LINES) { $env:STUB_INSTALL_LINES -split '\|' | ForEach-Object { Write-Output $_ } }
if ($env:STUB_INSTALL_STDERR) { [Console]::Error.WriteLine($env:STUB_INSTALL_STDERR) }
exit [int]$env:STUB_INSTALL_CODE
'@

# ---------- files ----------
function W([string]$Path, [string]$Text, [switch]$NoBom) {
    $d = Split-Path $Path
    if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory $d -Force | Out-Null }
    $enc = if ($NoBom) { $script:Utf8NoBom } else { $script:Utf8Bom }
    [IO.File]::WriteAllText($Path, $Text, $enc)
}
function Write-State([string]$Path, [string]$Value) { W $Path ($Value + "`r`n") }
function First([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $l = [IO.File]::ReadAllLines($Path)
    if ($l.Count -eq 0) { return '' }
    return $l[0].Trim([char]0xFEFF).Trim()
}
function FHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Q([string]$s) { "'" + $s.Replace("'", "''") + "'" }
function Get-Log([string]$H) { $p = Join-Path $H 'agent.log'; if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { '' } }
function Get-NewLog([string]$H, [string]$Before) { $l = Get-Log $H; if ($l.Length -lt $Before.Length) { return $l }; return $l.Substring($Before.Length) }
function Count-Of([string]$Text, [string]$Literal) { [regex]::Matches($Text, [regex]::Escape($Literal)).Count }
function Esc([string]$s) { [regex]::Escape($s) }
# log records without the per-run "[тест] XRRFIX_HOME=..." line
function Get-Records([string]$Text) { @($Text -split "`r`n" | Where-Object { $_ -and $_ -notmatch '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[тест\] XRRFIX_HOME=' }) }
function Assert-NoNotify([string]$Text, [string]$Msg = '') { Assert-NotMatch $Text '\[тест\] уведомление' "no notification expected $Msg" }

function New-Sandbox {
    $script:CaseN++
    $p = Join-Path $script:Root ("c{0:d3}" -f $script:CaseN)
    New-Item -ItemType Directory $p -Force | Out-Null
    return $p
}
function New-Gamma([string]$G) {
    New-Item -ItemType Directory "$G\mods", "$G\profiles\P" -Force | Out-Null
    W "$G\ModOrganizer.exe" 'stub' -NoBom
    return $G
}
function New-AgentHome([string]$H, [string]$Gamma = '', [switch]$NoAgent) {
    New-Item -ItemType Directory $H -Force | Out-Null
    if (-not $NoAgent) { New-Item -ItemType Directory "$H\agent" -Force | Out-Null; Copy-Item "$script:SrcAgent\*" "$H\agent\" -Force }
    if ($Gamma) { Write-State "$H\gamma_root.txt" $Gamma }
    return $H
}

# ---------- git ----------
function Invoke-Git([string]$Dir, [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & git.exe -C $Dir -c core.autocrlf=false @GitArgs 2>&1 | ForEach-Object { '' + $_ }; $c = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($c -ne 0) { throw "git $($GitArgs -join ' ') in $Dir failed ($c): $($o -join ' ')" }
    return (@($o) -join "`n")
}
function Set-RepoConfig([string]$Dir) {
    Invoke-Git $Dir config user.name xrrfix-test | Out-Null
    Invoke-Git $Dir config user.email test@example.invalid | Out-Null
    Invoke-Git $Dir config core.autocrlf false | Out-Null
    Invoke-Git $Dir config commit.gpgsign false | Out-Null
}
# Clone-shaped folder with a stub host\publish.ps1 (no network: origin is only read by `remote get-url`).
function New-StubClone([string]$C, [string]$Origin = $script:OriginHttps, [switch]$SeparateGitDir, [switch]$NoOriginMain, [switch]$NoAgentScript) {
    New-Item -ItemType Directory "$C\host", "$C\agent" -Force | Out-Null
    Copy-Item "$script:SrcAgent\*" "$C\agent\" -Force
    if ($NoAgentScript) { Remove-Item -LiteralPath "$C\agent\xrrfix_agent.ps1" -Force }
    W "$C\host\publish.ps1" $script:StubPublish
    if ($SeparateGitDir) { Invoke-Git $C init -q -b main --separate-git-dir ("$C" + '_gitdir') | Out-Null }
    else { Invoke-Git $C init -q -b main | Out-Null }
    Set-RepoConfig $C
    if ($Origin) { Invoke-Git $C remote add origin $Origin | Out-Null }
    Invoke-Git $C add -A | Out-Null
    Invoke-Git $C commit -q -m init | Out-Null
    if (-not $NoOriginMain) { Invoke-Git $C update-ref refs/remotes/origin/main HEAD | Out-Null }
    return $C
}
function Get-PathWithoutGit {
    (($env:PATH -split ';') | Where-Object {
        $d = $_
        if (-not $d) { return $false }
        try { -not ((Test-Path -LiteralPath (Join-Path $d 'git.exe')) -or (Test-Path -LiteralPath (Join-Path $d 'git.cmd')) -or (Test-Path -LiteralPath (Join-Path $d 'git.bat'))) } catch { $true }
    }) -join ';'
}

# ---------- processes ----------
function Stop-Tree([int]$ProcId) { try { & taskkill.exe /PID $ProcId /T /F 2>&1 | Out-Null } catch { } }
function Stop-AllChildren {
    foreach ($p in @($script:Children)) { try { if (-not $p.HasExited) { Stop-Tree $p.Id } } catch { } }
    Get-Process -Name $script:FAKE_PROC -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($script:Root, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { try { $_.Kill() } catch { } }
}
function Clean-Err([string]$e) {
    if ($e -match '^#< CLIXML') {
        $e = (([regex]::Matches($e, '<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value }) -join '') -replace '_x000D__x000A_', "`n" -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&'
    }
    return $e
}
# Runs a .ps1 in a child Windows PowerShell with UTF-8 output, given env overrides ($null value = remove), stdin and timeout.
# Returns { Code; Out (stdout + cleaned stderr) }.
function Invoke-Ps {
    param([string]$Script, [string]$ArgStr = '', [hashtable]$Env = @{}, [AllowNull()][string]$StdIn = $null, [int]$TimeoutSec = 180, [string]$WorkDir = '')
    $cmd = "`$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false); " +
           "try { [Console]::InputEncoding = New-Object Text.UTF8Encoding(`$false) } catch { }; `$global:LASTEXITCODE = 0; " +
           "try { & $(Q $Script) $ArgStr; exit `$LASTEXITCODE } catch { Write-Output ('THROWN: ' + `$_.Exception.Message); exit 1 }"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $PSHOME 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $enc"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom
    $psi.WorkingDirectory = if ($WorkDir) { $WorkDir } else { $script:Root }
    $ev = $psi.EnvironmentVariables
    foreach ($k in @('XRRFIX_HOME', 'XRRFIX_REPO', 'STUB_CODE', 'STUB_LINES', 'STUB_MARK', 'STUB_INSTALL_CODE', 'STUB_INSTALL_LINES', 'STUB_INSTALL_STDERR')) { if ($ev.ContainsKey($k)) { $ev.Remove($k) } }
    $ev['LOCALAPPDATA'] = $script:Lad
    $ev['XRRFIX_NO_NOTIFY'] = '1'
    $ev['XRRFIX_BLOCK_PROCS'] = $script:FAKE_PROC
    $ev['XRRFIX_API'] = $script:ApiUrl
    foreach ($k in $Env.Keys) { if ($null -eq $Env[$k]) { if ($ev.ContainsKey($k)) { $ev.Remove($k) } } else { $ev[$k] = [string]$Env[$k] } }
    if ($ev['XRRFIX_API'] -notmatch '^http://127\.0\.0\.1:') { throw "unsafe XRRFIX_API: $($ev['XRRFIX_API'])" }
    $p = [Diagnostics.Process]::Start($psi)
    [void]$script:Children.Add($p)
    $outT = $p.StandardOutput.ReadToEndAsync()
    $errT = $p.StandardError.ReadToEndAsync()
    try {
        $w = New-Object IO.StreamWriter($p.StandardInput.BaseStream, $script:Utf8NoBom)
        if ($null -ne $StdIn -and $StdIn -ne '') { $w.Write($StdIn) }
        $w.Close()
    } catch { }
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Stop-Tree $p.Id
        throw "timeout ${TimeoutSec}s: $Script $ArgStr"
    }
    $p.WaitForExit()
    $out = $outT.Result + "`n" + (Clean-Err $errT.Result)
    if ($script:Verbose) { Write-Host "    --- $(Split-Path $Script -Leaf) $ArgStr -> $($p.ExitCode)"; Write-Host $out -ForegroundColor DarkGray }
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $out }
}
function Assert-SafeHome([string]$H, [string]$LadForChild, [switch]$AllowRealLayout) {
    $full = [IO.Path]::GetFullPath($H).TrimEnd('\')
    if (-not $full.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "unsafe XRRFIX_HOME outside the temp root: $H" }
    if ((Split-Path $full -Leaf) -ne 'xrrfix') { throw "XRRFIX_HOME must be named xrrfix: $H" }
    if (-not $AllowRealLayout -and $full -eq (Join-Path $LadForChild 'xrrfix').TrimEnd('\')) { throw "XRRFIX_HOME equals LOCALAPPDATA\xrrfix (not test mode): $H" }
}
function Invoke-Agent {
    param([string]$H, [hashtable]$Env = @{}, [string]$ArgStr = '', [string]$Script = '', [switch]$NonTestMode, [int]$TimeoutSec = 180)
    $lad = if ($Env.ContainsKey('LOCALAPPDATA')) { $Env['LOCALAPPDATA'] } else { $script:Lad }
    Assert-SafeHome $H $lad -AllowRealLayout:$NonTestMode
    if (-not $Script) { $Script = Join-Path $H 'agent\xrrfix_agent.ps1' }
    $e = @{ XRRFIX_HOME = $H }
    foreach ($k in $Env.Keys) { $e[$k] = $Env[$k] }
    return (Invoke-Ps -Script $Script -ArgStr $ArgStr -Env $e -TimeoutSec $TimeoutSec)
}
# setup/uninstall: ALWAYS test mode (otherwise they would register / delete the real scheduled task)
function Invoke-Setup([string]$H, [string]$Dir, [string]$ArgStr = '', [hashtable]$Env = @{}, [AllowNull()][string]$StdIn = $null, [int]$TimeoutSec = 180) {
    if ($Env.ContainsKey('LOCALAPPDATA')) { throw 'setup must use the suite LOCALAPPDATA' }
    Assert-SafeHome $H $script:Lad
    $e = @{ XRRFIX_HOME = $H }; foreach ($k in $Env.Keys) { $e[$k] = $Env[$k] }
    return (Invoke-Ps -Script (Join-Path $Dir 'setup_agent.ps1') -ArgStr $ArgStr -Env $e -StdIn $StdIn -TimeoutSec $TimeoutSec)
}
function Invoke-Uninstall([string]$H, [string]$ArgStr = '', [AllowNull()][string]$StdIn = $null) {
    Assert-SafeHome $H $script:Lad
    return (Invoke-Ps -Script (Join-Path $script:SrcAgent 'uninstall_agent.ps1') -ArgStr $ArgStr -Env @{ XRRFIX_HOME = $H } -StdIn $StdIn -TimeoutSec 60)
}
function Get-TaskSnapshot {
    try {
        $null = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
        return [string](Export-ScheduledTask -TaskName $script:TaskName)
    } catch { return '<none>' }
}
function Start-FakeMo2([string]$Name = $script:FAKE_PROC) {
    $exe = Join-Path $script:Root "$Name.exe"
    if (-not (Test-Path -LiteralPath $exe)) { Copy-Item (Join-Path $env:WINDIR 'System32\PING.EXE') $exe }
    $p = Start-Process -FilePath $exe -ArgumentList '-n 600 127.0.0.1' -WindowStyle Hidden -PassThru
    [void]$script:Children.Add($p)
    for ($i = 0; $i -lt 50; $i++) { if (Get-Process -Name $Name -ErrorAction SilentlyContinue) { break }; Start-Sleep -Milliseconds 100 }
    return $p
}
function Stop-FakeMo2($p) { if ($p) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { } } }
function Get-FreePort {
    $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    return $port
}

# ---------- fake GitHub (fixtures\fake_github.py) ----------
function Start-FakeGitHub {
    $py = Get-Command python.exe, py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $py) { throw 'python not found in PATH (needed for fixtures\fake_github.py)' }
    $portFile = Join-Path $script:Root 'www_port.txt'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $py.Source
    $psi.Arguments = "-I `"$(Join-Path $script:Fixtures 'fake_github.py')`" `"$script:Www`" `"$portFile`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $script:Root
    $p = [Diagnostics.Process]::Start($psi)
    [void]$script:Children.Add($p)
    for ($i = 0; $i -lt 150 -and -not (Test-Path -LiteralPath $portFile); $i++) {
        if ($p.HasExited) { throw "fake_github.py exited with code $($p.ExitCode)" }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $portFile)) { throw 'fake_github.py did not start' }
    $port = ([IO.File]::ReadAllText($portFile)).Trim()
    $script:BaseUrl = "http://127.0.0.1:$port"
    $script:ApiUrl = "$script:BaseUrl/latest.json"
}
function Reset-Www {
    $script:Routes = @{}
    Get-ChildItem -LiteralPath $script:Www -Force -ErrorAction SilentlyContinue | ForEach-Object {
        for ($i = 0; $i -lt 10; $i++) { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 100 } }
    }
}
function Set-Route([string]$Path, [hashtable]$Route) {
    $script:Routes[$Path] = $Route
    W (Join-Path $script:Www '_routes.json') ($script:Routes | ConvertTo-Json -Depth 5) -NoBom
}
function Get-Requests([string]$Path = '') {
    $f = Join-Path $script:Www '_requests.log'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $r = @([IO.File]::ReadAllLines($f, $script:Utf8NoBom) | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($Path) { $r = @($r | Where-Object { $_.path -eq $Path }) }
    return $r
}
# Builds a release zip in www and points /latest.json at it. Returns { Ver; Zip; ZipPath; Url; Stage; Pkg }.
function New-Release {
    param([string]$Ver, [string]$Tag = '', [switch]$WithAgent, [string]$AgentMarker = 'selfupdate-marker', [switch]$Nested,
          [switch]$NoInstaller, [string[]]$Mods = @('Мод Один', 'Mod B'), [string]$PackVersion = '', [switch]$NoAsset,
          [switch]$Corrupt, [AllowNull()][string]$Etag = '"abc"')
    if (-not $Tag) { $Tag = "v$Ver" }
    if (-not $PackVersion) { $PackVersion = $Ver }
    $script:RelN++
    $st = Join-Path $script:Root ("stage\r{0}" -f $script:RelN)
    $pkg = if ($Nested) { Join-Path $st 'xrRazom_fixes' } else { $st }
    foreach ($m in $Mods) { W "$pkg\mods\$m\gamedata\scripts\x.script" "-- $Ver`r`n" -NoBom }
    W "$pkg\pack.txt" ("version=$PackVersion`nprofile=github`nsection=xrRazom Sync`n`n" + (($Mods | ForEach-Object { "[mod] $_" }) -join "`n") + "`n") -NoBom
    if (-not $NoInstaller) { W "$pkg\install.ps1" $script:StubInstall }
    if ($WithAgent) {
        New-Item -ItemType Directory "$pkg\agent" -Force | Out-Null
        Copy-Item "$script:SrcAgent\*" "$pkg\agent\" -Force
        [IO.File]::AppendAllText("$pkg\agent\xrrfix_agent.ps1", "`r`n# $AgentMarker`r`n")
    }
    $zipName = "rel_$($script:RelN).zip"
    $zip = Join-Path $script:Www $zipName
    if ($Corrupt) { $b = New-Object byte[] 4096; (New-Object Random 42).NextBytes($b); [IO.File]::WriteAllBytes($zip, $b) }
    else { [IO.Compression.ZipFile]::CreateFromDirectory($st, $zip) }
    $url = "$script:BaseUrl/$zipName"
    $assets = if ($NoAsset) { @() } else { @(@{ name = 'xrRazom_fixes.zip'; browser_download_url = $url }) }
    $json = ConvertTo-Json @{ tag_name = $Tag; assets = $assets } -Depth 5
    W (Join-Path $script:Www 'latest.json') $json -NoBom
    Set-Route '/latest.json' @{ etag = $Etag }
    return [pscustomobject]@{ Ver = $Ver; Zip = $zip; ZipPath = "/$zipName"; Url = $url; Stage = $st; Pkg = $pkg }
}
