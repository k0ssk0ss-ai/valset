// RiotEvents.cs — события клиента Riot (порт сторожа из agent.ps1): lockfile, WAMP по WebSocket,
// вход в аккаунт, игра запущена/закрыта, токен игры. Без опроса — только ожидание событий.
using System;
using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;

class RiotEvents {
    public event Action<bool> ClientChanged;   // клиент открыт (канал событий подключён) / закрыт
    public event Action LoggedIn;              // вход в аккаунт (и при подключении к уже открытому клиенту)
    public event Action<bool> GameChanged;     // игра запущена / закрыта (сразу)
    public event Action<string> GameClosed;    // через 3 с после выхода из игры; токен игры или null
    public event Action<string> Pregame;       // выбор агента: что-то поменялось (сообщение RMS ares-pregame); id матча

    public volatile bool ClientUp;
    public volatile bool GameRunning;

    readonly ManualResetEvent stop = new ManualResetEvent(false);
    readonly AutoResetEvent appeared = new AutoResetEvent(false);
    readonly string lockPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Riot Games\\Riot Client\\Config\\lockfile");
    string gameToken, port, auth;
    DateTime lastLogin = DateTime.MinValue;
    bool gameSeen;
    FileSystemWatcher fsw;

    public void Start() { new Thread(Loop) { IsBackground = true, Name = "riot-events" }.Start(); }
    public void Stop() { stop.Set(); }

    void SetClient(bool v) {
        if (ClientUp == v) return;
        ClientUp = v;
        try { var h = ClientChanged; if (h != null) h(v); } catch { }
    }
    void SetGame(bool v) {
        if (GameRunning == v) return;
        GameRunning = v;
        try { var h = GameChanged; if (h != null) h(v); } catch { }
    }

    // Токен текущего входа ({accessToken, token, subject}); после выхода из аккаунта клиент его уже не отдаст.
    string Local(string path) {
        try {
            var wc = new WebClient(); wc.Encoding = Encoding.UTF8;
            wc.Headers[HttpRequestHeader.Authorization] = auth;
            return wc.DownloadString("https://127.0.0.1:" + port + path);
        } catch { return ""; }
    }

    void HoldToken() {
        string j = Local("/entitlements/v1/token");
        if (j.Contains("\"accessToken\"") && j.Contains("\"subject\"")) gameToken = j;
    }

    void AfterGame() {   // событие приходит, когда процесс игры уже завершён; 3 с — запас
        string tok = gameToken; gameToken = null;
        SetGame(false);
        new Thread(() => {
            if (stop.WaitOne(3000)) return;
            try { var h = GameClosed; if (h != null) h(tok); } catch { }
        }) { IsBackground = true }.Start();
    }

