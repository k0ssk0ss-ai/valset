// UiIcons.cs — линейные значки 16 px (контур 24×24, линия 1.5, скруглённые концы) — как в макете dist\mockup-panel.html.
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

static class Icons {
    static readonly Dictionary<string, Geometry> cache = new Dictionary<string, Geometry>();

    // Окружность в языке путей: две дуги.
    static string C(double x, double y, double r) {
        return string.Format(System.Globalization.CultureInfo.InvariantCulture, "M{0},{1} a{2},{2} 0 1 0 {3},0 a{2},{2} 0 1 0 -{3},0 ", x - r, y, r, 2 * r);
    }

    static string Src(string name) {
        switch (name) {
            case "apply": return "M12,3 V15 M7,10 L12,15 L17,10 M5,21 H19";
            case "save": return "M5,3 H16 L19,6 V21 H5 Z M8,3 V8 H15 V3 M8,21 V14 H16 V21";
            case "diff": return "M4,7 H14 M4,12 H20 M4,17 H11 M17,4 L20,7 L17,10";
            case "pros": return C(12, 12, 8) + "M12,2 V6 M12,18 V22 M2,12 H6 M18,12 H22";
            case "share": return "M10,14 L14,10 M8.5,16.5 L6.7,18.3 A3,3 0 0 1 2.5,14.1 L6,10.6 A3,3 0 0 1 10.2,10.6 M15.5,7.5 L17.3,5.7 A3,3 0 0 1 21.5,9.9 L18,13.4 A3,3 0 0 1 13.8,13.4";
            case "skins": return "M5,4 H19 A2,2 0 0 1 21,6 V18 A2,2 0 0 1 19,20 H5 A2,2 0 0 1 3,18 V6 A2,2 0 0 1 5,4 Z M3,15 L8,10 L12,14 L15,11 L21,17";
            case "sets": return "M4,7 H20 M4,12 H20 M4,17 H14";
            case "accounts": return C(9, 8, 3.5) + "M3,20 C3,16.7 5.7,14 9,14 C12.3,14 15,16.7 15,20 M16,4.5 A3.5,3.5 0 0 1 16,11.5 M21,20 C21,17.4 19.3,15.1 17,14.3";
            case "backups": return "M3,12 A9,9 0 1 0 6,5.3 L3,8 M3,3 V8 H8 M12,7 V12 L15,14";
            case "settings": return C(12, 12, 3) + "M12,3 V5 M12,19 V21 M3,12 H5 M19,12 H21 M5.6,5.6 L7,7 M17,17 L18.4,18.4 M5.6,18.4 L7,17 M17,7 L18.4,5.6" + C(12, 12, 7);
            case "help": return C(12, 12, 9) + "M9.5,9.5 A2.5,2.5 0 1 1 12,12 V13.5 M12,17 V17.2";
            case "back": return "M15,5 L8,12 L15,19";
            case "search": return C(11, 11, 6) + "M20,20 L15.5,15.5";
            case "chev": return "M9,6 L15,12 L9,18";
        }
        return "";
    }

    public static Geometry Geo(string name) {
        Geometry g;
        if (!cache.TryGetValue(name, out g)) { g = Geometry.Parse(Src(name)); g.Freeze(); cache[name] = g; }
        return g;
    }

    // Значок 16×16 цвета c.
    public static FrameworkElement Make(string name, uint c) {
        var p = new Path { Data = Geo(name), Stroke = Ui.Br(c), StrokeThickness = 1.5, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round };
        var cv = new Canvas { Width = 24, Height = 24 }; cv.Children.Add(p);
        return new Viewbox { Child = cv, Width = 16, Height = 16, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
    }
}
