# agent.ps1 — помощник в фоне: уведомления и (по желанию) автоперенос. По умолчанию выключен.
#
# Как устроено — без опроса, только ожидание событий:
#   сторож   — крошечная программа (valset-agent-7.exe), стартует со входом в Windows (HKCU\...\Run).
#              Клиент Riot закрыт → спит, пока Windows не сообщит о появлении его lockfile (FileSystemWatcher).
#              Клиент открыт → слушает локальный канал событий клиента (WebSocket, WAMP) и ждёт:
#                Create /entitlements/v1/token                    — вход в аккаунт → `valset watch`
#                Delete /product-session/v1/external-sessions/…   — игра закрыта → через 3 с `valset watch -AfterGame`
#              (события проверены на живом клиенте 2026-10-06). Процесс игры сторож не трогает.
#              Пока идёт игра, держит в памяти её токен и отдаёт его `watch -AfterGame`
#              через переменную окружения: выйдешь из аккаунта прямо из игры — клиент токен удалит, а сервер его ещё
#              принимает (замер 2026-10-10, NOTES), и исходные вернутся всё равно. На диск токен не пишется.
#              Токен живёт 60 мин; клиент обновляет его за ~30 с до конца и шлёт Update /entitlements/v1/token —
#              по этому событию и берём новый. Раз в час — на случай, если событие потерялось.
#   проверка — `valset watch` (скрыто, одна проверка и выход): чужой аккаунт — автоперенос или уведомление «не твои»;
#              основной — уведомление, если его настройки разошлись с моими (после игры — тоже).
# Основной аккаунт автоперенос не трогает: его настройки меняешь ты сам и потом «Запоминаешь».
# config.json: { autoApply, notify } — по умолчанию оба выкл: фоновую программу человек включает сам.
# Сторож работает, только если включено хоть что-то.

$AgentExe      = Join-Path $Root 'valset-agent-7.exe'
$AgentMutex    = 'Local\valset-agent'
$AgentStopName = 'Local\valset-agent-stop'
$RunKey        = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$WatchDonePath = Join-Path $Root 'watch-done.txt'
$ConfigPath    = Join-Path $Root 'config.json'
$ToastAppId    = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$AgentSrc = @"
using System; using System.IO; using System.Text; using System.Threading; using System.Diagnostics;
using System.Net; using System.Net.WebSockets;
static class ValsetAgent {
    static string Cmd, Lock; static EventWaitHandle Stop; static DateTime LastLogin = DateTime.MinValue; static bool GameSeen; static string GameToken, LockPort, LockAuth;

    [System.Runtime.InteropServices.DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr h);
    static void Trim() { GC.Collect(); try { EmptyWorkingSet(Process.GetCurrentProcess().Handle); } catch { } }   // в ожидании память не нужна

    static void Run(string arg, string token = null) {
        var si = new ProcessStartInfo("cmd.exe", "/c \"\"" + Cmd + "\" " + arg + "\"");
        si.CreateNoWindow = true; si.UseShellExecute = false; si.WindowStyle = ProcessWindowStyle.Hidden;
        if (token != null) si.EnvironmentVariables["VALSET_GAME_TOKEN"] = token;
        try { Process.Start(si).Dispose(); } catch { }
    }

    // Токен текущего входа ({accessToken, token, subject}); после выхода из аккаунта клиент его уже не отдаст.
    static string Local(string path) {
        try {
            var wc = new WebClient(); wc.Encoding = Encoding.UTF8;
            wc.Headers[HttpRequestHeader.Authorization] = LockAuth;
            return wc.DownloadString("https://127.0.0.1:" + LockPort + path);
        } catch { return ""; }
    }

    static void HoldToken() {
        string j = Local("/entitlements/v1/token");
        if (j.Contains("\"accessToken\"") && j.Contains("\"subject\"")) GameToken = j;
    }

    static void AfterGame() {   // событие приходит, когда процесс игры уже завершён; 3 с — запас, ждать дольше незачем
        string tok = GameToken; GameToken = null;
        new Thread(() => { if (!Stop.WaitOne(3000)) Run("watch -AfterGame", tok); }) { IsBackground = true }.Start();
    }

