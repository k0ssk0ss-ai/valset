// Ui.cs — общие элементы панели, всё кодом, без XAML. Стиль: графит, тонкие линии; цвет — только у скинов и баннеров
// коллекций, мятный — только «твоё» (статус, надетое, выбранное в списке оружия). Токены — NOTES.md, «Оформление».
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

static class Ui {
    // ── токены ──
    public const uint Bg0 = 0x0E0F10, Bg1 = 0x161718, Bg2 = 0x1D1E20, Bg3 = 0x26282A;
    public const uint T1 = 0xECEEF0, T2 = 0xA4A8AD, T3 = 0x6C7076, Acc = 0x46C08A, Warn = 0xD9A441, Err = 0xD0706A, Ink = 0x111213;
    public static readonly FontFamily Sans = new FontFamily("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Mono = new FontFamily("Cascadia Mono, Consolas");
    public static readonly SolidColorBrush Line = A(T1, 0x14), Line2 = A(T1, 0x24);   // волосяная линия 8 % и рамка кнопок 14 %

    public static SolidColorBrush Br(uint rgb) {
        var b = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)); b.Freeze(); return b;
    }
    public static SolidColorBrush A(uint rgb, byte alpha) {
        var b = new SolidColorBrush(Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)); b.Freeze(); return b;
    }
    static Brush Bg(uint c) { return c == 0 ? Brushes.Transparent : (Brush)Br(c); }

    public static TextBlock Tb(string text, double size, uint color, FontWeight? weight) {
        var t = new TextBlock { Text = text, FontSize = size, Foreground = Br(color), TextWrapping = TextWrapping.Wrap };
        if (weight.HasValue) t.FontWeight = weight.Value;
        return t;
    }

    // Однострочный текст с многоточием.
    public static TextBlock Tb1(string text, double size, uint color, FontWeight? weight) {
        var t = Tb(text, size, color, weight); t.TextWrapping = TextWrapping.NoWrap; t.TextTrimming = TextTrimming.CharacterEllipsis; return t;
    }

    // Моноширинный: счётчики, время, метки (цифры табличные).
    public static TextBlock MonoTb(string text, double size, uint color) {
        var t = Tb1(text, size, color, null); t.FontFamily = Mono; t.VerticalAlignment = VerticalAlignment.Center; return t;
    }

    // Подпись группы: 12 px, t3, 8 px над пунктами.
    public static TextBlock Cap(string text) { var t = Tb1(text, 12, T3, null); t.Margin = new Thickness(8, 8, 8, 4); return t; }

    public static Ellipse Dot(uint c, double size) { return new Ellipse { Width = size, Height = size, Fill = Br(c), VerticalAlignment = VerticalAlignment.Center }; }

    // Кнопка из Border: тема задаётся кодом, без шаблонов.
    public static Border Btn(string text, double size, uint fg, uint bg, uint hover, bool enabled, Action click, double height, double radius) {
        var tb = Tb(text, size, enabled ? fg : T3, FontWeights.Medium);
        tb.HorizontalAlignment = HorizontalAlignment.Center; tb.VerticalAlignment = VerticalAlignment.Center;
        var b = new Border { Child = tb, Background = Bg(bg), CornerRadius = new CornerRadius(radius), Height = height, Padding = new Thickness(12, 0, 12, 0) };
        Hover(b, bg, hover, enabled, click);
        return b;
    }

    // Главная кнопка: светлая, тёмный текст.
    public static Border Pri(string text, double size, bool enabled, Action click, double height, double radius) {
        var b = Btn(text, size, Ink, enabled ? T1 : Bg3, 0xFFFFFF, enabled, click, height, 8);
        return b;
    }

    // Второстепенная: прозрачная, рамка-линия.
    public static Border Sec(string text, double size, bool enabled, Action click, double height, double radius) {
        var b = Btn(text, size, T1, 0, Bg3, enabled, click, height, 8);
        b.BorderBrush = Line2; b.BorderThickness = new Thickness(1);
        return b;
    }

    public static void Hover(Border b, uint bg, uint hover, bool enabled, Action click) {
        if (!enabled) return;
        b.Cursor = Cursors.Hand;
        b.MouseEnter += (s, e) => b.Background = Br(hover);
        b.MouseLeave += (s, e) => b.Background = Bg(bg);
        b.MouseLeftButtonUp += (s, e) => { if (click != null) click(); };
    }

    public static Border Sep(double top, double bottom) {
        return new Border { Height = 1, Background = Line, Margin = new Thickness(0, top, 0, bottom) };
    }

    // Карточка: bg2, линия, радиус 10.
    public static Border Card(UIElement child, Thickness pad) {
        return new Border { Child = child, Background = Br(Bg2), BorderBrush = Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Padding = pad };
    }

    // Строка списка: заголовок + подпись, справа необязательная отметка. click == null — не нажимается.
    public static Border Row(string title, string sub, string right, uint rightColor, Action click) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(Tb1(title, 13, T1, null));
        if (!string.IsNullOrEmpty(sub)) { var s = Tb(sub, 12, T2, null); s.Margin = new Thickness(0, 1, 0, 0); left.Children.Add(s); }
        g.Children.Add(left);
        if (!string.IsNullOrEmpty(right)) {
            UIElement r = right == "on" ? (UIElement)Dot(Acc, 6) : right == "warn" ? (UIElement)Dot(Warn, 6) : MonoTb(right, 11, rightColor == 0 ? T3 : rightColor);
            ((FrameworkElement)r).Margin = new Thickness(8, 0, 0, 0);
            Grid.SetColumn(r, 1); g.Children.Add(r);
        }
        var b = new Border { Child = g, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 8, 8, 8), MinHeight = 36, Background = Brushes.Transparent };
        Hover(b, 0, Bg3, click != null, click);
        return b;
    }

    // Пункт навигации: значок 16 px, подпись, справа — счётчик / клавиши.
    public static Border Nav(string icon, string text, UIElement right, Action click) {
        var g = new Grid { Height = 36 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(icon != null ? 26 : 0) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (icon != null) g.Children.Add(Icons.Make(icon, T2));
        var t = Tb1(text, 13, T1, null); t.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(t, 1); g.Children.Add(t);
        if (right != null) { Grid.SetColumn(right, 2); g.Children.Add(right); }
        var b = new Border { Child = g, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 0, 8, 0), Background = Brushes.Transparent };
        Hover(b, 0, Bg3, true, click);
        return b;
    }
    public static Border Nav(string text, Action click) { return Nav(null, text, null, click); }

    // Клавиши: Ctrl Alt S.
    public static UIElement Keys(params string[] keys) {
        var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        foreach (var k in keys) {
            var t = MonoTb(k, 10, T2);
            sp.Children.Add(new Border { Child = t, BorderBrush = Line2, BorderThickness = new Thickness(1, 1, 1, 2), CornerRadius = new CornerRadius(4), Padding = new Thickness(4, 0, 4, 1), Margin = new Thickness(3, 0, 0, 0) });
        }
        return sp;
    }

    // Переключатель: подпись слева, «таблетка» справа (включено — мятный).
    public static Border Toggle(string label, bool on, Action<bool> set) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var t = Tb(label, 13, T1, null); t.VerticalAlignment = VerticalAlignment.Center;
        g.Children.Add(t);
        var knob = new Ellipse { Width = 12, Height = 12, Fill = Br(on ? Ink : T2), Margin = new Thickness(3, 0, 3, 0), HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        var pill = new Border { Width = 34, Height = 18, CornerRadius = new CornerRadius(9), Background = on ? Br(Acc) : Br(Bg0), BorderBrush = on ? Br(Acc) : Line2, BorderThickness = new Thickness(1), Child = knob };
        Grid.SetColumn(pill, 1); g.Children.Add(pill);
        var b = new Border { Child = g, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 0, 8, 0), Height = 36, Background = Brushes.Transparent };
        Hover(b, 0, Bg3, true, () => set(!on));
        return b;
    }

    // Сегменты (вкладки): подложка bg0 с линией, выбранный — bg3.
    public static Border Seg(params Border[] items) {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var x in items) sp.Children.Add(x);
        return new Border { Child = sp, Background = Br(Bg0), BorderBrush = Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = new Thickness(2), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left };
    }
    public static Border SegItem(string text, bool on, Action click) {
        var t = Tb1(text, 12, on ? T1 : T2, null); t.VerticalAlignment = VerticalAlignment.Center;
        var b = new Border { Child = t, CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 4, 10, 5), Background = on ? Br(Bg3) : Brushes.Transparent };
        Hover(b, on ? Bg3 : 0, Bg3, true, click);
        return b;
    }

    // Подтверждение / вопрос: карточка с заголовком, подписью и кнопками.
    public static Border Ask(string title, string sub, params Border[] buttons) {
        var sp = new StackPanel();
        sp.Children.Add(Tb(title, 13, T1, FontWeights.Medium));
        if (!string.IsNullOrEmpty(sub)) { var s = Tb(sub, 12, T2, null); s.Margin = new Thickness(0, 2, 0, 0); sp.Children.Add(s); }
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        foreach (var x in buttons) { x.Margin = new Thickness(0, 0, 8, 0); x.MinWidth = 60; r.Children.Add(x); }
        sp.Children.Add(r);
        var c = Card(sp, new Thickness(12, 10, 12, 12)); c.Margin = new Thickness(0, 4, 0, 4);
        return c;
    }

    public static TextBlock Loading() {
        var t = MonoTb("…", 13, T3); t.Margin = new Thickness(8, 8, 0, 8); return t;
    }

    public static TextBlock Note(string text) {
        var t = Tb(text, 12, T2, null); t.Margin = new Thickness(8, 6, 8, 6); return t;
    }

    // Итог действия: «Готово · Отменить» (или «…», пока идёт). null — показывать нечего.
    public static UIElement Result() {
        if (Ctl.Busy) { var w = Ctl.BusyStatus.Length > 0 ? Tb("…  " + Ctl.BusyStatus, 12, Warn, null) : MonoTb("…", 13, T3); w.Margin = new Thickness(0, 8, 0, 0); return w; }
        if (Ctl.ResultMsg == null) return null;
        var sp = new StackPanel { Margin = new Thickness(0, 8, 0, 4) };
        sp.Children.Add(Tb(Ctl.ResultMsg, 12, T2, null));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        if (Ctl.ResultOk) { var d = Dot(Acc, 6); d.Margin = new Thickness(0, 0, 6, 0); r.Children.Add(d); }
        r.Children.Add(Tb(Ctl.ResultOk ? L.T("Готово", "Done") : L.T("Не вышло", "Failed"), 12, Ctl.ResultOk ? T1 : Warn, FontWeights.Medium));
        if (Ctl.ResultUndo) {
            r.Children.Add(Tb("  ·  ", 12, T3, null));
            var u = Tb(L.T("Отменить", "Undo"), 12, T1, FontWeights.Medium);
            u.TextDecorations = TextDecorations.Underline; u.Cursor = Cursors.Hand; u.MouseLeftButtonUp += (a, b) => Ctl.DoAction("undo", false);
            r.Children.Add(u);
        }
        sp.Children.Add(r);
        return sp;
    }
}
