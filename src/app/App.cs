// App.cs — точка входа: один экземпляр, канал для второго запуска, стоп-событие; Ctl — состояние и связка частей.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

static class Program {
    static readonly string Inst = Environment.GetEnvironmentVariable("VALSET_APP_INSTANCE") ?? "";
    static readonly string PipeName = "valset-app" + Inst;

    [STAThread]
    static int Main(string[] args) {
        Native.SetProcessDPIAware();
        if (args.Length < 1) return 1;
        Core.Cmd = args[0];
        string arg = args.Length > 1 ? args[1] : "";
        bool created;
        var single = new Mutex(true, "Local\\valset-app" + Inst, out created);
        if (!created) { SendToFirst(arg.Length > 0 ? arg : "valset:open"); return 0; }
        // У клиента Riot самоподписанный сертификат — его принимаем только на 127.0.0.1; остальные адреса (картинки
        // media.valorant-api.com, Img.cs) — обычная проверка. TLS 1.2 — exe без TargetFramework иначе берёт старые протоколы.
        ServicePointManager.ServerCertificateValidationCallback = (s, c, ch, e) => { var r = s as HttpWebRequest; return e == System.Net.Security.SslPolicyErrors.None || r == null || r.RequestUri.Host == "127.0.0.1"; };
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        var stop = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\valset-app-stop" + Inst);
        var app = new Application();
        app.DispatcherUnhandledException += (s, e) => { Dbg.Log("ИСКЛЮЧЕНИЕ: " + e.Exception); e.Handled = true; };
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        new Thread(PipeLoop) { IsBackground = true, Name = "pipe" }.Start();
        // Стоп (обновление/удаление): аккуратно, а если интерфейс завис — через 3 с выйти всё равно, иначе exe останется занят.
        new Thread(() => { stop.WaitOne(); Ctl.Ui.BeginInvoke(new Action(Ctl.Exit)); Thread.Sleep(3000); Environment.Exit(0); }) { IsBackground = true, Name = "stop" }.Start();
        InProc.Preload();
        Ctl.Init(app, arg);
        app.Run();
        GC.KeepAlive(single); GC.KeepAlive(stop);
        Environment.Exit(0);   // потоки ядра в памяти (runspace) не фоновые — без этого процесс не завершится
        return 0;
    }

    // Второй запуск: передать аргумент первому по именованному каналу.
    static void SendToFirst(string arg) {
        try {
            using (var c = new NamedPipeClientStream(".", PipeName, PipeDirection.Out)) {
                c.Connect(3000);
                var b = Encoding.UTF8.GetBytes(arg + "\n");
                c.Write(b, 0, b.Length); c.Flush();
            }
        } catch (Exception e) { Dbg.Log("канал: " + e.Message); }
    }

    static void PipeLoop() {
        while (true) {
            try {
                using (var s = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte)) {
                    s.WaitForConnection();
                    using (var r = new StreamReader(s, Encoding.UTF8)) {
                        string line = r.ReadLine();
                        if (line != null && Ctl.Ui != null) { string a = line; Ctl.Ui.BeginInvoke(new Action(() => Ctl.Handle(a))); }
                    }
                }
            } catch { Thread.Sleep(500); }
        }
    }
}

class Status { public uint Color; public string Text; }

// Состояние приложения и связка: события клиента -> ядро -> интерфейс (трей, панель, значок).
static class Ctl {
    public const uint Green = 0x3BA55C, Amber = 0xE0A100, Blue = 0x3D8BFD, Gray = 0x7A7A7A;
    static readonly string[] Actions = { "apply", "binds", "applyperm", "save", "savebinds", "untemp", "undo" };

    public static Dispatcher Ui;
    public static Application App;
    public static Tray Tray;
    public static PanelWin Panel;
    public static BadgeWin Badge;
    public static OverlayWin Overlay;
    public static RiotEvents Events;

