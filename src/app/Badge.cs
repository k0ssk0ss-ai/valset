// Badge.cs — значок у окна клиента Riot: маленькая «таблетка» в правом нижнем углу окна клиента.
// Окно значка принадлежит окну клиента (владелец) — оно над клиентом, но не над другими окнами и игрой.
// За положением следим через SetWinEventHook; в процесс клиента не лезем, память его не читаем.
using System;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

class BadgeWin : IDisposable {
    Window w;
    Ellipse dot; TextBlock txt;
    IntPtr client, badgeH, hookA, hookB;
    Native.WinEventProc proc;                 // делегат держим, иначе его соберёт GC
    DispatcherTimer scan; int scanTicks;

    public BadgeWin() { proc = OnEvent; }

    // ── окно значка ──
    void Ensure() {
        if (w != null) return;
        dot = new Ellipse { Width = 8, Height = 8, Margin = new Thickness(0, 0, 7, 0), VerticalAlignment = VerticalAlignment.Center };
        txt = new TextBlock { FontSize = 12, Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(dot); row.Children.Add(txt);
        var pill = new Border {
            Child = row, CornerRadius = new CornerRadius(12), Padding = new Thickness(11, 5, 12, 6), Cursor = Cursors.Hand,
            Background = new SolidColorBrush(Color.FromArgb(0xEE, 0x20, 0x20, 0x20)), BorderBrush = Ui.Br(0x3A3A3A), BorderThickness = new Thickness(1)
        };
        pill.MouseLeftButtonUp += (s, e) => { Native.RECT bb; Native.GetWindowRect(badgeH, out bb); Ctl.Panel.Toggle(new System.Drawing.Rectangle(bb.Left, bb.Top, bb.Right - bb.Left, bb.Bottom - bb.Top)); };
        w = new Window {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ShowInTaskbar = false,
            ShowActivated = false, Topmost = false, ResizeMode = ResizeMode.NoResize, SizeToContent = SizeToContent.WidthAndHeight,
            Content = pill, FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"), Left = -10000, Top = -10000
        };
        w.Closed += (s, e) => { w = null; badgeH = IntPtr.Zero; };   // владелец уничтожен — система закрыла и значок
        badgeH = new WindowInteropHelper(w).EnsureHandle();
        Native.AddExStyle(badgeH, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
    }

    // Что показывать: null — спрятать.
    static string TextFor(State s, out uint color) {
        color = Ctl.Green;
        if (Ctl.IsGame() || !s.Client || s.Account.Length == 0) return null;
        if (s.Pending) { color = Ctl.Blue; return "● " + L.T("ждёт выхода из игры", "waiting for game exit"); }
        if (s.Suggested == "untemp") { color = Ctl.Amber; return "! " + L.T("вернуть исходные", "restore originals"); }
        if (s.Suggested == "save") { color = Ctl.Amber; return "! " + L.T("есть правки: сохранить", "changes: save"); }
        if (s.Suggested == "apply" || s.Same == false) { color = Ctl.Amber; return "! " + L.T("не твои: перенести", "not yours: apply"); }
        if (s.Suggested.Length > 0) return null;
        return "✓ VALSET · " + L.T("настройки твои", "settings are yours");
    }

    // Вызывается при любом изменении состояния.
    public void Update() {
        var s = Ctl.Cur; uint color = Ctl.Green;
        Dbg.Log("значок: Update badge=" + s.Badge + " client=" + s.Client + " acc=" + s.Account);
        string text = s.Badge ? TextFor(s, out color) : null;
        if (!s.Badge || !s.Client) { Untrack(); StopScan(); HideBadge(); return; }
        if (client == IntPtr.Zero || !Native.IsWindow(client)) { Untrack(); StartScan(); }
        if (text == null) { HideBadge(); return; }
        Ensure();
        if (client != IntPtr.Zero) Native.SetOwner(badgeH, client);
        txt.Text = text; dot.Fill = Ui.Br(color);
        Refit();
    }

    void HideBadge() { if (w != null && w.IsVisible) w.Hide(); }

    // Показать/спрятать и поставить в угол по текущему положению окна клиента.
    void Refit() {
        if (w == null) return;
        Native.RECT r;
        bool ok = client != IntPtr.Zero && Native.IsWindow(client) && Native.IsWindowVisible(client) && !Native.IsIconic(client)
                  && Native.GetWindowRect(client, out r) && (r.Right - r.Left) > 200;
        if (!ok || Ctl.IsGame()) { HideBadge(); return; }
        Native.GetWindowRect(client, out r);
        if (!w.IsVisible) { Native.SetOwner(badgeH, client); w.Show(); }
        w.UpdateLayout();
        Native.RECT b; Native.GetWindowRect(badgeH, out b);
        Dbg.Log("значок: размер " + (b.Right - b.Left) + "x" + (b.Bottom - b.Top) + " owner-ok=" + (Native.IsWindowVisible(badgeH)));
        var src = PresentationSource.FromVisual(w);
        double sc = src != null ? src.CompositionTarget.TransformToDevice.M11 : 1;
        int inset = (int)Math.Round(16 * sc);
        int x = r.Right - (b.Right - b.Left) - inset, y = r.Bottom - (b.Bottom - b.Top) - inset;
        Native.SetWindowPos(badgeH, IntPtr.Zero, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
        Dbg.Log("значок: клиент " + client + " [" + r.Left + "," + r.Top + "," + r.Right + "," + r.Bottom + "] -> " + x + "," + y);
    }

    // ── поиск окна клиента ──
    // Видимое окно верхнего уровня «Riot Client» процесса «Riot Client».
    public static IntPtr FindClientWindow() {
        IntPtr found = IntPtr.Zero;
        Native.EnumWindows((h, l) => {
            if (!Native.IsWindowVisible(h)) return true;
            var sb = new StringBuilder(64);
            Native.GetWindowText(h, sb, 64);
            if (sb.ToString() != "Riot Client") return true;
            uint pid; Native.GetWindowThreadProcessId(h, out pid);
            try {
                using (var p = System.Diagnostics.Process.GetProcessById((int)pid))
                    if (p.ProcessName == "Riot Client") { found = h; return false; }
            } catch { }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    void StartScan() {
        if (scan != null && scan.IsEnabled) return;
        if (scan == null) { scan = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) }; scan.Tick += (s, e) => ScanTick(); }
        scanTicks = 0; scan.Interval = TimeSpan.FromSeconds(1); scan.Start();
        ScanTick();
    }
    void StopScan() { if (scan != null) scan.Stop(); }

    void ScanTick() {
        if (!Ctl.Cur.Badge || !Ctl.Cur.Client) { StopScan(); return; }
        scanTicks++;
        if (scanTicks == 60) scan.Interval = TimeSpan.FromSeconds(5);   // дальше реже: клиент мог стартовать свёрнутым в трей
        var h = FindClientWindow();
        Dbg.Log("поиск окна клиента: " + (h == IntPtr.Zero ? "нет" : "hwnd " + h));
        if (h == IntPtr.Zero) return;
        StopScan();
        Track(h);
        Update();
    }

    // ── слежение за окном клиента ──
    void Track(IntPtr h) {
        Untrack();
        client = h;
        uint pid; Native.GetWindowThreadProcessId(h, out pid);
        hookA = Native.SetWinEventHook(Native.EVENT_SYSTEM_MINIMIZESTART, Native.EVENT_SYSTEM_MINIMIZEEND, IntPtr.Zero, proc, pid, 0, 0);
        hookB = Native.SetWinEventHook(Native.EVENT_OBJECT_DESTROY, Native.EVENT_OBJECT_LOCATIONCHANGE, IntPtr.Zero, proc, pid, 0, 0);
    }

    void Untrack() {
        if (hookA != IntPtr.Zero) { Native.UnhookWinEvent(hookA); hookA = IntPtr.Zero; }
        if (hookB != IntPtr.Zero) { Native.UnhookWinEvent(hookB); hookB = IntPtr.Zero; }
        client = IntPtr.Zero;
    }

    // Колбэк приходит в потоке интерфейса (WINEVENT_OUTOFCONTEXT).
    void OnEvent(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) {
        if (hwnd != client || idObject != 0) return;
        Dbg.Log("значок: событие " + ev.ToString("X"));
        switch (ev) {
            case Native.EVENT_OBJECT_LOCATIONCHANGE:
            case Native.EVENT_SYSTEM_MINIMIZEEND:
            case Native.EVENT_OBJECT_SHOW:
                Refit(); break;
            case Native.EVENT_SYSTEM_MINIMIZESTART:
            case Native.EVENT_OBJECT_HIDE:
                HideBadge(); break;
            case Native.EVENT_OBJECT_DESTROY:
                Untrack(); HideBadge();
                if (Ctl.Cur.Badge && Ctl.Cur.Client) StartScan();
                break;
        }
    }

    public void Dispose() {
        Untrack(); StopScan();
        if (w != null) { try { w.Close(); } catch { } }
    }
}
