// Panel.cs — панель у часов (WPF кодом, без XAML): аккаунт, статус, одна большая кнопка, «Про · Ещё · ⚙».
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;

class PanelWin : Window {
    const double Shadow = 14, CardW = 340, Gap = 12;
    readonly Border card = new Border();
    DateTime hiddenAt = DateTime.MinValue;

    public static SolidColorBrush Br(uint rgb) {
        var b = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)); b.Freeze(); return b;
    }

    public PanelWin() {
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; Topmost = true; ResizeMode = ResizeMode.NoResize; ShowActivated = true;
        SizeToContent = SizeToContent.Height; Width = CardW + 2 * Shadow;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"); UseLayoutRounding = true;
        card.Margin = new Thickness(Shadow); card.Background = Br(0x202020); card.BorderBrush = Br(0x3A3A3A);
        card.BorderThickness = new Thickness(1); card.CornerRadius = new CornerRadius(8); card.Padding = new Thickness(16);
        card.Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Opacity = 0.45, Color = Colors.Black };
        Content = card;
        Deactivated += (s, e) => HidePanel();
        KeyDown += (s, e) => { if (e.Key == Key.Escape) HidePanel(); };
        Closing += (s, e) => { e.Cancel = true; HidePanel(); };
    }

    public void Toggle() {
        if (IsVisible) HidePanel();
        else if ((DateTime.Now - hiddenAt).TotalMilliseconds > 300) ShowPanel();   // клик по иконке сам снял фокус — это «закрыть»
    }

    public void HidePanel() {
        if (!IsVisible) return;
        hiddenAt = DateTime.Now;
        if (!Ctl.Busy) Ctl.ResultMsg = null;
        Hide();
    }

    public void ShowPanel() {
        if (Ctl.StateAt < DateTime.Now.AddSeconds(-10)) Ctl.RefreshState();
        Build();
        if (IsVisible) { Activate(); return; }
        Opacity = 0; Show(); UpdateLayout();
        Place(true);
        Activate(); Native.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(this).Handle);
    }

    // Перерисовать, если открыта (низ панели остаётся у часов).
    public void Refresh() {
        if (!IsVisible) return;
        Build();
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => Place(false)));
    }

    // Внизу справа над панелью задач; задачи на другом краю — к этому краю.
    void Place(bool animate) {
        var wa = SystemParameters.WorkArea;
        double sw = SystemParameters.PrimaryScreenWidth, sh = SystemParameters.PrimaryScreenHeight;
        double x = wa.Left > 0 ? wa.Left + Gap - Shadow : wa.Right - Gap - Width + Shadow;
        double y = (wa.Top > 0 && wa.Bottom >= sh) ? wa.Top + Gap - Shadow : wa.Bottom - Gap - ActualHeight + Shadow;
        BeginAnimation(TopProperty, null);
        Left = x; Top = y;
        if (!animate) return;
        bool fromTop = wa.Top > 0 && wa.Bottom >= sh;
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        BeginAnimation(TopProperty, new DoubleAnimation(y + (fromTop ? -10 : 10), y, TimeSpan.FromMilliseconds(170)) { EasingFunction = ease });
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(140)));
    }

    // ── содержимое ──
    static TextBlock Tb(string text, double size, uint color, FontWeight? weight) {
        var t = new TextBlock { Text = text, FontSize = size, Foreground = Br(color), TextWrapping = TextWrapping.Wrap };
        if (weight.HasValue) t.FontWeight = weight.Value;
        return t;
    }

    // Кнопка из Border: тема задаётся кодом, без шаблонов.
    static Border Btn(string text, double size, uint fg, uint bg, uint hover, bool enabled, Action click, double height, double radius) {
        var tb = Tb(text, size, fg, FontWeights.SemiBold);
        tb.HorizontalAlignment = HorizontalAlignment.Center; tb.VerticalAlignment = VerticalAlignment.Center;
        var b = new Border { Child = tb, Background = bg == 0 ? Brushes.Transparent : (Brush)Br(bg), CornerRadius = new CornerRadius(radius), Height = height, Padding = new Thickness(10, 0, 10, 0) };
        if (enabled) {
            b.Cursor = Cursors.Hand;
            b.MouseEnter += (s, e) => b.Background = Br(hover);
            b.MouseLeave += (s, e) => b.Background = bg == 0 ? Brushes.Transparent : (Brush)Br(bg);
            b.MouseLeftButtonUp += (s, e) => { if (click != null) click(); };
        }
        return b;
    }

    void Build() {
        var s = Ctl.Cur; var st = Ctl.GetStatus();
        var sp = new StackPanel();
        sp.Children.Add(Tb("VALSET", 11, 0x9A9A9A, FontWeights.SemiBold));
        var acc = Tb(s.Account.Length > 0 ? s.Account : "—", 20, 0xFFFFFF, FontWeights.SemiBold);
        acc.Margin = new Thickness(0, 2, 0, 0); acc.TextTrimming = TextTrimming.CharacterEllipsis; acc.TextWrapping = TextWrapping.NoWrap;
        sp.Children.Add(acc);

        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        row.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = Br(st.Color), Margin = new Thickness(0, 1, 8, 0), VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(Tb(st.Text, 13, 0xE0E0E0, null));
        sp.Children.Add(row);

        if (s.Synced.Count > 0) {
            var n = Tb(L.T("Из игры сохранено: ", "Saved from the game: ") + string.Join(", ", s.Synced.ToArray()), 12, 0x9A9A9A, null);
            n.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(n);
        }
        if (s.Error.Length > 0 && Ctl.HaveState) {
            var n = Tb(s.Error, 12, 0xE0A100, null); n.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(n);
        }

        sp.Children.Add(MainButton(s));

        if (Ctl.ResultMsg != null && !Ctl.Busy) {
            var m = Tb(Ctl.ResultMsg, 12.5, 0xE0E0E0, null); m.Margin = new Thickness(0, 10, 0, 0); sp.Children.Add(m);
            var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
            r.Children.Add(Tb(Ctl.ResultOk ? L.T("Готово", "Done") : L.T("Не вышло", "Failed"), 12.5, Ctl.ResultOk ? 0x3BA55Cu : 0xE0A100u, FontWeights.SemiBold));
            if (Ctl.ResultUndo) {
                r.Children.Add(Tb("  ·  ", 12.5, 0x777777, null));
                var u = Tb(L.T("Отменить", "Undo"), 12.5, 0x60A5FF, FontWeights.SemiBold);
                u.Cursor = Cursors.Hand; u.MouseLeftButtonUp += (a, b) => Ctl.DoAction("undo", false);
                r.Children.Add(u);
            }
            sp.Children.Add(r);
        }

        sp.Children.Add(new Border { Height = 1, Background = Br(0x333333), Margin = new Thickness(0, 14, 0, 6) });
        var bot = new Grid();
        for (int i = 0; i < 3; i++) bot.ColumnDefinitions.Add(new ColumnDefinition());
        AddSmall(bot, 0, L.T("Про", "Pros"), () => { HidePanel(); Core.Console("pros"); });
        AddSmall(bot, 1, L.T("Ещё", "More"), () => { HidePanel(); Core.Console("more"); });
        AddSmall(bot, 2, "⚙", () => { HidePanel(); Ctl.Tray.ShowMenuAtCursor(); });
        sp.Children.Add(bot);
        card.Child = sp;
    }

    static void AddSmall(Grid g, int col, string text, Action click) {
        var b = Btn(text, 13, 0xC8C8C8, 0, 0x2E2E2E, true, click, 30, 5);
        b.Margin = new Thickness(col == 0 ? 0 : 2, 0, col == 2 ? 0 : 2, 0);
        Grid.SetColumn(b, col); g.Children.Add(b);
    }

    // Одна большая кнопка по ситуации (state.suggested).
    static Border MainButton(State s) {
        string text; Action act = null; bool on = true;
        if (Ctl.Busy) { text = "…"; on = false; }
        else switch (s.Suggested) {
            case "save": text = L.T("Сохранить", "Save"); act = () => Ctl.DoAction("save", false); break;
            case "apply": text = L.T("Применить мои", "Apply mine"); act = () => Ctl.DoAction("apply", false); break;
            case "untemp": text = L.T("Вернуть исходные", "Restore originals"); act = () => Ctl.DoAction("untemp", false); break;
            case "client": text = L.T("Открыть клиент Riot", "Open Riot Client"); act = Core.OpenRiotClient; break;
            default: text = L.T("Всё твоё ✓", "All yours ✓"); on = false; break;
        }
        var b = Btn(text, 14, on ? 0xFFFFFFu : 0x8A8A8Au, on ? 0x3D8BFDu : 0x333333u, 0x5A9DFE, on, act, 40, 6);
        b.Margin = new Thickness(0, 14, 0, 0);
        return b;
    }
}
