// Pages.cs — страницы панели: Главная, Применить, Сохранить, Настройки, Справка (код для друга — PagesShare.cs, скины — PagesSets.cs).
using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;

static class Pages {
    static PanelWin P { get { return Ctl.Panel; } }

    public static string Title(string page) {
        switch (page) {
            case "apply": return L.T("Перенести", "Apply");
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
            case "skins": return Skins.Title(page);
            case "skinscoll": return Colls.Name;
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
            case "help": Help(b); break;
        }
    }

    // ── Главная — PagesHome.cs ──
    public static void Home(StackPanel sp) { PagesHome.Build(sp); }

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
        if (OverlayWin.FsMode == 0) b.Children.Add(Ui.Note(L.T("Работает в режиме «Оконный полноэкранный». Сейчас в игре «Полноэкранный». В меню игры нажми Ctrl+Alt+S: откроются «Все скины».",
                                                                "Works in “Windowed Fullscreen”. The game is in “Fullscreen” now. In the game menu press Ctrl+Alt+S to open All skins.")));
        b.Children.Add(Ui.Toggle(L.T("Автозапуск", "Start with Windows"), Config.IsAutostart(), on => { Config.SetAutostart(on); Ctl.DoAction(Set("app", on), false); }));

        var lang = new Grid { Margin = new Thickness(8, 4, 8, 4) };
        lang.ColumnDefinitions.Add(new ColumnDefinition());
        lang.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var lt = Ui.Tb(L.T("Язык", "Language"), 13, Ui.T1, null); lt.VerticalAlignment = VerticalAlignment.Center;
        lang.Children.Add(lt);
        var seg = Ui.Seg(LangBtn("RU", "ru", !L.En), LangBtn("EN", "en", L.En));
        Grid.SetColumn(seg, 1); lang.Children.Add(seg);
        b.Children.Add(lang);

        b.Children.Add(Ui.Sep(8, 6));
        b.Children.Add(Ui.Row(L.T("Открыть папку с данными", "Open data folder"), "", "", 0, OpenFolder));
        b.Children.Add(Ui.Row(L.T("Консоль", "Console"), "", "", 0, () => { P.HidePanel(); Core.Console(""); }));
    }

    static Border LangBtn(string text, string code, bool active) {
        return Ui.SegItem(text, active, () => {
            if (active) return;
            L.En = code == "en"; Ctl.Cur.Lang = code; Ctl.DoAction("set:lang=" + code, false);
        });
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
            new[] { "Сохрани настройки на основном аккаунте. Потом переноси их на остальные.", "Save your settings on the main account. Then apply them on the others." },
            new[] { "Войдёшь в аккаунт, и настройки перенесутся сами (если включён автоперенос).", "When you log in, settings are applied automatically (if auto-apply is on)." },
            new[] { "Правки в игре на твоих аккаунтах подхватываются и сохраняются после игры.", "In-game changes on your accounts are picked up and saved after the game." },
            new[] { "На чужом аккаунте настройки ставятся на время: после игры вернутся исходные.", "On someone else's account settings are temporary: originals return after the game." },
            new[] { "Про: настройки про-игрока ставятся на время, их можно отменить.", "Pros: a pro's settings go on for now, you can undo them." },
            new[] { "Код для друга: «Поделиться» копирует код твоих настроек. Друг вставит его и сначала увидит, что изменится.", "Share code: “Share” copies a code of your settings. Your friend pastes it and first sees what changes." },
            new[] { "Скины: сохрани надетое как набор и надевай одним нажатием. Набор можно привязать к агенту.", "Skins: save what you have on as a set and put it on in one click. A set can be bound to an agent." },
            new[] { "Большинство действий можно отменить сразу или позже в «Бэкапах».", "Most actions can be undone right away or later in Backups." },
            new[] { "Цвет значка: зелёный, твои настройки; жёлтый, нужно действие; синий, идёт игра; серый, клиента Riot нет.", "Icon colour: green, your settings; amber, action needed; blue, game running; grey, no Riot Client." }
        };
        foreach (var x in t) {
            var tb = Ui.Tb(L.T(x[0], x[1]), 12, Ui.T2, null); tb.Margin = new Thickness(8, 0, 8, 10);
            b.Children.Add(tb);
        }
    }
}
