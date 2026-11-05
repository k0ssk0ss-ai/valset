// Pages.cs — страницы панели: Главная, Применить, Сохранить, Настройки, Справка (код для друга — PagesShare.cs, скины — PagesSets.cs).
using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Shapes;

static class Pages {
    static PanelWin P { get { return Ctl.Panel; } }

    public static string Title(string page) {
        switch (page) {
            case "apply": return L.T("Применить", "Apply");
            case "save": return L.T("Сохранить", "Save");
            case "diff": return L.T("Что отличается", "What differs");
            case "pros": return L.T("Про", "Pros");
            case "accounts": return L.T("Аккаунты", "Accounts");
            case "backups": return L.T("Бэкапы", "Backups");
            case "settings": return L.T("Настройки", "Settings");
            case "share": return L.T("Код для друга", "Share code");
            case "preview": return Share.Title();
            case "sets": return L.T("Скины", "Skins");
            case "setagent": return L.T("Агент для набора", "Agent for the set");
            case "skins": case "skinsgun": return Skins.Title(page);
            case "help": return L.T("Справка", "Help");
        }
        return "VALSET";
    }

    public static void Body(string page, StackPanel b) {
        switch (page) {
            case "apply": Apply(b); break;
            case "save": Save(b); break;
            case "diff": PagesLists.Diff(b); break;
            case "pros": PagesLists.Pros(b); break;
            case "accounts": PagesLists.Accounts(b); break;
            case "backups": PagesLists.Backups(b); break;
            case "settings": Settings(b); break;
            case "share": Share.Page(b); break;
            case "preview": Share.Preview(b); break;
            case "sets": Sets.Page(b); break;
            case "setagent": Sets.Agents(b); break;
            case "skins": Skins.Page(b); break;
            case "skinsgun": Skins.Gun(b); break;
            case "help": Help(b); break;
        }
    }

    // ── Главная ──
    public static void Home(StackPanel sp) {
        var s = Ctl.Cur; var st = Ctl.GetStatus();
        sp.Children.Add(Ui.Tb("VALSET", 11, 0x9A9A9A, FontWeights.SemiBold));
        var acc = Ui.Tb(s.Account.Length > 0 ? s.Account : "—", 20, 0xFFFFFF, FontWeights.SemiBold);
        acc.Margin = new Thickness(0, 2, 0, 0); acc.TextTrimming = TextTrimming.CharacterEllipsis; acc.TextWrapping = TextWrapping.NoWrap;
        sp.Children.Add(acc);

        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        row.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = Ui.Br(st.Color), Margin = new Thickness(0, 1, 8, 0), VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(Ui.Tb(st.Text, 13, 0xE0E0E0, null));
        sp.Children.Add(row);

        if (s.Synced.Count > 0) {
            var n = Ui.Tb(L.T("Из игры сохранено: ", "Saved from the game: ") + string.Join(", ", s.Synced.ToArray()), 12, 0x9A9A9A, null);
            n.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(n);
        }
        if (s.Error.Length > 0 && Ctl.HaveState) {
            var n = Ui.Tb(s.Error, 12, 0xE0A100, null); n.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(n);
        }
        sp.Children.Add(MainButton(s));
        var r = Ui.Result(); if (r != null) sp.Children.Add(r);
        if (s.AskAuto && Ctl.HaveState && !Ctl.Busy) sp.Children.Add(AskAuto());

        sp.Children.Add(Ui.Sep(12, 6));
        var g = new UniformGrid { Columns = 2 };
        g.Children.Add(NavItem(L.T("Применить", "Apply"), "apply"));
        g.Children.Add(NavItem(L.T("Сохранить", "Save"), "save"));
        if (s.Diff > 0) g.Children.Add(NavItem(L.T("Что отличается", "What differs"), "diff"));
        g.Children.Add(NavItem(L.T("Про", "Pros"), "pros"));
        g.Children.Add(NavItem(L.T("Код для друга", "Share code"), "share"));
        g.Children.Add(NavItem(L.T("Скины", "Skins"), "sets"));
        g.Children.Add(NavItem(L.T("Аккаунты", "Accounts"), "accounts"));
        g.Children.Add(NavItem(L.T("Бэкапы", "Backups"), "backups"));
        g.Children.Add(NavItem(L.T("Настройки", "Settings"), "settings"));
        g.Children.Add(NavItem(L.T("Справка", "Help"), "help"));
        sp.Children.Add(g);
    }

    static UIElement NavItem(string text, string page) { return Ui.Nav(text, () => P.Go(page)); }

