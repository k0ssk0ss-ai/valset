// Overlay.cs — кнопка «VALSET · скины» поверх игры: отдельное окно поверх всех (WS_EX_TOPMOST), без фокуса
// (WS_EX_NOACTIVATE) и без кнопки в панели задач (WS_EX_TOOLWINDOW). В игру не внедряемся, её память и файлы не трогаем
// (Vanguard) — только читаем режим экрана из GameUserSettings.ini. Видна, когда окно VALORANT на переднем плане и игрок
// в меню (присутствие в чате Riot, RiotEvents.LoopState = MENUS); в выборе агента и в матче — скрыта.
// Передний план — SetWinEventHook(EVENT_SYSTEM_FOREGROUND), только пока игра запущена; таймеров нет.
// Режим «Полноэкранный» (FullscreenMode 0): чужое окно с фокусом сворачивает игру — кнопку не показываем,
// вместо неё горячая клавиша Ctrl+Alt+S (в меню игры) и одноразовая подсказка в «Все скины».
using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

class OverlayWin : IDisposable {
    const int HotId = 0x5653;                         // «VS»
    const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_NOREPEAT = 0x4000, VK_S = 0x53;
    Window w; IntPtr h, fgHook, game;
    Native.WinEventProc proc;                         // делегат держим, иначе его соберёт GC
    HwndSource hot; bool hotOn;
    uint gamePid; bool fgGame;
    static readonly uint Self = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
    public static int FsMode = -1;                    // режим экрана игры: 0 — полноэкранный, 1 — оконный полноэкранный, 2 — в окне; -1 — неизвестно

    public OverlayWin() { proc = OnForeground; }

    // Включена ли кнопка: выбор в настройках, иначе — по режиму экрана (только если безопасно).
    public static bool Enabled() { return Ctl.Cur.Overlay ?? (FsMode >= 1); }
    public static bool Safe() { return FsMode >= 1; }

    // Режим экрана: GameUserSettings.ini аккаунта (LastConfirmedFullscreenMode, иначе FullscreenMode / PreferredFullscreenMode).
    public static void ReadFsMode() {
        int mode = -1;
        try {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VALORANT\\Saved\\Config");
            string pu = Ctl.Cur.Puuid;
            var dirs = Directory.GetDirectories(root).Select(d => new DirectoryInfo(d))
                .Where(d => pu.Length > 0 ? d.Name.StartsWith(pu + "-", StringComparison.OrdinalIgnoreCase) : d.Name.Length > 37)
                .Select(d => Path.Combine(d.FullName, "WindowsClient\\GameUserSettings.ini")).Where(File.Exists)
                .OrderByDescending(File.GetLastWriteTime).ToList();
            if (dirs.Count > 0) {
                var lines = File.ReadAllLines(dirs[0]);
                foreach (var key in new[] { "LastConfirmedFullscreenMode=", "FullscreenMode=", "PreferredFullscreenMode=" }) {
                    var l = lines.FirstOrDefault(x => x.StartsWith(key));
                    int v; if (l != null && int.TryParse(l.Substring(key.Length).Trim(), out v)) { mode = v; break; }
                }
            }
        } catch (Exception e) { Dbg.Log("режим экрана: " + e.Message); }
        if (mode != FsMode) Dbg.Log("режим экрана игры: " + mode);
        FsMode = mode;
    }