    // Слушает события клиента, пока он открыт. false — пришёл сигнал остановки.
    static bool Listen() {
        string[] p;
        try { using (var fs = new FileStream(Lock, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
              using (var r = new StreamReader(fs)) p = r.ReadToEnd().Split(':'); } catch { return !Stop.WaitOne(3000); }
        if (p.Length < 5) return !Stop.WaitOne(3000);
        LockPort = p[2]; LockAuth = "Basic " + Convert.ToBase64String(Encoding.ASCII.GetBytes("riot:" + p[3]));
        using (var ws = new ClientWebSocket()) {
            ws.Options.SetRequestHeader("Authorization", "Basic " + Convert.ToBase64String(Encoding.ASCII.GetBytes("riot:" + p[3])));
            ws.Options.AddSubProtocol("wamp");
            try { ws.ConnectAsync(new Uri("wss://127.0.0.1:" + p[2]), CancellationToken.None).Wait(10000); } catch { }
            if (ws.State != WebSocketState.Open) return !Stop.WaitOne(5000);   // клиент ещё поднимается
            var sub = Encoding.UTF8.GetBytes("[5, \"OnJsonApiEvent\"]");
            ws.SendAsync(new ArraySegment<byte>(sub), WebSocketMessageType.Text, true, CancellationToken.None).Wait();
            Run("watch");   // клиент уже открыт — вход мог быть раньше
            // и игра могла уже идти (сторож перезапустился посреди игры) — тогда сразу держим её токен
            GameSeen = Local("/product-session/v1/external-sessions").Contains("\"productId\":\"valorant\"");
            if (GameSeen) HoldToken();
            LastLogin = DateTime.Now; Trim();
            var buf = new byte[65536]; var sb = new StringBuilder(); bool dirty = false;
            while (ws.State == WebSocketState.Open) {
                var t = ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None);
                var wh = new WaitHandle[] { Stop, ((IAsyncResult)t).AsyncWaitHandle };
                int w = WaitHandle.WaitAny(wh, dirty ? 30000 : GameSeen ? 3600000 : Timeout.Infinite);
                while (w == WaitHandle.WaitTimeout) {
                    if (!dirty && GameSeen) HoldToken();                                   // час без событий в игре — на всякий случай
                    Trim(); dirty = false; w = WaitHandle.WaitAny(wh, GameSeen ? 3600000 : Timeout.Infinite);   // тишина — отдать память
                }
                if (w == 0) return false;
                WebSocketReceiveResult res;
                try { res = t.Result; } catch { break; }
                if (res.MessageType == WebSocketMessageType.Close) break;
                sb.Append(Encoding.UTF8.GetString(buf, 0, res.Count));
                if (!res.EndOfMessage) continue;
                string m = sb.ToString(); sb.Clear();
                if (GameSeen && m.Contains("\"uri\":\"/entitlements/v1/token\"") && m.Contains("\"eventType\":\"Update\"")) HoldToken();   // клиент обновил токен
                else if (m.Contains("\"uri\":\"/entitlements/v1/token\"") && m.Contains("\"eventType\":\"Create\"")) {
                    if ((DateTime.Now - LastLogin).TotalSeconds < 15) continue;   // клиент выдаёт несколько токенов подряд
                    LastLogin = DateTime.Now;
                    if (Stop.WaitOne(2000)) return false;
                    Run("watch");
                } else if (m.Contains("\"uri\":\"/product-session/v1/external-sessions/")) {
                    if (m.Contains("\"eventType\":\"Create\"")) { GameSeen = true; HoldToken(); }        // игра запущена
                    else if (m.Contains("\"eventType\":\"Delete\"") && GameSeen) { GameSeen = false; AfterGame(); }   // и закрыта (в т. ч. выходом из аккаунта)
                }
                dirty = true;
            }
        }
        return !Stop.WaitOne(1000);
    }

    static void Main(string[] args) {
        if (args.Length < 1) return;
        Cmd = args[0];
        bool created; var single = new Mutex(true, "Local\\valset-agent", out created);
        if (!created) return;
        Stop = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\valset-agent-stop");
        // У клиента Riot самоподписанный сертификат; сторож ходит только на 127.0.0.1.
        ServicePointManager.ServerCertificateValidationCallback = (s, c, ch, e) => { var r = s as HttpWebRequest; return r == null || r.RequestUri.Host == "127.0.0.1"; };
        Lock = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Riot Games\\Riot Client\\Config\\lockfile");
        var dir = Path.GetDirectoryName(Lock);
        Directory.CreateDirectory(dir);
        var appeared = new AutoResetEvent(false);
        var fsw = new FileSystemWatcher(dir, "lockfile");
        fsw.Created += (s, e) => appeared.Set(); fsw.Changed += (s, e) => appeared.Set(); fsw.Renamed += (s, e) => appeared.Set();
        fsw.EnableRaisingEvents = true;
        while (true) {
            if (File.Exists(Lock)) { if (!Listen()) break; continue; }
            Trim();
            if (WaitHandle.WaitAny(new WaitHandle[] { Stop, appeared }) == 0) break;   // ждём, пока откроют клиент
            if (Stop.WaitOne(2000)) break;   // клиент дописывает lockfile
        }
        GC.KeepAlive(single); GC.KeepAlive(fsw);
    }
}
"@
# ── Настройки помощника ──────────────────────────────────────────────────────

function Get-Config {
    # autoApply/notify — помощник только по личному выбору; gfxAll — писать графику во все аккаунты ПК ($null — ещё не спрашивали)
    $c = [pscustomobject]@{ autoApply = $false; notify = $false; gfxAll = $null; tempAuto = $null; lang = ''; dpi = 0 }
    if (Test-Path $ConfigPath) {
        try {
            $j = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in 'autoApply', 'notify', 'gfxAll', 'tempAuto') { if ($null -ne $j.$k) { $c.$k = [bool]$j.$k } }
            if ($j.lang -in 'ru', 'en') { $c.lang = $j.lang }
            if ($j.dpi -as [int]) { $c.dpi = [int]$j.dpi }
        } catch {}
    }
    $c
}

