// PagesStage.cs — оформление «Всех скинов» (широкое окно 740×600): шапка с вкладками и поиском, список оружия слева,
// сцена (большая картинка скина на фоне баннера коллекции), карточки сетки. Данные и действия — PagesSkins.cs / PagesColl.cs.
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

static class Stage {
    public const double RailW = 168;

    // Каркас: шапка сверху, слева — список (rail == null — без него), справа — прокручиваемая область.
    public static UIElement Frame(UIElement top, UIElement rail, out ScrollViewer pane, out StackPanel body) {
        var root = new DockPanel();
        var bar = new Border { Child = top, Height = 52, Padding = new Thickness(12, 0, 16, 0), BorderBrush = Ui.Line, BorderThickness = new Thickness(0, 0, 0, 1) };
        DockPanel.SetDock(bar, Dock.Top); root.Children.Add(bar);
        if (rail != null) {
            var rb = new Border { Child = rail, Width = RailW, BorderBrush = Ui.Line, BorderThickness = new Thickness(0, 0, 1, 0) };
            DockPanel.SetDock(rb, Dock.Left); root.Children.Add(rb);
        }
        body = new StackPanel { Margin = new Thickness(16) };
        pane = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        root.Children.Add(pane);
        return root;
    }

    // Список слева: прокручиваемые строки, внизу — закреплённая строка (foot).
    public static UIElement Rail(StackPanel rows, UIElement foot) {
        var d = new DockPanel();
        var fb = new Border { Child = foot, BorderBrush = Ui.Line, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(8) };
        DockPanel.SetDock(fb, Dock.Bottom); d.Children.Add(fb);
        rows.Margin = new Thickness(8);
        d.Children.Add(new ScrollViewer { Content = rows, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        return d;
    }

    // Шапка: назад, заголовок, сегменты, поиск справа.
    public static UIElement Top(string title, Border seg, UIElement search) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var back = Ctl.Panel.BackBtn(); back.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(back);
        var t = Ui.Tb1(title, 15, Ui.T1, FontWeights.Medium); t.VerticalAlignment = VerticalAlignment.Center; t.Margin = new Thickness(8, 0, 12, 0); t.MaxWidth = 150;
        Grid.SetColumn(t, 1); g.Children.Add(t);
        Grid.SetColumn(seg, 2); g.Children.Add(seg);
        Grid.SetColumn(search, 3); g.Children.Add(search);
        return g;
    }

    // Поле поиска: подложка bg0, значок, текст без рамки, подсказка «Поиск», пока пусто.
    public static UIElement Search(TextBox box) {
        var p = box.Parent as Panel; if (p != null) p.Children.Remove(box);
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.Children.Add(Icons.Make("search", Ui.T3));
        var ph = Ui.Tb1(L.T("Поиск", "Search"), 12, Ui.T3, null); ph.VerticalAlignment = VerticalAlignment.Center; ph.Margin = new Thickness(10, 0, 0, 0); ph.IsHitTestVisible = false;
        ph.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetColumn(ph, 1); g.Children.Add(ph);
        Grid.SetColumn(box, 1); g.Children.Add(box);
        return new Border { Child = g, Width = 140, Height = 30, Padding = new Thickness(10, 0, 8, 0), CornerRadius = new CornerRadius(8), Background = Ui.Br(Ui.Bg0),
                            BorderBrush = Ui.Line, BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
    }

    public static TextBox NewSearchBox() {
        return new TextBox { FontSize = 12, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Ui.Br(Ui.T1), CaretBrush = Ui.Br(Ui.T1),
                             VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0), Padding = new Thickness(0) };
    }

    // Строка списка слева: имя, справа — моно-счётчик; выбранная — bg3 и мятная черта 2 px.
    public static Border RailRow(string text, string count, bool on, uint color, Action click) {
        var g = new Grid { Height = 32 };
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var t = Ui.Tb1(text, 13, color, null); t.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(t);
        if (count.Length > 0) { var c = Ui.MonoTb(count, 11, Ui.T3); Grid.SetColumn(c, 1); g.Children.Add(c); }
        if (on) g.Children.Add(new Rectangle { Width = 2, Height = 14, RadiusX = 1, RadiusY = 1, Fill = Ui.Br(Ui.Acc), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(-6, 0, 0, 0) });
        var b = new Border { Child = g, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 0, 8, 0), Background = on ? Ui.Br(Ui.Bg3) : Brushes.Transparent };
        Ui.Hover(b, on ? Ui.Bg3 : 0, Ui.Bg3, true, click);
        return b;
    }

