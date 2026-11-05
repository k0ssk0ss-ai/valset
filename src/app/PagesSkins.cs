// PagesSkins.cs — «Все скины»: что есть на аккаунте (ядро — skins.ps1, `list skins`), по вкладкам: оружие → скины
// с цветом и уровнем, коллекции (PagesColl.cs), брелоки, спреи, флексы, карточки, титулы. Выбранное — предпросмотр «было → станет» (PagesShare.cs,
// вид skin), надеть — кнопкой в нём (бэкап и «Отменить», как у наборов). Картинки — Img.cs, только видимые.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

static class Skins {
    public static string Tab = "gun";
    static string gunId = "", gunName = "";
    static string open = "", selLv = "", selCh = "";                // раскрытый скин: выбранные уровень и цвет
    static string pickId = "", pickType = "", pickName = "";         // спрей/флекс ждёт выбора слота
    static TextBox find; static bool typing;                         // поиск живёт между перерисовками панели
    const string TSpray = "d5f120f8-ff8c-4aac-92ea-f2b5acbe9475", TFlex = "03a572de-4234-31ed-d344-ababa488f981";

    public static string Title(string page) { return page == "skinsgun" ? gunName : L.T("Все скины", "All skins"); }

    static List<Dictionary<string, object>> Data(StackPanel b) {
        var l = PagesLists.Load("skins", b); if (l == null) return null;
        string err = l.Count > 0 ? Json.Str(l[0], "error") : "";
        if (err.Length > 0) { b.Children.Add(Ui.Note(err)); b.Children.Add(Ui.Row(L.T("Повторить", "Retry"), "", "", 0, () => Lists.Retry("skins"))); return null; }
        return l;
    }

    // ── вкладки ──
    public static void Page(StackPanel b) {
        if (OverlayWin.FsMode < 0) OverlayWin.ReadFsMode();
        Hint(b);
        var tabs = new WrapPanel { Margin = new Thickness(0, 0, 0, 6) };
        foreach (var t in new[] { new[] { "gun", "Оружие", "Weapons" }, new[] { "coll", "Коллекции", "Collections" }, new[] { "buddy", "Брелоки", "Buddies" }, new[] { "spray", "Спреи", "Sprays" },
                                  new[] { "flex", "Флексы", "Flex" }, new[] { "card", "Карточки", "Cards" }, new[] { "title", "Титулы", "Titles" } }) {
            string id = t[0]; bool on = Tab == id;
            var x = Ui.Btn(L.T(t[1], t[2]), 12, on ? 0xFFFFFFu : 0xD0D0D0u, on ? 0x3D8BFDu : 0x2E2E2Eu, on ? 0x5A9DFEu : 0x3A3A3Au, true,
                () => { if (Tab == id) return; Tab = id; pickId = ""; if (find != null) find.Text = ""; typing = false; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh(); }, 26, 5);
            x.Margin = new Thickness(0, 0, 4, 4); tabs.Children.Add(x);
        }
        b.Children.Add(tabs);
        if (Tab == "coll") Colls.List(b);   // свой список (collections.ps1), PagesColl.cs
        else {
            var l = Data(b); if (l == null) return;
            if (Tab == "gun") Weapons(b, l);
            else if (Tab == "title") Titles(b, l);
            else Tiles(b, l, Tab);
        }
        b.Children.Add(Ui.Sep(8, 4));
        b.Children.Add(Ui.Row(L.T("Сохранить текущие как набор", "Save current as a set"), L.T("всё, что надето сейчас, — в «Скины»", "everything on now — to Skins"), "", 0, Sets.StartNaming));
    }