    // Слушает события, пока клиент открыт. false — пришёл сигнал остановки.
    bool Listen() {
        string[] p;
        try {
            using (var fs = new FileStream(lockPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new StreamReader(fs)) p = r.ReadToEnd().Split(':');
        } catch { return !stop.WaitOne(3000); }
        if (p.Length < 5) return !stop.WaitOne(3000);
        port = p[2]; auth = "Basic " + Convert.ToBase64String(Encoding.ASCII.GetBytes("riot:" + p[3]));
        using (var ws = new ClientWebSocket()) {
            ws.Options.SetRequestHeader("Authorization", auth);
            ws.Options.AddSubProtocol("wamp");
            try { ws.ConnectAsync(new Uri("wss://127.0.0.1:" + p[2]), CancellationToken.None).Wait(10000); } catch { }
            if (ws.State != WebSocketState.Open) return !stop.WaitOne(5000);   // клиент ещё поднимается
            var sub = Encoding.UTF8.GetBytes("[5, \"OnJsonApiEvent\"]");
            ws.SendAsync(new ArraySegment<byte>(sub), WebSocketMessageType.Text, true, CancellationToken.None).Wait();
            SetClient(true);
            lastLogin = DateTime.Now;
            try { var h = LoggedIn; if (h != null) h(); } catch { }   // клиент уже открыт — вход мог быть раньше
            // и игра могла уже идти (приложение перезапустилось посреди игры) — тогда сразу держим её токен
            gameSeen = Local("/product-session/v1/external-sessions").Contains("\"productId\":\"valorant\"");
            if (gameSeen) { HoldToken(); SetGame(true); }
            Mem.Trim();
            var buf = new byte[65536]; var sb = new StringBuilder(); bool dirty = false;
            try {
                while (ws.State == WebSocketState.Open) {
                    var t = ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None);
                    var wh = new WaitHandle[] { stop, ((IAsyncResult)t).AsyncWaitHandle };
                    int w = WaitHandle.WaitAny(wh, dirty ? 30000 : gameSeen ? 3600000 : Timeout.Infinite);
                    while (w == WaitHandle.WaitTimeout) {
                        if (!dirty && gameSeen) HoldToken();   // час без событий в игре — на всякий случай
                        Mem.Trim(); dirty = false; w = WaitHandle.WaitAny(wh, gameSeen ? 3600000 : Timeout.Infinite);   // тишина — отдать память
                    }
                    if (w == 0) return false;
                    WebSocketReceiveResult res;
                    try { res = t.Result; } catch { break; }
                    if (res.MessageType == WebSocketMessageType.Close) break;
                    sb.Append(Encoding.UTF8.GetString(buf, 0, res.Count));
                    if (!res.EndOfMessage) continue;
                    string m = sb.ToString(); sb.Clear();
                    if (gameSeen && m.Contains("\"uri\":\"/entitlements/v1/token\"") && m.Contains("\"eventType\":\"Update\"")) HoldToken();   // клиент обновил токен
                    else if (m.Contains("\"uri\":\"/entitlements/v1/token\"") && m.Contains("\"eventType\":\"Create\"")) {
                        if ((DateTime.Now - lastLogin).TotalSeconds < 15) continue;   // клиент выдаёт несколько токенов подряд
                        lastLogin = DateTime.Now;
                        if (stop.WaitOne(2000)) return false;
                        try { var h = LoggedIn; if (h != null) h(); } catch { }
                    } else if (m.Contains("\"uri\":\"/product-session/v1/external-sessions/")) {
                        if (m.Contains("\"eventType\":\"Create\"")) { gameSeen = true; HoldToken(); SetGame(true); }   // игра запущена
                        else if (m.Contains("\"eventType\":\"Delete\"") && gameSeen) { gameSeen = false; AfterGame(); }   // и закрыта (в т. ч. выходом из аккаунта)
                    } else if (m.Contains("/ares-pregame/pregame/v1/matches/")) {   // выбор агента: выбрал, зафиксировал, сменил кто-то из команды
                        var pm = System.Text.RegularExpressions.Regex.Match(m, "/ares-pregame/pregame/v1/matches/([0-9a-fA-F-]{36})");
                        if (pm.Success) { try { var h = Pregame; if (h != null) h(pm.Groups[1].Value); } catch { } }
                    }
                    dirty = true;
                }
            } finally {
                SetClient(false);
                if (gameSeen) { gameSeen = false; gameToken = null; SetGame(false); }
            }
        }
        return !stop.WaitOne(1000);
    }

    void Loop() {
        try {
            string dir = Path.GetDirectoryName(lockPath);
            Directory.CreateDirectory(dir);
            fsw = new FileSystemWatcher(dir, "lockfile");
            fsw.Created += (s, e) => appeared.Set(); fsw.Changed += (s, e) => appeared.Set(); fsw.Renamed += (s, e) => appeared.Set();
            fsw.EnableRaisingEvents = true;
            while (true) {
                if (File.Exists(lockPath)) { if (!Listen()) break; continue; }
                SetClient(false);
                Mem.Trim();
                if (WaitHandle.WaitAny(new WaitHandle[] { stop, appeared }) == 0) break;   // ждём, пока откроют клиент
                if (stop.WaitOne(2000)) break;   // клиент дописывает lockfile
            }
        } catch (Exception e) { Dbg.Log("события клиента: " + e.Message); }
        GC.KeepAlive(fsw);
    }
}
