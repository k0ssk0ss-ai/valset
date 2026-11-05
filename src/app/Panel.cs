// Panel.cs — панель: оболочка, навигация по страницам, позиция (у часов, рядом со значком у клиента или с кнопкой поверх игры).
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

class PanelWin : Window {
    const double Shadow = 14, NarrowW = 380, WideW = 740, WideH = 600, Gap = 12, ListMax = 440;
    public const string Home = "home";
    readonly Border card = new Border();
    readonly Stack<string> nav = new Stack<string>();
    ScrollViewer sv;
    public ScrollViewer Scroller { get { return sv; } }   // для самопроверки (SelfTest.cs)
    DateTime hiddenAt = DateTime.MinValue;
    System.Drawing.Rectangle? anchor;   // значок у клиента, пиксели экрана; null — у часов
    public string Page = Home;
    public bool ResetScroll;            // следующая перерисовка — с начала списка (вкладка, поиск)
    // «Все скины» и всё, что открыто из них (предпросмотр, наборы), — в широком окне 740×600
    public bool Wide { get { if (Page.StartsWith("skins")) return true; foreach (var p in nav) if (p.StartsWith("skins")) return true; return false; } }
    double CardW { get { return Wide ? WideW : NarrowW; } }

    public PanelWin() {
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; Topmost = true; ResizeMode = ResizeMode.NoResize; ShowActivated = true;
        SizeToContent = SizeToContent.Height; Width = NarrowW + 2 * Shadow;
        FontFamily = Ui.Sans; UseLayoutRounding = true; TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        card.Margin = new Thickness(Shadow); card.Background = Ui.Br(Ui.Bg1); card.BorderBrush = Ui.Line;
        card.BorderThickness = new Thickness(1); card.CornerRadius = new CornerRadius(12);
        card.Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0.45, Color = Colors.Black };
        Content = card;
        Deactivated += (s, e) => HidePanel();
        KeyDown += (s, e) => { if (e.Key == Key.Escape) HidePanel(); };
        Closing += (s, e) => { e.Cancel = true; HidePanel(); };
    }

    // Клик по иконке трея (anchor == null) или по значку у клиента.
    public void Toggle() { Toggle(null); }
    public void Toggle(System.Drawing.Rectangle? at) {
        if (IsVisible) HidePanel();
        else if ((DateTime.Now - hiddenAt).TotalMilliseconds > 300) ShowPanel(at);   // клик по иконке сам снял фокус — это «закрыть»
    }

    public void HidePanel() {
        if (!IsVisible) return;
        hiddenAt = DateTime.Now;
        if (!Ctl.Busy) Ctl.ResultMsg = null;
        Hide();
        Img.Clear();   // картинки «Всех скинов» — из памяти; на диске остаются
    }

    // «Все скины»: кнопка поверх игры (at — её место) или Ctrl+Alt+S. Открыта на скинах — закрыть.
    public void ShowSkins(System.Drawing.Rectangle? at) {
        if (IsVisible && Page.StartsWith("skins")) { HidePanel(); return; }
        if (!IsVisible) ShowPanel(at);
        if (Page != "skins") Go("skins");
    }

    public void ShowPanel() { ShowPanel(null); }
    public void ShowPanel(System.Drawing.Rectangle? at) {
        if (Ctl.StateAt < DateTime.Now.AddSeconds(-10)) Ctl.RefreshState();
        if (IsVisible) { Activate(); return; }
        anchor = at;
        nav.Clear(); Page = Home; Lists.Reset();
        Build();
        Opacity = 0; Show(); UpdateLayout();
        Place(true);
        Activate(); Native.SetForegroundWindow(new System.Windows.Interop.WindowInteropHelper(this).Handle);
    }

    // Перерисовать текущую страницу, если открыта.
    public void Refresh() {
        if (!IsVisible) return;
        Build();
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => Place(false)));
    }

    public void Rebuild() { Build(); }   // для самопроверки

    // ── навигация ──
    public void Go(string page) {
        if (page == Page) return;
        nav.Push(Page); Page = page; ResetScroll = true;
        if (!Ctl.Busy) Ctl.ResultMsg = null;
        Lists.ResetView();
        Refresh();
    }

    public void Back() {
        Page = nav.Count > 0 ? nav.Pop() : Home;
        if (!Ctl.Busy) Ctl.ResultMsg = null;
        Lists.ResetView();
        Refresh();
    }

    // ── позиция ──
    double Scale() {
        var src = PresentationSource.FromVisual(this);
        return src != null ? src.CompositionTarget.TransformToDevice.M11 : 1;
    }

    void Place(bool animate) {
        double cardH = Math.Max(0, ActualHeight - 2 * Shadow), x, y;
        bool fromTop;
        if (anchor.HasValue) PlaceAtBadge(cardH, out x, out y, out fromTop);
        else PlaceAtClock(cardH, out x, out y, out fromTop);
        BeginAnimation(TopProperty, null);
        Left = x - Shadow; Top = y - Shadow;
        if (!animate) return;
        double top = y - Shadow;
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        BeginAnimation(TopProperty, new DoubleAnimation(top + (fromTop ? -10 : 10), top, TimeSpan.FromMilliseconds(170)) { EasingFunction = ease });
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(140)));
    }

    // Внизу справа над панелью задач; задачи на другом краю — к этому краю.
    void PlaceAtClock(double cardH, out double x, out double y, out bool fromTop) {
        var wa = SystemParameters.WorkArea;
        double sh = SystemParameters.PrimaryScreenHeight;
        x = wa.Left > 0 ? wa.Left + Gap : wa.Right - Gap - CardW;
        fromTop = wa.Top > 0 && wa.Bottom >= sh;
        y = fromTop ? wa.Top + Gap : wa.Bottom - Gap - cardH;
    }

    // Рядом со значком: над ним, правый край по значку; не влезает — под ним. Внутри рабочей области монитора окна клиента.
    void PlaceAtBadge(double cardH, out double x, out double y, out bool fromTop) {
        var a = anchor.Value; double k = Scale();
        var wp = System.Windows.Forms.Screen.FromRectangle(a).WorkingArea;
        double wl = wp.Left / k, wt = wp.Top / k, wr = wp.Right / k, wb = wp.Bottom / k;
        double al = a.Left / k, at = a.Top / k, ar = a.Right / k, ab = a.Bottom / k;
        x = Math.Max(wl + Gap, Math.Min(ar - CardW, wr - Gap - CardW));
        y = at - Gap - cardH; fromTop = false;
        if (y < wt + Gap) { y = ab + Gap; fromTop = true; }
        y = Math.Max(wt + Gap, Math.Min(y, wb - Gap - cardH));
    }

    // ── содержимое ──
    void Build() {
        double keep = 0;
        if (sv != null && card.Child != null && !ResetScroll) keep = sv.VerticalOffset;
        ResetScroll = false;
        Img.BeginPage();
        bool wide = Wide;
        Width = CardW + 2 * Shadow;
        if (wide) { SizeToContent = SizeToContent.Manual; Height = WideH + 2 * Shadow; } else SizeToContent = SizeToContent.Height;
        UIElement root;
        if (Page.StartsWith("skins")) root = Skins.Frame(out sv);   // своя раскладка: шапка, оружие слева, сцена и сетка (PagesStage.cs)
        else {
            var body = new StackPanel();
            sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = body };
            if (Page == Home) {
                Pages.Home(body);
                sv.MaxHeight = Math.Max(400, SystemParameters.WorkArea.Height - 2 * Gap - 2 * Shadow);
                root = sv;
            } else {
                var outer = new DockPanel { Margin = new Thickness(12, 12, 12, 12), LastChildFill = true };
                var top = new StackPanel();
                top.Children.Add(Header(Pages.Title(Page)));
                var r = Ui.Result(); if (r != null) top.Children.Add(r);
                top.Children.Add(Ui.Sep(8, 4));
                DockPanel.SetDock(top, Dock.Top); outer.Children.Add(top);
                Pages.Body(Page, body);
                if (!wide) sv.MaxHeight = ListMax;
                outer.Children.Add(sv);
                root = outer;
            }
        }
        var me = sv; sv.ScrollChanged += (s, e) => Img.Scan(me);   // картинки — только видимые
        card.Child = root;
        if (keep > 0) { sv.UpdateLayout(); sv.ScrollToVerticalOffset(keep); }
    }

    // Кнопка «назад»: значок, наведение — подложка bg3.
    public Border BackBtn() {
        var b = new Border { Child = Icons.Make("back", Ui.T2), Width = 28, Height = 28, CornerRadius = new CornerRadius(8), Background = Brushes.Transparent, Padding = new Thickness(6) };
        Ui.Hover(b, 0, Ui.Bg3, true, Back);
        return b;
    }

    // Шапка страницы: стрелка назад + заголовок.
    UIElement Header(string title) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.Children.Add(BackBtn());
        var t = Ui.Tb1(title, 15, Ui.T1, FontWeights.Medium);
        t.VerticalAlignment = VerticalAlignment.Center; t.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(t, 1); g.Children.Add(t);
        return g;
    }
}