    public static State Cur = new State();
    public static bool HaveState, Busy, ResultOk, ResultUndo;
    public static string ResultMsg;
    public static DateTime StateAt = DateTime.MinValue;
    public static event Action Changed;

    static readonly Queue<Action> queue = new Queue<Action>();
    static readonly AutoResetEvent wake = new AutoResetEvent(false);
    static bool stateQueued;

    public static void Init(Application app, string arg) {
        App = app; Ui = app.Dispatcher;
        new Thread(Worker) { IsBackground = true, Name = "core" }.Start();
        Tray = new Tray(); Panel = new PanelWin(); Badge = new BadgeWin(); Overlay = new OverlayWin();
        Changed += () => {
            try { Tray.Update(); } catch (Exception e) { Dbg.Log("tray: " + e); }
            try { Panel.Refresh(); } catch (Exception e) { Dbg.Log("panel: " + e); }
            try { Badge.Update(); } catch (Exception e) { Dbg.Log("badge: " + e); }
            try { Overlay.Update(); } catch (Exception e) { Dbg.Log("overlay: " + e); }
            Mem.TrimSoon();
        };
        Events = new RiotEvents();
        Events.LoggedIn += () => Ui.BeginInvoke(new Action(OnLogin));
        Events.ClientChanged += up => Ui.BeginInvoke(new Action(() => { RefreshState(); Raise(); }));
        Events.GameChanged += running => Ui.BeginInvoke(new Action(() => { if (running) OverlayWin.ReadFsMode(); Raise(); }));
        // меню / выбор агента / матч (присутствие): кнопка поверх игры; в меню режим экрана перечитываем — его могли сменить
        Events.LoopChanged += st => Ui.BeginInvoke(new Action(() => { Dbg.Log("игрок: " + st); if (st == "MENUS") OverlayWin.ReadFsMode(); try { Overlay.Update(); } catch (Exception e) { Dbg.Log("overlay: " + e); } }));
        Events.GameClosed += tok => Ui.BeginInvoke(new Action(() => OnGameClosed(tok)));
        Events.Pregame += mid => Ui.BeginInvoke(new Action(() => OnPregame(mid)));
        Tray.Update();
        RefreshState();
        Events.Start();
        if (arg.Length > 0) Handle(arg);
        string selfArg = Environment.GetEnvironmentVariable("VALSET_SELFTEST") ?? "";
        if (selfArg == "1") SelfTest.Start();
        else if (selfArg.StartsWith("coll:")) SelfColl.Start(selfArg.Substring(5));   // замер памяти: коллекция с картинками
    }

    static bool exiting;
    public static void Raise() { var h = Changed; if (h != null && !exiting) h(); }

    // Игра: пока слушаем клиент — верим событиям, иначе тому, что сказало ядро.
    public static bool IsGame() { return Events != null && Events.ClientUp ? Events.GameRunning : Cur.Game; }

    // ── очередь вызовов ядра: по одному ──
    public static void Post(Action a) { lock (queue) queue.Enqueue(a); wake.Set(); }
    static void Worker() {
        while (true) {
            Action a = null;
            lock (queue) if (queue.Count > 0) a = queue.Dequeue();
            if (a == null) { wake.WaitOne(); continue; }
            try { a(); } catch (Exception e) { Dbg.Log("задача: " + e.Message); }
        }
    }

    public static void RefreshState() {
        lock (queue) { if (stateQueued) return; stateQueued = true; }
        Post(() => {
            lock (queue) stateQueued = false;
            var d = Json.Parse(Core.Run("state", null, 60000));
            Ui.BeginInvoke(new Action(() => ApplyState(d)));
        });
    }

    static void ApplyState(Dictionary<string, object> d) {
        if (d != null) { Cur = State.From(d); HaveState = true; if (Cur.Lang == "ru" || Cur.Lang == "en") L.En = Cur.Lang == "en"; }
        else if (!HaveState) Cur.Error = L.T("Не получилось связаться с VALSET. Перезапусти", "VALSET did not respond. Restart it");
        StateAt = DateTime.Now;
        Raise();
        Upd.TryStart();   // одна проверка обновлений за запуск — Update.cs
    }