    // Одноразовая подсказка: игра в режиме «Полноэкранный» — кнопки поверх игры не будет.
    static void Hint(StackPanel b) {
        if (OverlayWin.FsMode != 0 || Ctl.Cur.OverlayHint) return;
        var box = new Border { Background = Ui.Br(0x2B2B2B), CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 6, 10, 8), Margin = new Thickness(0, 0, 0, 8) };
        var sp = new StackPanel();
        sp.Children.Add(Ui.Tb(L.T("Кнопка поверх игры работает в режиме „Оконный полноэкранный“", "The button over the game works in “Windowed Fullscreen” mode"), 12.5, 0xFFFFFF, FontWeights.SemiBold));
        sp.Children.Add(Ui.Tb(L.T("Сейчас в игре — „Полноэкранный“: окно поверх свернуло бы игру. Сменить: настройки игры → Видео → Режим экрана. А пока — Ctrl+Alt+S в меню игры откроет «Все скины» (игра свернётся, пока открыта панель).",
                                  "The game is in “Fullscreen” now: a window on top would minimize it. Change it: game settings → Video → Display mode. Meanwhile Ctrl+Alt+S in the game menu opens All skins (the game minimizes while the panel is open)."), 12, 0xB0B0B0, null));
        var ok = Ui.Btn(L.T("Понятно", "Got it"), 12, 0xFFFFFF, 0x3A3A3A, 0x484848, true, () => { Config.SetBool("overlayHint", true); Ctl.Cur.OverlayHint = true; Ctl.Panel.Refresh(); }, 26, 5);
        ok.HorizontalAlignment = HorizontalAlignment.Left; ok.Margin = new Thickness(0, 6, 0, 0);
        sp.Children.Add(ok);
        box.Child = sp; b.Children.Add(box);
    }

    // ── поиск ──
    public static void FindBox(StackPanel b) {
        if (find == null) {
            find = new TextBox { FontSize = 13, Padding = new Thickness(6, 3, 6, 3), Margin = new Thickness(0, 0, 0, 6),
                                 Background = Ui.Br(0x2B2B2B), Foreground = Ui.Br(0xFFFFFF), CaretBrush = Ui.Br(0xFFFFFF), BorderBrush = Ui.Br(0x444444) };
            find.TextChanged += (s, e) => { typing = true; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh(); };
        }
        var p = find.Parent as Panel; if (p != null) p.Children.Remove(find);
        b.Children.Add(Ui.Tb(L.T("Поиск", "Search"), 11.5, 0x9A9A9A, null));
        b.Children.Add(find);
        if (typing) { var tb = find; tb.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => { tb.Focus(); Keyboard.Focus(tb); tb.CaretIndex = tb.Text.Length; })); }
    }

    public static string Query() { return find != null ? find.Text.Trim() : ""; }

    static bool Match(Dictionary<string, object> d) {
        string q = Query();
        return q.Length == 0 || Json.Str(d, "name").IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    // ── строка с картинкой ──
    static Border ImgRow(string icon, double w, double h, string title, string sub, bool on, Action click) {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(w + 10) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var im = Img.Make(icon, w, h); im.HorizontalAlignment = HorizontalAlignment.Left;
        g.Children.Add(im);
        var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var t = Ui.Tb(title, 13, 0xFFFFFF, FontWeights.SemiBold); t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap;
        sp.Children.Add(t);
        if (sub.Length > 0) { var s = Ui.Tb(sub, 11.5, 0x9A9A9A, null); s.TextTrimming = TextTrimming.CharacterEllipsis; s.TextWrapping = TextWrapping.NoWrap; sp.Children.Add(s); }
        Grid.SetColumn(sp, 1); g.Children.Add(sp);
        if (on) { var c = Ui.Tb("✓", 13, Ctl.Green, FontWeights.SemiBold); c.VerticalAlignment = VerticalAlignment.Center; c.Margin = new Thickness(6, 0, 0, 0); Grid.SetColumn(c, 2); g.Children.Add(c); }
        var b = new Border { Child = g, CornerRadius = new CornerRadius(6), Padding = new Thickness(6, 4, 8, 4), Margin = new Thickness(0, 0, 0, 2), Background = Brushes.Transparent };
        Ui.Hover(b, 0, 0x2B2B2B, click != null, click);
        return b;
    }

    // ── оружие ──
    static void Weapons(StackPanel b, List<Dictionary<string, object>> l) {
        foreach (var d in l) {
            if (Json.Str(d, "cat") != "weapon") continue;
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name");
            b.Children.Add(ImgRow(Json.Str(d, "icon"), 96, 30, nm, Json.Str(d, "skin"), false, () => { gunId = id; gunName = nm; open = ""; if (find != null) find.Text = ""; typing = false; Ctl.Panel.Go("skinsgun"); }));
        }
    }

    public static void Gun(StackPanel b) {
        var l = Data(b); if (l == null) return;
        var list = l.FindAll(d => Json.Str(d, "cat") == "skin" && Json.Str(d, "w") == gunId);
        if (list.Count > 10) FindBox(b);
        foreach (var d in list) {
            if (!Match(d)) continue;
            string id = Json.Str(d, "id");
            var lv = Json.Dicts(Json.Get(d, "lv")); var ch = Json.Dicts(Json.Get(d, "ch"));
            bool on = Json.Bool(d, "on");
            string sub = on ? L.T("надет", "on") : Json.Bool(d, "def") ? L.T("стандартный", "standard") : "";
            if (ch.Count > 1) sub += (sub.Length > 0 ? " · " : "") + L.Plural(ch.Count, "цвет", "цвета", "цветов", "variant", "variants");
            b.Children.Add(ImgRow(Json.Str(d, "icon"), 110, 34, Json.Str(d, "name"), sub, on, () => {
                if (open == id) { open = ""; Ctl.Panel.Refresh(); return; }
                open = id;
                selLv = Json.Str(d, "curLv"); if (selLv.Length == 0 && lv.Count > 0) selLv = Json.Str(lv[lv.Count - 1], "id");
                selCh = Json.Str(d, "curCh"); if (selCh.Length == 0 && ch.Count > 0) selCh = Json.Str(ch[0], "id");
                if (lv.Count <= 1 && ch.Count <= 1) { open = ""; Share.Open("skin", Spec(id)); return; }
                Ctl.Panel.Refresh();
            }));
            if (open == id) b.Children.Add(Choose(id, lv, ch));
        }
    }

    static string Spec(string skin) { return "gun:" + gunId + ":" + skin + ":" + selLv + ":" + selCh; }

    // Выбор цвета (образцы) и уровня (номера), потом — предпросмотр.
    static UIElement Choose(string skin, List<Dictionary<string, object>> lv, List<Dictionary<string, object>> ch) {
        var sp = new StackPanel { Margin = new Thickness(12, 2, 0, 8) };
        if (ch.Count > 1) {
            var row = new WrapPanel();
            string cur = "";
            foreach (var c in ch) {
                string cid = Json.Str(c, "id"); bool sel = cid == selCh; if (sel) cur = Json.Str(c, "name");
                var cell = new Border { Child = Img.Make(Json.Str(c, "sw"), 24, 24), Padding = new Thickness(2), Margin = new Thickness(0, 0, 4, 4), CornerRadius = new CornerRadius(4),
                                        BorderThickness = new Thickness(2), BorderBrush = sel ? Ui.Br(0x3D8BFD) : Ui.Br(0x333333), ToolTip = Json.Str(c, "name"), Cursor = Cursors.Hand, Background = Ui.Br(0x2B2B2B) };
                cell.MouseLeftButtonUp += (s, e) => { selCh = cid; Ctl.Panel.Refresh(); };
                row.Children.Add(cell);
            }
            sp.Children.Add(row);
            sp.Children.Add(Ui.Tb(cur, 11.5, 0x9A9A9A, null));
        }
        if (lv.Count > 1) {
            var row = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
            row.Children.Add(Ui.Tb(L.T("Уровень ", "Level "), 12, 0x9A9A9A, null));
            foreach (var v in lv) {
                string vid = Json.Str(v, "id"); bool sel = vid == selLv;
                var x = Ui.Btn(Json.Str(v, "n"), 12, 0xFFFFFF, sel ? 0x3D8BFDu : 0x333333u, sel ? 0x5A9DFEu : 0x404040u, true, () => { selLv = vid; Ctl.Panel.Refresh(); }, 24, 5);
                x.Margin = new Thickness(4, 0, 0, 4); x.MinWidth = 28; row.Children.Add(x);
            }
            sp.Children.Add(row);
        }
        var go = Ui.Btn(L.T("Что изменится →", "What changes →"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, !Ctl.Busy, () => Share.Open("skin", Spec(skin)), 28, 5);
        go.HorizontalAlignment = HorizontalAlignment.Left; go.Margin = new Thickness(0, 6, 0, 0);
        sp.Children.Add(go);
        return sp;
    }

    // ── брелоки, спреи, флексы, карточки: плитки ──
    static void Tiles(StackPanel b, List<Dictionary<string, object>> l, string cat) {
        if (cat == "buddy") b.Children.Add(Ui.Note(L.T("Брелоки — только посмотреть: как Riot хранит брелок на оружии (лоадаут v3), ещё не измерено — надень брелок в игре.",
                                                      "Buddies are view-only for now: how Riot stores a buddy on a weapon (loadout v3) is not measured yet — equip it in the game.")));
        if ((cat == "spray" || cat == "flex") && pickId.Length > 0) { Slots(b, l); return; }
        var list = l.FindAll(d => Json.Str(d, "cat") == cat);
        if (list.Count == 0) { b.Children.Add(Ui.Note(L.T("На аккаунте пусто", "Nothing on the account"))); return; }
        if (list.Count > 12) FindBox(b);
        var g = new UniformGrid { Columns = 4 };
        foreach (var d in list) {
            if (!Match(d)) continue;
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name"); bool on = Json.Bool(d, "on");
            var sp = new StackPanel();
            sp.Children.Add(Img.Make(Json.Str(d, "icon"), 60, 60));
            var t = Ui.Tb(nm, 10.5, on ? 0x7FD99Au : 0xB0B0B0u, null); t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; t.HorizontalAlignment = HorizontalAlignment.Center; t.Margin = new Thickness(0, 2, 0, 0);
            sp.Children.Add(t);
            var cell = new Border { Child = sp, Padding = new Thickness(3, 4, 3, 3), Margin = new Thickness(1), CornerRadius = new CornerRadius(6), ToolTip = nm,
                                    Background = on ? Ui.Br(0x24364F) : (Brush)Brushes.Transparent };
            Action click = null;
            if (cat == "card") click = () => Share.Open("skin", "card:" + id);
            else if (cat == "spray" || cat == "flex") click = () => { pickId = id; pickType = cat == "flex" ? TFlex : TSpray; pickName = nm; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh(); };
            if (click != null) Ui.Hover(cell, on ? 0x24364Fu : 0u, 0x2E2E2E, true, click);
            g.Children.Add(cell);
        }
        b.Children.Add(g);
    }

    // Спрей/флекс выбран — в какой слот колеса (порядок — как в игре).
    static void Slots(StackPanel b, List<Dictionary<string, object>> l) {
        b.Children.Add(Ui.Note("«" + pickName + "» — " + L.T("в какой слот?", "which slot?")));
        foreach (var s in Json.Dicts(Json.Get(l[0], "slots"))) {
            int i = Json.Int(s, "i");
            string what = (i + 1) + ". " + (Json.Str(s, "type") == "flex" ? L.T("Флекс", "Flex") : L.T("Спрей", "Spray"));
            b.Children.Add(Ui.Row(what, Json.Str(s, "name"), "", 0, () => { string spec = "expr:" + i + ":" + pickType + ":" + pickId; pickId = ""; Share.Open("skin", spec); }));
        }
        b.Children.Add(Ui.Row(L.T("Отмена", "Cancel"), "", "", 0, () => { pickId = ""; Ctl.Panel.Refresh(); }));
    }

    // ── титулы: строки ──
    static void Titles(StackPanel b, List<Dictionary<string, object>> l) {
        var list = l.FindAll(d => Json.Str(d, "cat") == "title");
        if (list.Count > 12) FindBox(b);
        foreach (var d in list) {
            if (!Match(d)) continue;
            string id = Json.Str(d, "id");
            b.Children.Add(Ui.Row(Json.Str(d, "name"), "", Json.Bool(d, "on") ? "✓" : "", Ctl.Green, () => Share.Open("skin", "title:" + id)));
        }
    }
}