function Set-Config([string]$key, $value) {
    $c = Get-Config; $c.$key = $value
    New-Item -ItemType Directory -Force $Root | Out-Null
    Set-Content $ConfigPath (ConvertTo-Json $c) -Encoding UTF8
    if ($key -in 'notify', 'autoApply', 'tempAuto') { Update-Agent }
}

# ── Сторож ───────────────────────────────────────────────────────────────────

function Test-NamedMutex([string]$name) {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting($name, [ref]$m)) { $m.Dispose(); return $true }
    $false
}

function Test-WatchRunning  { Test-NamedMutex $WatchMutexName }
function Test-AgentRunning  { Test-NamedMutex $AgentMutex }
function Test-AgentEnabled  { $null -ne (Get-ItemProperty $RunKey -Name 'VALSET' -ErrorAction SilentlyContinue) }

function Send-Stop([string]$eventName, [scriptblock]$running) {
    $ev = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $eventName)
    [void]$ev.Set()
    for ($n = 0; $n -lt 60 -and (& $running); $n++) { Start-Sleep -Milliseconds 50 }
    [void]$ev.Reset(); $ev.Dispose()
}


# Сторож нужен, если включены уведомления или автоперенос.
function Update-Agent {
    $c = Get-Config
    if ($c.notify -or $c.autoApply -or ($c.tempAuto -and (Test-AnyTemp))) { Enable-Agent } else { Disable-Agent }
}

