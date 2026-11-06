// PagesHome.cs — главная панели: аккаунт, статус, «Надето сейчас» (ядро — `list now`, skins.ps1), одна колонка
// пунктов по группам «Настройки» / «Косметика» / «Сервис», внизу «Справка» и версия. Большая кнопка — только когда есть действие.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

static class PagesHome {
    static PanelWin P { get { return Ctl.Panel; } }

    public static void Build(StackPanel sp) {
        var s = Ctl.Cur; var st = Ctl.GetStatus();
        Dictionary<string, object> now = null;
        if (s.Client && s.Account.Length > 0 && Ctl.HaveState) {
            var l = Lists.Get("now");
            if (l != null && l.Count > 0 && Json.Str(l[0], "error").Length == 0) now = l[0];
        }
        sp.Children.Add(Account(s, now));
        sp.Children.Add(Status(st));

        if (s.Synced.Count > 0) sp.Children.Add(Pad(Ui.Tb(L.T("Из игры сохранено: ", "Saved from the game: ") + string.Join(", ", s.Synced.ToArray()), 12, Ui.T2, null)));
        if (s.Error.Length > 0 && Ctl.HaveState) sp.Children.Add(Pad(Ui.Tb(s.Error, 12, Ui.Warn, null)));
        var mb = MainButton(s); if (mb != null) sp.Children.Add(mb);
        var r = Ui.Result(); if (r != null) sp.Children.Add(Pad(r));
        if (s.AskAuto && Ctl.HaveState && !Ctl.Busy) sp.Children.Add(AskAuto());
        if (now != null) sp.Children.Add(Now(now));

        var g = Group(sp, L.T("Настройки", "Settings"), false);
        string diff = s.Have && s.Same.HasValue ? L.Plural(s.Diff, "отличие", "отличия", "отличий", "difference", "differences") : "";
        g.Children.Add(Ui.Nav("apply", L.T("Применить мои", "Apply mine"), Right(diff, false), () => P.Go("apply")));
        if (s.Diff > 0) g.Children.Add(Ui.Nav("diff", L.T("Что отличается", "What differs"), null, () => P.Go("diff")));
        g.Children.Add(Ui.Nav("save", L.T("Сохранить как мои", "Save as mine"), null, () => P.Go("save")));
        g.Children.Add(Ui.Nav("pros", L.T("Настройки про", "Pro settings"), null, () => P.Go("pros")));
        g.Children.Add(Ui.Nav("share", L.T("Код для друга", "Share code"), null, () => P.Go("share")));

        g = Group(sp, L.T("Косметика", "Cosmetics"), true);
        g.Children.Add(Ui.Nav("skins", L.T("Все скины", "All skins"), Ui.Keys("Ctrl", "Alt", "S"), () => P.Go("skins")));
        g.Children.Add(Ui.Nav("sets", L.T("Наборы", "Sets"), Right(s.NSets > 0 ? s.NSets.ToString() : "", true), () => P.Go("sets")));

        g = Group(sp, L.T("Сервис", "Service"), true);
        g.Children.Add(Ui.Nav("accounts", L.T("Аккаунты", "Accounts"), Right(s.NAccounts > 0 ? s.NAccounts.ToString() : "", true), () => P.Go("accounts")));
        g.Children.Add(Ui.Nav("backups", L.T("Бэкапы и история", "Backups and history"), null, () => P.Go("backups")));
        g.Children.Add(Ui.Nav("settings", L.T("Настройки", "Settings"), null, () => P.Go("settings")));

        sp.Children.Add(Foot(s));
    }

    static UIElement Pad(UIElement e) { var b = new Border { Child = e, Padding = new Thickness(16, 0, 16, 8) }; return b; }

    static UIElement Right(string text, bool mono) {
        if (text.Length == 0) return null;
        return mono ? Ui.MonoTb(text, 11, Ui.T3) : (UIElement)new TextBlock { Text = text, FontSize = 11, Foreground = Ui.Br(Ui.T3), VerticalAlignment = VerticalAlignment.Center };
    }

    // Группа: линия сверху, подпись, пункты.
    static StackPanel Group(StackPanel sp, string cap, bool line) {
        var g = new StackPanel();
        g.Children.Add(Ui.Cap(cap));
        sp.Children.Add(new Border { Child = g, BorderBrush = Ui.Line, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(8, 0, 8, 8) });
        return g;
    }