    // Один раз после установки: включить автоперенос? Ответ (любой) больше не спрашивается; меняется в «Настройках».
    static UIElement AskAuto() {
        var box = new Border { Background = Ui.Br(0x2B2B2B), CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 8, 10, 8), Margin = new Thickness(0, 10, 0, 0) };
        var sp = new StackPanel();
        sp.Children.Add(Ui.Tb(L.T("Переносить твои настройки сами при входе в другие аккаунты?", "Apply your settings automatically when you log into other accounts?"), 13, 0xFFFFFF, FontWeights.SemiBold));
        sp.Children.Add(Ui.Tb(L.T("Основной не трогается; исходные чужих вернутся после игры.", "Main is never touched; the originals come back after the game."), 11.5, 0x9A9A9A, null));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        var yes = Ui.Btn(L.T("Да", "Yes"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, true, () => { Ctl.Cur.AskAuto = false; Ctl.DoAction("set:autoApply=on", false); }, 26, 5); yes.MinWidth = 60;
        var no = Ui.Btn(L.T("Нет", "No"), 12.5, 0xE0E0E0, 0x3A3A3A, 0x484848, true, () => { Ctl.Cur.AskAuto = false; Ctl.DoAction("set:autoAsked=on", false); }, 26, 5); no.MinWidth = 60;
        no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no); sp.Children.Add(r);
        box.Child = sp; return box;
    }

    // Одна большая кнопка по ситуации (state.suggested).
    static UIElement MainButton(State s) {
        string text; Action act = null; bool on = true;
        if (Ctl.Busy) { text = "…"; on = false; }
        else switch (s.Suggested) {
            case "save": text = L.T("Сохранить", "Save"); act = () => Ctl.DoAction("save", false); break;
            case "apply": text = L.T("Применить мои", "Apply mine"); act = () => Ctl.DoAction("apply", false); break;
            case "untemp": text = L.T("Вернуть исходные", "Restore originals"); act = () => Ctl.DoAction("untemp", false); break;
            case "client": text = L.T("Открыть клиент Riot", "Open Riot Client"); act = Core.OpenRiotClient; break;
            default: text = L.T("Всё твоё ✓", "All yours ✓"); on = false; break;
        }
        var b = Ui.Btn(text, 14, on ? 0xFFFFFFu : 0x8A8A8Au, on ? 0x3D8BFDu : 0x333333u, 0x5A9DFE, on, act, 40, 6);
        b.Margin = new Thickness(0, 14, 0, 0);
        return b;
    }

    static void Act(StackPanel b, string title, string sub, string id) {
        b.Children.Add(Ui.Row(title, sub, "", 0, () => Ctl.DoAction(id, false)));
    }

    // ── Применить ──
    static void Apply(StackPanel b) {
        string hint = Ctl.Cur.Own
            ? L.T("твои настройки на этом аккаунте", "your settings on this account")
            : L.T("на время: после игры вернутся исходные", "temporary: originals come back after the game");
        Act(b, L.T("Всё", "Everything"), hint, "apply");
        Act(b, L.T("Только бинды", "Keybinds only"), hint, "binds");
        Act(b, L.T("Насовсем", "Permanently"), L.T("останется и после игры", "stays after the game"), "applyperm");
    }

    // ── Сохранить ──
    static void Save(StackPanel b) {
        Act(b, L.T("Всё", "Everything"), L.T("бинды, графика и остальное", "binds, graphics and the rest"), "save");
        Act(b, L.T("Только бинды", "Keybinds only"), "", "savebinds");
        Act(b, L.T("Только графику", "Graphics only"), L.T("можно прямо в игре", "works right in the game"), "gfxsave");
    }

    // ── Настройки ──
    static string Set(string key, bool on) { return "set:" + key + "=" + (on ? "on" : "off"); }

    static void Settings(StackPanel b) {
        var s = Ctl.Cur;
        b.Children.Add(Ui.Toggle(L.T("Автоперенос", "Auto-apply"), s.AutoApply, on => { s.AutoApply = on; Ctl.DoAction(Set("autoApply", on), false); }));
        b.Children.Add(Ui.Toggle(L.T("Уведомления", "Notifications"), s.Notify, on => { s.Notify = on; Ctl.DoAction(Set("notify", on), false); }));
        b.Children.Add(Ui.Toggle(L.T("Значок у клиента", "Badge on the client"), s.Badge, on => { s.Badge = on; Ctl.DoAction(Set("badge", on), false); }));
        if (OverlayWin.FsMode < 0) OverlayWin.ReadFsMode();
        b.Children.Add(Ui.Toggle(L.T("Кнопка поверх игры", "Button over the game"), OverlayWin.Enabled(), on => { s.Overlay = on; Ctl.DoAction(Set("overlay", on), false); }));
        if (OverlayWin.FsMode == 0) b.Children.Add(Ui.Note(L.T("Работает в режиме „Оконный полноэкранный“ (сейчас в игре — „Полноэкранный“). В меню игры — Ctrl+Alt+S: «Все скины».",
                                                                "Works in “Windowed Fullscreen” (the game is in “Fullscreen” now). In the game menu — Ctrl+Alt+S: All skins.")));
        b.Children.Add(Ui.Toggle(L.T("Автозапуск", "Start with Windows"), Config.IsAutostart(), on => { Config.SetAutostart(on); Ctl.DoAction(Set("app", on), false); }));

        var lang = new Grid { Margin = new Thickness(10, 8, 10, 4) };
        lang.ColumnDefinitions.Add(new ColumnDefinition());
        lang.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var lt = Ui.Tb(L.T("Язык", "Language"), 13.5, 0xE8E8E8, null); lt.VerticalAlignment = VerticalAlignment.Center;
        lang.Children.Add(lt);
        var seg = new StackPanel { Orientation = Orientation.Horizontal };
        seg.Children.Add(LangBtn("RU", "ru", !L.En)); seg.Children.Add(LangBtn("EN", "en", L.En));
        Grid.SetColumn(seg, 1); lang.Children.Add(seg);
        b.Children.Add(lang);

        b.Children.Add(Ui.Sep(8, 6));
        b.Children.Add(Ui.Row(L.T("Открыть папку", "Open folder"), "%USERPROFILE%\\valset", "", 0, OpenFolder));
        b.Children.Add(Ui.Row(L.T("Консоль (запасная)", "Console (fallback)"), "", "", 0, () => { P.HidePanel(); Core.Console(""); }));
    }

    static UIElement LangBtn(string text, string code, bool active) {
        var x = Ui.Btn(text, 12.5, active ? 0xFFFFFFu : 0xB0B0B0u, active ? 0x3D8BFDu : 0x333333u, active ? 0x5A9DFEu : 0x404040u, true, () => {
            if (active) return;
            L.En = code == "en"; Ctl.Cur.Lang = code; Ctl.DoAction("set:lang=" + code, false);
        }, 26, 5);
        x.Margin = new Thickness(3, 0, 0, 0); x.MinWidth = 44; return x;
    }

    static void OpenFolder() {
        try {
            string dir = System.IO.Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE") ?? "", "valset");
            Directory.CreateDirectory(dir);
            Process.Start(new ProcessStartInfo("explorer.exe", "\"" + dir + "\"") { UseShellExecute = true });
        } catch (Exception e) { Dbg.Log("папка: " + e.Message); }
    }

    // ── Справка ──
    static void Help(StackPanel b) {
        string[][] t = {
            new[] { "Сохрани настройки один раз на главном аккаунте — потом применяй их на остальных.", "Save your settings once on the main account, then apply them on the others." },
            new[] { "Войдёшь в аккаунт — настройки перенесутся сами (если включён автоперенос).", "When you log in, settings are applied automatically (if auto-apply is on)." },
            new[] { "Правки в игре на твоих аккаунтах подхватываются и сохраняются после игры.", "In-game changes on your accounts are picked up and saved after the game." },
            new[] { "На чужом аккаунте настройки ставятся на время: после игры вернутся исходные.", "On someone else's account settings are temporary: originals return after the game." },
            new[] { "Про: настройки про-игрока примеряются на время, потом можно отменить.", "Pros: a pro's settings are a temporary try-on, you can undo it." },
            new[] { "Код для друга: «Поделиться» копирует код твоих настроек; друг вставляет его у себя и сначала видит, что изменится.", "Share code: “Share” copies a code of your settings; your friend pastes it and first sees what changes." },
            new[] { "Скины: сохрани текущие скины, брелоки, спреи, карточку, титул и рамку как набор и надевай одним нажатием; набор можно привязать к агенту.", "Skins: save your current skins, buddies, sprays, card, title and border as a set and put it on in one click; a set can be bound to an agent." },
            new[] { "Любое действие отменяется сразу («Готово · Отменить») или позже в Бэкапах.", "Any action can be undone right away (\"Done · Undo\") or later in Backups." },
            new[] { "Цвет значка: зелёный — твои, жёлтый — есть действие, синий — игра, серый — клиента нет.", "Icon colour: green — yours, amber — action needed, blue — game, grey — no client." }
        };
        foreach (var x in t) {
            var tb = Ui.Tb("•  " + L.T(x[0], x[1]), 12.5, 0xD0D0D0, null); tb.Margin = new Thickness(6, 0, 6, 8);
            b.Children.Add(tb);
        }
    }
}