    // Вход в аккаунт (или клиент уже был открыт): проверка ядром, потом состояние.
    static void OnLogin() {
        Post(() => { Core.Run("watch", null, 120000); });
        RefreshState();
    }

    static void OnGameClosed(string token) {
        Raise();
        Post(() => { Core.Run("watch -AfterGame", token, 180000); });
        RefreshState();
    }

    // Выбор агента (событие клиента, без опроса): ядро смотрит, зафиксирован ли агент, и надевает его набор (sets.ps1).
    // По матчу — пока ядро не скажет done (агент зафиксирован); события во время вызова — ещё один вызов после него.
    static string pregameDone = "", pregameAgain = null;
    static bool pregameBusy;
    static void OnPregame(string match) {
        if (!Cur.SetsAuto || match == pregameDone) return;
        if (pregameBusy) { pregameAgain = match; return; }
        pregameBusy = true; pregameAgain = null;
        Post(() => {
            var d = Json.Parse(Core.Run("do loadoutauto", null, 90000));
            Ui.BeginInvoke(new Action(() => {
                pregameBusy = false;
                if (d != null && Json.Bool(d, "done")) pregameDone = match;
                if (d != null && Json.Bool(d, "applied") && !Busy) {
                    ResultOk = Json.Bool(d, "ok"); ResultUndo = Json.Bool(d, "undo"); ResultMsg = Json.Str(d, "message");
                    Lists.Reset(); Raise();
                }
                string again = pregameAgain; pregameAgain = null;
                if (again != null) OnPregame(again);
            }));
        });
    }

    // Пока идёт действие — строка состояния ядра (повторы запросов к Riot, cloud.ps1): ядро в памяти приложения
    // пишет её в переменную процесса VALSET_STATUS. Таймер работает только пока Busy.
    public static string BusyStatus = "";
    static DispatcherTimer statusTimer;
    static void WatchStatus() {
        if (statusTimer == null) {
            statusTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
            statusTimer.Tick += (s, e) => {
                string t = Busy ? (Environment.GetEnvironmentVariable("VALSET_STATUS") ?? "") : "";
                if (!Busy) statusTimer.Stop();
                if (t != BusyStatus) { BusyStatus = t; Raise(); }
            };
        }
        BusyStatus = ""; statusTimer.Start();
    }

    // Действие из панели/тоста. show — показать панель с результатом.
    public static void DoAction(string act, bool show) {
        if (Busy) return;
        Busy = true; ResultMsg = null; WatchStatus();
        if (show) Panel.ShowPanel();
        Raise();
        Post(() => {
            var d = Json.Parse(Core.Run("do " + act, null, 180000));
            Ui.BeginInvoke(new Action(() => {
                Busy = false; Lists.Reset();
                if (d == null) { ResultOk = false; ResultUndo = false; ResultMsg = L.T("Не получилось связаться с VALSET. Перезапусти", "VALSET did not respond. Restart it"); }
                else {
                    ResultOk = Json.Bool(d, "ok"); ResultUndo = Json.Bool(d, "undo");
                    ResultMsg = Json.Str(d, "message");
                    if (Json.Bool(d, "queued") && ResultMsg.Length == 0) ResultMsg = L.T("Перенесётся после выхода из игры", "Will apply after the game closes");
                    string code = Json.Str(d, "code");   // «Поделиться»: код в буфер обмена (буфер — только из потока интерфейса)
                    if (ResultOk && code.Length > 0) {
                        try { Clipboard.SetText(code); }
                        catch (Exception e) { Dbg.Log("буфер: " + e.Message); ResultOk = false; ResultMsg = L.T("Не удалось скопировать код. Попробуй ещё раз", "Could not copy the code. Try again"); }
                    }
                    string text = Json.Str(d, "text");   // «Сообщить об ошибке»: диагностика в буфер, форма issue — в браузере
                    if (ResultOk && act == "report" && text.Length > 0) { string err = BugReport.Open(text); if (err != null) { ResultOk = false; ResultMsg = err; } }
                }
                Raise();
                if (show && !Panel.IsVisible) Panel.ShowPanel();
            }));
            RefreshState();
        });
    }