    // ── аккаунт: карточка игрока, Riot ID, регион и роль аккаунта ──
    static UIElement Account(State s, Dictionary<string, object> now) {
        var g = new Grid { Margin = new Thickness(16, 16, 16, 12) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        string card = now != null ? Json.Str(now, "card") : "";
        if (card.Length > 0) {
            var im = Img.Make(card, 40, 40); im.Stretch = Stretch.UniformToFill;
            im.Clip = new RectangleGeometry(new Rect(0, 0, 40, 40), 8, 8);
            var box = new Border { Child = im, Width = 40, Height = 40, CornerRadius = new CornerRadius(8), Background = Ui.Br(Ui.Bg3), Margin = new Thickness(0, 0, 12, 0) };
            g.Children.Add(box);
        }
        var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        sp.Children.Add(Ui.Tb1(s.Account.Length > 0 ? s.Account : "VALSET", 16, Ui.T1, FontWeights.Medium));
        string role = s.Account.Length == 0 ? "" : s.IsMain ? L.T("основной аккаунт", "main account") : s.Temp ? L.T("чужой · на время", "not yours · for now") : s.Own ? L.T("свой аккаунт", "your account") : L.T("чужой аккаунт", "not your account");
        string region = now != null ? Json.Str(now, "region") : "";
        string meta = region.Length > 0 && role.Length > 0 ? region + " · " + role : region + role;
        if (meta.Length > 0) sp.Children.Add(Ui.MonoTb(meta, 11, Ui.T3));
        Grid.SetColumn(sp, 1); g.Children.Add(sp);
        return g;
    }

    static UIElement Status(Status st) {
        var g = new Grid { Margin = new Thickness(16, 0, 16, 16) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        uint c = st.Color == Ctl.Green ? Ui.Acc : st.Color == Ctl.Amber ? Ui.Warn : st.Color == Ctl.Blue ? Ui.T2 : Ui.T3;
        var d = Ui.Dot(c, 8); d.Margin = new Thickness(0, 0, 8, 0); g.Children.Add(d);
        var t = Ui.Tb1(st.Text, 13, Ui.T2, null); Grid.SetColumn(t, 1); g.Children.Add(t);
        if (Ctl.HaveState && Ctl.StateAt > DateTime.MinValue) {
            var m = Ui.MonoTb(L.T("сверено ", "checked ") + Ctl.StateAt.ToString("HH:mm"), 11, Ui.T3); m.Margin = new Thickness(8, 0, 0, 0);
            Grid.SetColumn(m, 2); g.Children.Add(m);
        }
        return g;
    }

    // ── «Надето сейчас»: Vandal, два спрея, набор и агент ──
    static UIElement Now(Dictionary<string, object> d) {
        string gun = Json.Str(d, "gun"), set = Json.Str(d, "set"), agent = Json.Str(d, "agent");
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(56) });
        g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var im = Img.Make(gun, 200, 48); im.HorizontalAlignment = HorizontalAlignment.Left;
        im.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 10, ShadowDepth = 5, Direction = 270, Opacity = 0.5, Color = Colors.Black };
        g.Children.Add(im);
        var side = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        foreach (var u in Json.List(d, "ex")) {
            var x = Img.Make(u, 24, 24);
            side.Children.Add(new Border { Child = x, Width = 28, Height = 28, CornerRadius = new CornerRadius(6), Background = Ui.Br(Ui.Bg3), Margin = new Thickness(4, 0, 0, 0) });
        }
        Grid.SetColumn(side, 1); g.Children.Add(side);
        var lbl = new Grid { Margin = new Thickness(0, 4, 0, 0) };
        lbl.ColumnDefinitions.Add(new ColumnDefinition());
        lbl.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new TextBlock { FontSize = 12, Foreground = Ui.Br(Ui.T2), TextTrimming = TextTrimming.CharacterEllipsis };
        left.Inlines.Add(new System.Windows.Documents.Run(L.T("Надето", "Wearing")));
        if (set.Length > 0) {
            left.Inlines.Add(new System.Windows.Documents.Run(" · "));
            left.Inlines.Add(new System.Windows.Documents.Run(L.T("набор «", "set “") + set + L.T("»", "”")) { Foreground = Ui.Br(Ui.T1), FontWeight = FontWeights.Medium });
        }
        lbl.Children.Add(left);
        if (agent.Length > 0) { var a = Ui.MonoTb(agent, 11, Ui.T3); Grid.SetColumn(a, 1); lbl.Children.Add(a); }
        Grid.SetRow(lbl, 1); Grid.SetColumnSpan(lbl, 2); g.Children.Add(lbl);
        var c = Ui.Card(g, new Thickness(12)); c.CornerRadius = new CornerRadius(12); c.Margin = new Thickness(12, 0, 12, 12);
        Ui.Hover(c, Ui.Bg2, Ui.Bg3, true, () => P.Go("skins"));
        return c;
    }

    static UIElement Foot(State s) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var h = Ui.Tb(L.T("Справка", "Help"), 11, Ui.T3, null); h.Cursor = System.Windows.Input.Cursors.Hand;
        h.MouseEnter += (a, e) => h.Foreground = Ui.Br(Ui.T1); h.MouseLeave += (a, e) => h.Foreground = Ui.Br(Ui.T3);
        h.MouseLeftButtonUp += (a, e) => P.Go("help");
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(h); left.Children.Add(Report());
        g.Children.Add(left);
        var v = Ui.MonoTb("VALSET" + (s.Ver.Length > 0 ? " " + s.Ver : ""), 11, Ui.T3); Grid.SetColumn(v, 1); g.Children.Add(v);
        return new Border { Child = g, BorderBrush = Ui.Line, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(16, 8, 16, 12) };
    }

    // «Сообщить об ошибке» — тихая ссылка в подвале: диагностика (без личного) в буфер, форма issue на GitHub — в браузере.
    static UIElement Report() {
        var ic = Icons.Make("report", Ui.T3); ic.Width = 12; ic.Height = 12; ic.Margin = new Thickness(0, 0, 5, 0);
        var t = Ui.Tb(L.T("Сообщить об ошибке", "Report a bug"), 11, Ui.T3, null);
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 0, 0, 0), Cursor = System.Windows.Input.Cursors.Hand, Background = Brushes.Transparent };
        r.Children.Add(ic); r.Children.Add(t);
        var path = (System.Windows.Shapes.Path)((Canvas)((Viewbox)ic).Child).Children[0];
        r.MouseEnter += (a, e) => { t.Foreground = Ui.Br(Ui.T1); path.Stroke = Ui.Br(Ui.T1); };
        r.MouseLeave += (a, e) => { t.Foreground = Ui.Br(Ui.T3); path.Stroke = Ui.Br(Ui.T3); };
        r.MouseLeftButtonUp += (a, e) => Ctl.DoAction("report", false);
        return r;
    }

    // Один раз после установки: включить автоперенос? Ответ (любой) больше не спрашивается; меняется в «Настройках».
    static UIElement AskAuto() {
        var a = Ui.Ask(L.T("Переносить твои настройки сами при входе в другие аккаунты?", "Apply your settings automatically when you log into other accounts?"),
                       L.T("Основной не трогается; исходные чужих вернутся после игры", "Main is never touched; the originals come back after the game"),
                       Ui.Pri(L.T("Да", "Yes"), 12, true, () => { Ctl.Cur.AskAuto = false; Ctl.DoAction("set:autoApply=on", false); }, 28, 8),
                       Ui.Sec(L.T("Нет", "No"), 12, true, () => { Ctl.Cur.AskAuto = false; Ctl.DoAction("set:autoAsked=on", false); }, 28, 8));
        a.Margin = new Thickness(12, 0, 12, 12);
        return a;
    }

    // Большая кнопка — только когда есть действие (state.suggested).
    static UIElement MainButton(State s) {
        if (Ctl.Busy) return null;
        string text; Action act;
        switch (s.Suggested) {
            case "save": text = L.T("Сохранить как мои", "Save as mine"); act = () => Ctl.DoAction("save", false); break;
            case "apply": text = L.T("Применить мои", "Apply mine"); act = () => Ctl.DoAction("apply", false); break;
            case "untemp": text = L.T("Вернуть исходные", "Restore originals"); act = () => Ctl.DoAction("untemp", false); break;
            case "client": text = L.T("Открыть клиент Riot", "Open Riot Client"); act = Core.OpenRiotClient; break;
            default: return null;
        }
        var b = Ui.Pri(text, 13, true, act, 36, 8);
        b.Margin = new Thickness(16, 0, 16, 16);
        return b;
    }
}