function Enable-Agent {
    if (-not (Test-Path $InstalledCmd)) { throw (L 'Сначала установи VALSET: valset.cmd install' 'Install VALSET first: valset.cmd install') }
    if (-not (Test-Path $AgentExe)) {
        Add-Type -TypeDefinition $AgentSrc -OutputAssembly $AgentExe -OutputType WindowsApplication
    }
    $want = "`"$AgentExe`" `"$InstalledCmd`""
    $was = (Get-ItemProperty $RunKey -Name 'VALSET' -ErrorAction SilentlyContinue).VALSET
    if ($was -ne $want) {
        Set-ItemProperty $RunKey -Name 'VALSET' -Value $want
        if (Test-AgentRunning) { Send-Stop $AgentStopName { Test-AgentRunning } }   # старая версия сторожа
        foreach ($old in Get-ChildItem $Root -Filter 'valset-agent-*.exe' | Where-Object FullName -ne $AgentExe) {
            Remove-Item -LiteralPath $old.FullName -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-AgentRunning)) { Start-Process $AgentExe -ArgumentList "`"$InstalledCmd`"" }
}

function Disable-Agent {
    Remove-ItemProperty $RunKey -Name 'VALSET' -ErrorAction SilentlyContinue
    if (Test-AgentRunning) { Send-Stop $AgentStopName { Test-AgentRunning } }
}

# ── Уведомления ──────────────────────────────────────────────────────────────

function Send-Toast([string]$title, [string]$text) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $esc = { param($s) [Security.SecurityElement]::Escape($s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $esc $title)</text><text>$(& $esc $text)</text></binding></visual></toast>")
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($ToastAppId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { Log "уведомление не показано: $($_.Exception.Message)" }
}

# Сверка аккаунта с моими настройками: @{ Same; Count; Sig } (Sig — отпечаток отличий, чтобы не повторять уведомление).
function Get-AccountDrift($s) {
    $cur = Get-Settings $s | ConvertFrom-Json
    $new = Read-Profile
    $null = Join-Crosshairs $cur $new (Test-TempDefault $s.Puuid)
    if (Test-PrefsEqual $cur $new) { return @{ Same = $true; Count = 0; Sig = '' } }
    $d = Compare-Prefs $cur $new
    $sig = (@($d | ForEach-Object { "$($_.What)=$($_.Old)" }) -join ';')
    if (-not $sig) { $sig = 'internal' }
    @{ Same = $false; Count = [Math]::Max(1, $d.Count); Sig = $sig }
}

# Основной: настройки разошлись с моими — один раз на каждое новое расхождение.
function Test-MainDrift($s, [string]$name) {
    $dr = Get-AccountDrift $s
    $prev = "$((Read-Accounts)[$s.Puuid].notified)"
    Set-AccountState $s.Puuid @{ state = $(if ($dr.Same) { 'same' } else { 'diff' }); diff = $dr.Count; checked = (Get-Stamp); notified = $dr.Sig }
    if ($dr.Same -or $dr.Sig -eq $prev) { return }
    Log "основной $($name): настройки разошлись с твоими ($($dr.Count))"
    Send-Toast "VALSET · $name" (L "Настройки изменились ($($dr.Count)). Поменял в игре — Ctrl+Alt+V → «Запомнить как мои»." "Settings changed ($($dr.Count)). Changed them in game? Ctrl+Alt+V → `“Save as mine`”.")
}

# ── Слежение ─────────────────────────────────────────────────────────────────

function Read-WatchDone { @(if (Test-Path $WatchDonePath) { Get-Content $WatchDonePath -Encoding ASCII }) }
function Add-WatchDone([string]$key) {
    $all = @(Read-WatchDone) + $key
    Set-Content $WatchDonePath ($all | Select-Object -Last 50) -Encoding ASCII
}

# Сессия из токена, который сторож держал, пока шла игра (VALSET_GAME_TOKEN). Годится только для облака.
function Get-GameTokenSession {
    if (-not $env:VALSET_GAME_TOKEN) { return $null }
    try { $t = $env:VALSET_GAME_TOKEN | ConvertFrom-Json } catch { return $null }
    if (-not $t.subject -or -not $t.accessToken) { return $null }
    [pscustomobject]@{ Puuid = $t.subject; Token = $t.accessToken; Entitlement = $t.token; ClientPid = ''; Port = ''; Auth = '' }
}

# Одна проверка по событию сторожа: вход в аккаунт (или клиент открылся) / игра закрыта (-AfterGame).
function Invoke-Watch([switch]$AfterGame) {
    $mutex = New-Object Threading.Mutex($false, $WatchMutexName)
    try { $got = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { return }
    $isMain = $false; $cfg = Get-Config
    try {
        if (Get-Process $GameProc -ErrorAction SilentlyContinue) { return }
        if (-not (Test-Path $ProfilePath)) { return }
        $s = $null
        for ($n = 0; $n -lt 5 -and -not $s; $n++) { $s = Get-Session; if (-not $s) { Start-Sleep 1 } }   # токен мог ещё не выдаться
        # Вышел из аккаунта прямо из игры (или уже вошёл в другой): клиент токен удалил, но сторож держал токен игры.
        $g = Get-GameTokenSession
        if ($AfterGame -and $g -and (Test-Temp $g.Puuid) -and (-not $s -or $s.Puuid -ne $g.Puuid)) {
            $ok = $false; try { $ok = Invoke-RestoreTemp $g } catch { Log "возврат токеном игры не удался: $($_.Exception.Message)" }
            $msg = if ($ok) { L 'Исходные настройки аккаунта возвращены.' 'The account''s original settings are back.' }
                   else { L 'Не успел вернуть исходные: ты вышел из аккаунта. Зайди в него и открой VALSET — «Вернуть исходные».' 'Could not restore the originals: you logged out. Log in to it and open VALSET — `“Restore originals`”.' }
            Send-Toast "VALSET · $(Get-AccountLabel $g.Puuid)" $msg
        }
        if (-not $s) { return }
        $key = "$($s.ClientPid):$($s.Puuid)"
        $isMain = $s.Puuid -eq (Get-MainPuuid)
        # Игра закрыта на аккаунте, где твои настройки стоят на время, — вернуть его исходные, пока ты в нём.
        if ($AfterGame -and (Test-Temp $s.Puuid)) {
            if (Invoke-RestoreTemp $s) { Send-Toast "VALSET · $(Get-AccountLabel $s.Puuid)" (L 'Исходные настройки аккаунта возвращены. Можно выходить.' 'The account''s original settings are back. You can log out.') }
            return
        }
        if ($key -notin (Read-WatchDone)) {
            $name = Register-Account $s
            if ($isMain) { if ($cfg.notify) { Test-MainDrift $s $name } }
            elseif ($cfg.autoApply) {
                Invoke-Apply $s
                $r = $script:LastApply
                if ($cfg.notify -and -not $r.Same) {
                    if ($r.Temp) { Send-Toast "VALSET · $name" (L "Твои настройки на время: $($r.Count) изм. После игры вернутся исходные." "Your settings for now: $($r.Count) changes. The originals come back after the game.") }
                    else { Send-Toast "VALSET · $name" (L "Твои настройки перенесены: $($r.Count) изм. Можно играть." "Your settings applied: $($r.Count) changes. Ready to play.") }
                }
            } elseif ($cfg.notify) {
                $dr = Get-AccountDrift $s
                Set-AccountState $s.Puuid @{ state = $(if ($dr.Same) { 'same' } else { 'diff' }); diff = $dr.Count; checked = (Get-Stamp) }
                if (-not $dr.Same) { Send-Toast "VALSET · $name" (L "Настройки не твои ($($dr.Count)). Ctrl+Alt+V → «Перенести мои» до запуска игры." "Not your settings ($($dr.Count)). Ctrl+Alt+V → `“Apply mine`” before launching the game.") }
            }
            Add-WatchDone $key
        } elseif ($AfterGame -and $isMain -and $cfg.notify) {
            Test-MainDrift $s (Get-AccountLabel $s.Puuid)   # не поменял ли что-то в игре
        }
    } catch {
        Log "помощник: ошибка: $($_.Exception.Message)"
        if ($cfg.notify -and $cfg.autoApply -and -not $isMain) { Send-Toast 'VALSET' "$(L 'Не удалось перенести настройки' 'Could not apply settings'): $($_.Exception.Message)" }
    } finally {
        $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}
function Get-RiotClientExe {
    $cfg = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
    if (-not (Test-Path $cfg)) { return $null }
    $j = Get-Content $cfg -Raw | ConvertFrom-Json
    @($j.rc_default, $j.rc_live) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Open-RiotClient {
    $exe = Get-RiotClientExe
    if (-not $exe) { throw (L 'Не нашёл клиент Riot на этом ПК.' 'Riot Client not found on this PC.') }
    Start-Process $exe
}