    // ── сцена ──
    // banner — картинка коллекции (нет — тёмная сцена); hero — картинка скина; info — имя и подпись; controls — справа внизу;
    // chips — цвета и уровни: строкой над подписью, справа.
    public static UIElement Make(double h, string banner, UIElement hero, string tag, bool equipped, UIElement info, UIElement controls) { return Make(h, banner, hero, tag, equipped, info, controls, null); }
    public static UIElement Make(double h, string banner, UIElement hero, string tag, bool equipped, UIElement info, UIElement controls, UIElement chips) {
        var g = new Grid { Height = h, ClipToBounds = true };
        var bg = new RadialGradientBrush { Center = new Point(0.5, 1), GradientOrigin = new Point(0.5, 1), RadiusX = 1.2, RadiusY = 0.9 };
        bg.GradientStops.Add(new GradientStop(Color.FromRgb(0x2A, 0x2C, 0x2F), 0)); bg.GradientStops.Add(new GradientStop(Color.FromRgb(0x1A, 0x1B, 0x1D), 0.55)); bg.GradientStops.Add(new GradientStop(Color.FromRgb(0x14, 0x15, 0x16), 1));
        bg.Freeze(); g.Background = bg;
        if (!string.IsNullOrEmpty(banner)) {
            var im = Img.Make(banner, 560, h); im.Stretch = Stretch.UniformToFill; im.Opacity = 0.55; im.VerticalAlignment = VerticalAlignment.Top;
            var mask = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
            mask.GradientStops.Add(new GradientStop(Colors.Black, 0)); mask.GradientStops.Add(new GradientStop(Color.FromArgb(0xD9, 0, 0, 0), 0.45)); mask.GradientStops.Add(new GradientStop(Colors.Transparent, 1));
            mask.Freeze(); im.OpacityMask = mask;
            g.Children.Add(im);
            var shade = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
            shade.GradientStops.Add(new GradientStop(Color.FromArgb(0x26, 0x14, 0x15, 0x16), 0)); shade.GradientStops.Add(new GradientStop(Color.FromArgb(0x59, 0x14, 0x15, 0x16), 0.5)); shade.GradientStops.Add(new GradientStop(Color.FromArgb(0xEB, 0x14, 0x15, 0x16), 1));
            shade.Freeze(); g.Children.Add(new Rectangle { Fill = shade });
        }
        if (hero != null) {
            var floor = new RadialGradientBrush(); floor.GradientStops.Add(new GradientStop(Color.FromArgb(0x8C, 0, 0, 0), 0)); floor.GradientStops.Add(new GradientStop(Colors.Transparent, 1)); floor.Freeze();
            g.Children.Add(new Ellipse { Height = 22, Fill = floor, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(64, 0, 64, 52) });
            var fe = hero as FrameworkElement;
            if (fe != null) {
                fe.HorizontalAlignment = HorizontalAlignment.Center; fe.VerticalAlignment = VerticalAlignment.Center; fe.Margin = new Thickness(0, 0, 0, 44);
                fe.Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 10, Direction = 270, Opacity = 0.55, Color = Colors.Black };
            }
            g.Children.Add(hero);
        }
        if (!string.IsNullOrEmpty(tag)) {
            var t = Ui.MonoTb(tag, 11, Ui.T1); t.Opacity = 0.7; t.HorizontalAlignment = HorizontalAlignment.Left; t.VerticalAlignment = VerticalAlignment.Top; t.Margin = new Thickness(16, 14, 0, 0);
            g.Children.Add(t);
        }
        if (equipped) {
            var eq = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 12, 16, 0) };
            var d = Ui.Dot(Ui.Acc, 8); d.Margin = new Thickness(0, 0, 6, 0); eq.Children.Add(d);
            eq.Children.Add(Ui.Tb1(L.T("Надет сейчас", "Equipped"), 12, Ui.T2, null));
            g.Children.Add(eq);
        }
        var bottom = new DockPanel { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(16, 0, 16, 14), LastChildFill = true };
        if (controls != null) { DockPanel.SetDock(controls, Dock.Right); bottom.Children.Add(controls); }
        if (info != null) bottom.Children.Add(info);
        g.Children.Add(bottom);
        var ce = chips as FrameworkElement;
        if (ce != null) { ce.HorizontalAlignment = HorizontalAlignment.Right; ce.VerticalAlignment = VerticalAlignment.Bottom; ce.Margin = new Thickness(0, 0, 16, 58); g.Children.Add(ce); }
        var frame = new Border { Child = g, CornerRadius = new CornerRadius(12), BorderBrush = Ui.Line, BorderThickness = new Thickness(1), Margin = new Thickness(0, 0, 0, 16) };
        g.SizeChanged += (s, e) => g.Clip = new RectangleGeometry(new Rect(e.NewSize), 11, 11);
        return frame;
    }

    // Имя 18/500 и подпись 12 t2.
    public static UIElement Info(string name, string sub) {
        var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
        sp.Children.Add(Ui.Tb1(name, 18, Ui.T1, FontWeights.Medium));
        if (sub.Length > 0) { var s = Ui.Tb1(sub, 12, Ui.T2, null); s.Margin = new Thickness(0, 2, 0, 0); sp.Children.Add(s); }
        return sp;
    }

    // Образец цвета / номер уровня на сцене: 26×26, выбранный — светлая рамка.
    public static Border Chip(UIElement child, bool sel, string tip, Action click) {
        var b = new Border { Child = child, Width = 26, Height = 26, CornerRadius = new CornerRadius(6), Margin = new Thickness(0, 0, 6, 0), ToolTip = tip,
                             Background = Ui.Br(Ui.Bg3), BorderBrush = sel ? Ui.Br(Ui.T1) : Ui.Line, BorderThickness = new Thickness(sel ? 1.5 : 1), Cursor = Cursors.Hand, VerticalAlignment = VerticalAlignment.Center };
        b.MouseLeftButtonUp += (s, e) => click();
        return b;
    }

    // Подпись над сеткой: слева текст, справа моно-счётчик.
    public static UIElement GridHead(string text, string count) {
        var g = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(Ui.Tb1(text, 12, Ui.T3, null));
        var c = Ui.MonoTb(count, 11, Ui.T3); Grid.SetColumn(c, 1); g.Children.Add(c);
        return g;
    }

    // Карточка сетки: картинка по центру, подпись внизу слева, мятная точка — надето, выбранная — светлая рамка и bg3.
    public static Border Cell(string icon, double iw, double ih, string caption, bool sel, bool on, double dim, Action click) {
        var g = new Grid();
        var im = Img.Make(icon, iw, ih); im.VerticalAlignment = VerticalAlignment.Center; im.Margin = new Thickness(0, 0, 0, 14);
        if (dim < 1) im.Opacity = dim;
        g.Children.Add(im);
        var c = Ui.Tb1(caption, 11, dim < 1 ? Ui.T3 : Ui.T2, null); c.VerticalAlignment = VerticalAlignment.Bottom; g.Children.Add(c);
        if (on) { var d = Ui.Dot(Ui.Acc, 6); d.HorizontalAlignment = HorizontalAlignment.Right; d.VerticalAlignment = VerticalAlignment.Top; g.Children.Add(d); }
        var b = new Border { Child = g, Height = ih + 42, CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 8, 8, 6), Margin = new Thickness(4), ToolTip = caption,
                             Background = Ui.Br(sel ? Ui.Bg3 : Ui.Bg2), BorderBrush = sel ? Ui.A(Ui.T1, 0x52) : Ui.Line, BorderThickness = new Thickness(1) };
        Ui.Hover(b, sel ? Ui.Bg3 : Ui.Bg2, Ui.Bg3, click != null, click);
        return b;
    }
}