    // Аргумент второго запуска / кнопки тоста: valset:<действие>; ссылки valset:code/<код>, valset:pro/<ник> — предпросмотр.
    public static void Handle(string arg) {
        string a = (arg ?? "").Trim();
        if (a.StartsWith("valset:", StringComparison.OrdinalIgnoreCase)) a = a.Substring(7);
        int q = a.IndexOf('?'); if (q >= 0) a = a.Substring(0, q);
        a = a.Trim('/', ' ');
        // valset:code/<код> и valset:pro/<ник> — только предпросмотр; записать — кнопкой в нём
        int sl = a.IndexOf('/');
        if (sl > 0) {
            string kind = a.Substring(0, sl).ToLowerInvariant(), val = a.Substring(sl + 1);
            try { val = Uri.UnescapeDataString(val); } catch { }
            val = val.Trim('/', ' ');
            if (kind == "code") { string c = Share.Clean(val.IndexOf("VALSET", StringComparison.OrdinalIgnoreCase) >= 0 ? val : "VALSET2:" + val); if (c != null) { Share.Open("code", c); return; } }
            if (kind == "pro" && val.Length > 0 && val.IndexOfAny(new[] { ' ', '"', '&', '|', '<', '>', '^', '%' }) < 0) { Share.Open("pro", val); return; }
        }
        a = a.ToLowerInvariant();
        if (a == "skins") { Panel.ShowSkins(null); return; }   // valset:skins — «Все скины»
        if (Array.IndexOf(Actions, a) >= 0) DoAction(a, true);
        else Panel.ShowPanel();
    }

    public static void Exit() {
        exiting = true;
        try { if (Events != null) Events.Stop(); } catch { }
        try { Badge.Dispose(); } catch { }
        try { Overlay.Dispose(); } catch { }
        try { Tray.Dispose(); } catch { }
        App.Shutdown();
    }

    public static void SetBadge(bool on) {
        Config.SetBool("badge", on); Cur.Badge = on; Raise(); RefreshState();
    }

    // ── статус для трея, панели и значка ──
    public static Status GetStatus() {
        var s = Cur;
        Func<uint, string, Status> mk = (c, t) => new Status { Color = c, Text = t };
        if (!HaveState) return mk(Gray, s.Error.Length > 0 ? s.Error : L.T("Проверяю…", "Checking…"));
        if (!s.Client) return mk(Gray, L.T("Клиент Riot закрыт", "Riot Client is closed"));
        if (IsGame()) return mk(Blue, L.T("Идёт игра", "Game in progress"));
        if (s.Pending) return mk(Blue, L.T("Ждёт выхода из игры", "Waiting for the game to close"));
        if (s.Account.Length == 0) return mk(Gray, s.Error.Length > 0 ? s.Error : L.T("Нет входа в аккаунт", "Not logged in"));
        if (s.Suggested == "untemp") return mk(Amber, L.T("Исходные ждут возврата", "Originals are waiting to be restored"));
        if (s.Same == false) return mk(Amber, L.T("Не твои настройки: ", "Not your settings: ") + L.Plural(Math.Max(1, s.Diff), "отличие", "отличия", "отличий", "difference", "differences"));
        if (s.Suggested == "save") return mk(Amber, L.T("Есть несохранённые правки", "Unsaved changes"));
        if (s.Suggested == "apply") return mk(Amber, L.T("Настройки не твои", "Not your settings"));
        if (s.Error.Length > 0) return mk(Gray, s.Error);
        return mk(Green, s.Temp ? L.T("Твои настройки на время", "Your settings, for now") : L.T("Настройки твои", "Your settings"));
    }
}
