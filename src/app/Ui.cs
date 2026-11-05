// Ui.cs — общие стилизованные элементы панели (тёмный стиль Win11, всё кодом, без XAML).
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

static class Ui {
    public static SolidColorBrush Br(uint rgb) {
        var b = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)); b.Freeze(); return b;
    }

    public static TextBlock Tb(string text, double size, uint color, FontWeight? weight) {
        var t = new TextBlock { Text = text, FontSize = size, Foreground = Br(color), TextWrapping = TextWrapping.Wrap };
        if (weight.HasValue) t.FontWeight = weight.Value;
        return t;
    }

    // Кнопка из Border: тема задаётся кодом, без шаблонов.
    public static Border Btn(string text, double size, uint fg, uint bg, uint hover, bool enabled, Action click, double height, double radius) {
        var tb = Tb(text, size, fg, FontWeights.SemiBold);
        tb.HorizontalAlignment = HorizontalAlignment.Center; tb.VerticalAlignment = VerticalAlignment.Center;
        var b = new Border { Child = tb, Background = bg == 0 ? Brushes.Transparent : (Brush)Br(bg), CornerRadius = new CornerRadius(radius), Height = height, Padding = new Thickness(10, 0, 10, 0) };
        Hover(b, bg, hover, enabled, click);
        return b;
    }

    static void Hover(Border b, uint bg, uint hover, bool enabled, Action click) {
        if (!enabled) return;
        b.Cursor = Cursors.Hand;
        b.MouseEnter += (s, e) => b.Background = Br(hover);
        b.MouseLeave += (s, e) => b.Background = bg == 0 ? Brushes.Transparent : (Brush)Br(bg);
        b.MouseLeftButtonUp += (s, e) => { if (click != null) click(); };
    }

    public static Border Sep(double top, double bottom) {
        return new Border { Height = 1, Background = Br(0x333333), Margin = new Thickness(0, top, 0, bottom) };
    }

    // Строка списка: заголовок + подпись, справа необязательная отметка. click == null — не нажимается.
    public static Border Row(string title, string sub, string right, uint rightColor, Action click) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel();
        var t = Tb(title, 13.5, 0xFFFFFF, FontWeights.SemiBold); t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap;
        left.Children.Add(t);
        if (!string.IsNullOrEmpty(sub)) left.Children.Add(Tb(sub, 11.5, 0x9A9A9A, null));
        g.Children.Add(left);
        if (!string.IsNullOrEmpty(right)) {
            var r = Tb(right, 13, rightColor, FontWeights.SemiBold); r.VerticalAlignment = VerticalAlignment.Center; r.Margin = new Thickness(8, 0, 0, 0);
            Grid.SetColumn(r, 1); g.Children.Add(r);
        }
        var b = new Border { Child = g, CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 6, 10, 7), Margin = new Thickness(0, 0, 0, 2), Background = Brushes.Transparent };
        Hover(b, 0, 0x2B2B2B, click != null, click);
        return b;
    }

    // Пункт навигации на главной.
    public static Border Nav(string text, Action click) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var t = Tb(text, 13, 0xE0E0E0, null); t.TextWrapping = TextWrapping.NoWrap; t.TextTrimming = TextTrimming.CharacterEllipsis;
        g.Children.Add(t);
        var a = Tb("▸", 12, 0x777777, null); Grid.SetColumn(a, 1); g.Children.Add(a);
        var b = new Border { Child = g, CornerRadius = new CornerRadius(5), Padding = new Thickness(10, 6, 8, 7), Background = Brushes.Transparent };
        Hover(b, 0, 0x2E2E2E, true, click);
        return b;
    }

    // Переключатель: подпись слева, «таблетка» справа.
    public static Border Toggle(string label, bool on, Action<bool> set) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var t = Tb(label, 13.5, 0xE8E8E8, null); t.VerticalAlignment = VerticalAlignment.Center;
        g.Children.Add(t);
        var knob = new Ellipse { Width = 12, Height = 12, Fill = Brushes.White, Margin = new Thickness(3, 0, 3, 0), HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        var pill = new Border { Width = 36, Height = 18, CornerRadius = new CornerRadius(9), Background = Br(on ? 0x3D8BFDu : 0x5A5A5Au), Child = knob };
        Grid.SetColumn(pill, 1); g.Children.Add(pill);
        var b = new Border { Child = g, CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 8, 10, 8), Background = Brushes.Transparent };
        Hover(b, 0, 0x2B2B2B, true, () => set(!on));
        return b;
    }

    public static TextBlock Loading() {
        var t = Tb("…", 16, 0x9A9A9A, null); t.Margin = new Thickness(10, 8, 0, 8); return t;
    }

    public static TextBlock Note(string text) {
        var t = Tb(text, 12.5, 0x9A9A9A, null); t.Margin = new Thickness(10, 8, 10, 8); return t;
    }

    // Итог действия: «Готово · Отменить» (или «…», пока идёт). null — показывать нечего.
    public static UIElement Result() {
        if (Ctl.Busy) { var w = Ctl.BusyStatus.Length > 0 ? Tb("…  " + Ctl.BusyStatus, 12.5, 0xE0A100, null) : Tb("…", 14, 0x9A9A9A, null); w.Margin = new Thickness(0, 10, 0, 0); return w; }
        if (Ctl.ResultMsg == null) return null;
        var sp = new StackPanel { Margin = new Thickness(0, 10, 0, 4) };
        sp.Children.Add(Tb(Ctl.ResultMsg, 12.5, 0xE0E0E0, null));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        r.Children.Add(Tb(Ctl.ResultOk ? L.T("Готово", "Done") : L.T("Не вышло", "Failed"), 12.5, Ctl.ResultOk ? 0x3BA55Cu : 0xE0A100u, FontWeights.SemiBold));
        if (Ctl.ResultUndo) {
            r.Children.Add(Tb("  ·  ", 12.5, 0x777777, null));
            var u = Tb(L.T("Отменить", "Undo"), 12.5, 0x60A5FF, FontWeights.SemiBold);
            u.Cursor = Cursors.Hand; u.MouseLeftButtonUp += (a, b) => Ctl.DoAction("undo", false);
            r.Children.Add(u);
        }
        sp.Children.Add(r);
        return sp;
    }
}