    // ── окно кнопки ──
    void Ensure() {
        if (w != null) return;
        var t = new TextBlock { Text = "VALSET · " + L.T("скины", "skins"), FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White };
        var pill = new Border {
            Child = t, CornerRadius = new CornerRadius(13), Padding = new Thickness(12, 5, 12, 6), Cursor = Cursors.Hand,
            Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x20, 0x20, 0x20)), BorderBrush = Ui.Br(0x3D8BFD), BorderThickness = new Thickness(1)
        };
        pill.MouseLeftButtonUp += (s, e) => Click();
        w = new Window {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false,
            ShowActivated = false, Topmost = true, ResizeMode = ResizeMode.NoResize, SizeToContent = SizeToContent.WidthAndHeight,
            Content = pill, FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"), Left = -10000, Top = -10000
        };
        w.Closed += (s, e) => { w = null; h = IntPtr.Zero; };
        h = new WindowInteropHelper(w).EnsureHandle();
        Native.AddExStyle(h, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
    }

    void Click() {
        Native.RECT r; Native.GetWindowRect(h, out r);
        Ctl.Panel.ShowSkins(new System.Drawing.Rectangle(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top));
    }

    void HideBtn() { if (w != null && w.IsVisible) w.Hide(); }

    // Слева по центру окна игры: в меню VALORANT там пусто (вкладки — сверху, друзья — справа, чат — снизу слева).
    void ShowBtn() {
        Native.RECT r;
        if (game == IntPtr.Zero || !Native.IsWindow(game) || Native.IsIconic(game) || !Native.GetWindowRect(game, out r) || r.Right - r.Left < 400) { HideBtn(); return; }
        Ensure();
        if (!w.IsVisible) w.Show();
        w.UpdateLayout();
        Native.RECT b; Native.GetWindowRect(h, out b);
        var src = PresentationSource.FromVisual(w);
        double sc = src != null ? src.CompositionTarget.TransformToDevice.M11 : 1;
        int x = r.Left + (int)Math.Round(14 * sc), y = r.Top + (r.Bottom - r.Top) / 2 - (b.Bottom - b.Top) / 2;
        Native.SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
    }

    // Вызывается при любом изменении состояния (Ctl.Changed) и при смене LoopState.
    public void Update() {
        bool running = Ctl.IsGame();
        Hotkey(running);
        if (!running) { Unhook(); fgGame = false; game = IntPtr.Zero; gamePid = 0; HideBtn(); return; }
        if (!Enabled() || !Safe()) { Unhook(); HideBtn(); return; }
        if (fgHook == IntPtr.Zero) {
            fgHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, proc, 0, 0, 0);
            Check(Native.GetForegroundWindow());
        }
        if (fgGame && Ctl.Events.LoopState == "MENUS") ShowBtn(); else HideBtn();
    }

    void Unhook() { if (fgHook != IntPtr.Zero) { Native.UnhookWinEvent(fgHook); fgHook = IntPtr.Zero; } }

    // Окно на переднем плане — игра? Своё окно (панель) — состояние не меняем.
    void Check(IntPtr fg) {
        if (fg == IntPtr.Zero) return;
        uint pid; Native.GetWindowThreadProcessId(fg, out pid);
        if (pid == Self) return;
        bool isGame = pid == gamePid;
        if (!isGame) {
            try { using (var p = System.Diagnostics.Process.GetProcessById((int)pid)) isGame = p.ProcessName == "VALORANT-Win64-Shipping"; } catch { }
            if (isGame) gamePid = pid;
        }
        fgGame = isGame;
        if (isGame) game = fg;
    }

    // Колбэк в потоке интерфейса (WINEVENT_OUTOFCONTEXT).
    void OnForeground(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) {
        bool was = fgGame;
        Check(hwnd);
        if (fgGame != was || fgGame) Update();
    }

    // ── горячая клавиша Ctrl+Alt+S: только пока игра запущена ──
    void Hotkey(bool on) {
        if (on == hotOn) return;
        if (hot == null) {
            hot = new HwndSource(new HwndSourceParameters("valset-hotkey") { ParentWindow = new IntPtr(-3) });   // окно только для сообщений
            hot.AddHook(HotProc);
        }
        if (on) hotOn = Native.RegisterHotKey(hot.Handle, HotId, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_S);
        else { Native.UnregisterHotKey(hot.Handle, HotId); hotOn = false; }
        Dbg.Log("горячая клавиша Ctrl+Alt+S: " + (on ? (hotOn ? "есть" : "занята") : "снята"));
        if (on && !hotOn) hotOn = true;   // занята другой программой — не пытаться на каждом обновлении
    }

    IntPtr HotProc(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled) {
        if (msg == 0x0312 && wp.ToInt32() == HotId) {   // WM_HOTKEY
            handled = true;
            string loop = Ctl.Events != null ? Ctl.Events.LoopState : "";
            if (Ctl.IsGame() && loop != "MENUS") { Dbg.Log("Ctrl+Alt+S: не в меню (" + loop + ") — пропуск"); return IntPtr.Zero; }
            Ctl.Panel.ShowSkins(null);
        }
        return IntPtr.Zero;
    }

    public void Dispose() {
        Unhook();
        if (hot != null) { if (hotOn) Native.UnregisterHotKey(hot.Handle, HotId); hot.Dispose(); hot = null; }
        if (w != null) { try { w.Close(); } catch { } }
    }
}
