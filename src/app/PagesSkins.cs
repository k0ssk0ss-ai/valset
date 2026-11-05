// PagesSkins.cs — «Все скины»: что есть на аккаунте (ядро — skins.ps1, `list skins`), по вкладкам: оружие (слева список,
// справа сцена выбранного скина с цветом и уровнем и сетка своих скинов), коллекции (PagesColl.cs), брелоки, спреи, флексы,
// карточки, титулы. «Надеть» — предпросмотр «было → станет» (PagesShare.cs, вид skin; бэкап и «Отменить», как у наборов).
// Оформление — PagesStage.cs; картинки — Img.cs, только видимые.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;

static class Skins {
    public static string Tab = "gun";
    static string gunId = "", gunName = "";
    static string selId = "", selLv = "", selCh = "";                // скин на сцене: выбранные уровень и цвет
    static string pickId = "", pickType = "", pickName = "";         // спрей/флекс ждёт выбора слота
    static TextBox find; static bool typing;                         // поиск живёт между перерисовками панели
    const string TSpray = "d5f120f8-ff8c-4aac-92ea-f2b5acbe9475", TFlex = "03a572de-4234-31ed-d344-ababa488f981", Vandal = "9c82e19d-4575-0200-1a81-3eacf00cf872";

    public static string Title(string page) { return L.T("Все скины", "All skins"); }

    static List<Dictionary<string, object>> Data(StackPanel b) {
        var l = PagesLists.Load("skins", b); if (l == null) return null;
        string err = l.Count > 0 ? Json.Str(l[0], "error") : "";
        if (err.Length > 0) { b.Children.Add(Ui.Note(err)); b.Children.Add(Ui.Row(L.T("Повторить", "Retry"), "", "", 0, () => Lists.Retry("skins"))); return null; }
        return l;
    }

    // ── каркас окна ──
    public static UIElement Frame(out ScrollViewer pane) {
        if (OverlayWin.FsMode < 0) OverlayWin.ReadFsMode();
        if (find == null) { find = Stage.NewSearchBox(); find.TextChanged += (s, e) => { typing = true; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh(); }; }
        bool coll = Ctl.Panel.Page == "skinscoll";
        var seg = Ui.Seg(TabBtn("gun", "Оружие", "Weapons"), TabBtn("buddy", "Брелоки", "Buddies"), TabBtn("spray", "Спреи", "Sprays"),
                         TabBtn("flex", "Флексы", "Flex"), TabBtn("card", "Карточки", "Cards"), TabBtn("title", "Титулы", "Titles"));
        var top = Stage.Top(L.T("Все скины", "All skins"), seg, Stage.Search(find));
        var l = Lists.Get("skins");
        bool ok = l != null && (l.Count == 0 || Json.Str(l[0], "error").Length == 0);
        UIElement rail = (Tab == "gun" || Tab == "coll" || coll) && ok ? Rail(l, coll) : null;
        StackPanel b;
        var root = Stage.Frame(top, rail, out pane, out b);
        var r = Ui.Result(); if (r != null) { ((FrameworkElement)r).Margin = new Thickness(0, 0, 0, 12); b.Children.Add(r); }
        Hint(b);
        if (coll) Colls.Page(b);
        else if (Tab == "coll") Colls.List(b);
        else {
            var d = Data(b);
            if (d != null) {
                if (Tab == "gun") Weapon(b, d);
                else if (Tab == "title") Titles(b, d);
                else Tiles(b, d, Tab);
            }
        }
        if (typing) { var tb = find; tb.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => { tb.Focus(); Keyboard.Focus(tb); tb.CaretIndex = tb.Text.Length; })); }
        return root;
    }

    static Border TabBtn(string id, string ru, string en) {
        bool on = Tab == id || (id == "gun" && Tab == "coll");
        return Ui.SegItem(L.T(ru, en), on, () => SetTab(id));
    }

    static void SetTab(string id) {
        bool coll = Ctl.Panel.Page == "skinscoll";
        if (Tab == id && !coll) return;
        Tab = id; pickId = ""; find.Text = ""; typing = false; Ctl.Panel.ResetScroll = true;
        if (coll) Ctl.Panel.Back(); else Ctl.Panel.Refresh();
    }

    // Слева: оружие из лоадаута со счётчиком своих скинов, внизу — «Коллекции».
    static UIElement Rail(List<Dictionary<string, object>> l, bool collPage) {
        var sp = new StackPanel();
        var count = new Dictionary<string, int>();
        foreach (var d in l) if (Json.Str(d, "cat") == "skin") { string w = Json.Str(d, "w"); int n; count.TryGetValue(w, out n); count[w] = n + 1; }
        Pick(l);
        foreach (var d in l) {
            if (Json.Str(d, "cat") != "weapon") continue;
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name"); int n; count.TryGetValue(id, out n);
            sp.Children.Add(Stage.RailRow(nm, n > 0 ? n.ToString() : "", Tab == "gun" && !collPage && id == gunId, Ui.T1, () => {
                gunId = id; gunName = nm; selId = ""; find.Text = ""; typing = false; Ctl.Panel.ResetScroll = true;
                if (Tab != "gun" || collPage) { Tab = "gun"; if (collPage) { Ctl.Panel.Back(); return; } }
                Ctl.Panel.Refresh();
            }));
        }
        var cl = Lists.Peek("collections"); int own = 0;
        if (cl != null) foreach (var c in cl) if (Json.Int(c, "own") > 0) own++;
        var foot = Stage.RailRow(L.T("Коллекции", "Collections"), own > 0 ? own.ToString() : "", Tab == "coll" || collPage, Ui.T2, () => {
            if (collPage) { Tab = "coll"; Ctl.Panel.Back(); return; }
            if (Tab == "coll") return;
            Tab = "coll"; find.Text = ""; typing = false; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh();
        });
        return Stage.Rail(sp, foot);
    }

    // Оружие по умолчанию — Vandal (или первое в лоадауте).
    static void Pick(List<Dictionary<string, object>> l) {
        Dictionary<string, object> first = null, cur = null;
        foreach (var d in l) {
            if (Json.Str(d, "cat") != "weapon") continue;
            if (first == null) first = d;
            if (Json.Str(d, "id") == gunId) cur = d;
            else if (cur == null && gunId.Length == 0 && Json.Str(d, "id") == Vandal) cur = d;
        }
        if (cur == null) cur = first;
        if (cur != null) { gunId = Json.Str(cur, "id"); gunName = Json.Str(cur, "name"); }
    }

    // Одноразовая подсказка: игра в режиме «Полноэкранный» — кнопки поверх игры не будет.
    static void Hint(StackPanel b) {
        if (OverlayWin.FsMode != 0 || Ctl.Cur.OverlayHint) return;
        var a = Ui.Ask(L.T("Кнопка поверх игры работает в режиме „Оконный полноэкранный“", "The button over the game works in “Windowed Fullscreen” mode"),
                       L.T("Сейчас в игре — „Полноэкранный“: окно поверх свернуло бы игру. Сменить: настройки игры → Видео → Режим экрана. А пока — Ctrl+Alt+S в меню игры откроет «Все скины» (игра свернётся, пока открыта панель).",
                           "The game is in “Fullscreen” now: a window on top would minimize it. Change it: game settings → Video → Display mode. Meanwhile Ctrl+Alt+S in the game menu opens All skins (the game minimizes while the panel is open)."),
                       Ui.Sec(L.T("Понятно", "Got it"), 12, true, () => { Config.SetBool("overlayHint", true); Ctl.Cur.OverlayHint = true; Ctl.Panel.Refresh(); }, 28, 8));
        a.Margin = new Thickness(0, 0, 0, 12); b.Children.Add(a);
    }

    public static string Query() { return find != null ? find.Text.Trim() : ""; }

    static bool Match(Dictionary<string, object> d) {
        string q = Query();
        return q.Length == 0 || Json.Str(d, "name").IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    // ── оружие: сцена + сетка своих скинов ──
    static void Weapon(StackPanel b, List<Dictionary<string, object>> l) {
        Pick(l);
        var all = l.FindAll(d => Json.Str(d, "cat") == "skin" && Json.Str(d, "w") == gunId);
        var list = all.FindAll(Match);
        Dictionary<string, object> sel = all.Find(d => Json.Str(d, "id") == selId);
        if (sel == null) { sel = all.Find(d => Json.Bool(d, "on")) ?? (all.Count > 0 ? all[0] : null); if (sel != null) Select(sel); }
        if (sel != null) b.Children.Add(Scene(sel, all.IndexOf(sel), all.Count));
        b.Children.Add(Stage.GridHead(L.T("Твои скины на ", "Your skins for ") + gunName, list.Count.ToString()));
        var g = new UniformGrid { Columns = 4, Margin = new Thickness(-4, 0, -4, 0) };
        foreach (var d in list) {
            var x = d;
            g.Children.Add(Stage.Cell(Json.Str(d, "icon"), 104, 40, Short(Json.Str(d, "name")), d == sel, Json.Bool(d, "on"), 1, () => { Select(x); Ctl.Panel.Refresh(); }));
        }
        b.Children.Add(g);
        if (list.Count == 0 && Query().Length > 0) b.Children.Add(Ui.Note(L.T("Ничего не нашлось", "Nothing found")));
        var save = Ui.Sec(L.T("Сохранить надетое как набор", "Save what's on as a set"), 12, !Ctl.Busy, Sets.StartNaming, 30, 8);
        save.HorizontalAlignment = HorizontalAlignment.Left; save.Margin = new Thickness(0, 12, 0, 0);
        b.Children.Add(save);
    }

    // «Vandal "Прайм"» → «Прайм»: имя оружия и так в заголовке.
    static string Short(string name) { return Short(name, gunName); }
    public static string Short(string name, string gun) {
        string s = name;
        if (gun.Length > 0 && s.StartsWith(gun + " ", StringComparison.OrdinalIgnoreCase)) s = s.Substring(gun.Length + 1).Trim();
        s = s.Trim('"', '«', '»', '“', '”', ' ');
        return s.Length > 0 ? s : name;
    }

    // На сцену: надетый — его уровень и цвет; иначе — старший свой уровень и первый цвет.
    static void Select(Dictionary<string, object> d) {
        var lv = Json.Dicts(Json.Get(d, "lv")); var ch = Json.Dicts(Json.Get(d, "ch"));
        selId = Json.Str(d, "id");
        selLv = Json.Str(d, "curLv"); if (selLv.Length == 0 && lv.Count > 0) selLv = Json.Str(lv[lv.Count - 1], "id");
        selCh = Json.Str(d, "curCh"); if (selCh.Length == 0 && ch.Count > 0) selCh = Json.Str(ch[0], "id");
    }

    static UIElement Scene(Dictionary<string, object> d, int idx, int n) {
        string id = Json.Str(d, "id");
        var lv = Json.Dicts(Json.Get(d, "lv")); var ch = Json.Dicts(Json.Get(d, "ch"));
        var curCh = ch.Find(c => Json.Str(c, "id") == selCh);
        string icon = curCh != null && Json.Str(curCh, "icon").Length > 0 ? Json.Str(curCh, "icon") : Json.Str(d, "icon");
        var hero = Img.Make(icon, 400, 120);
        var curLv = lv.Find(v => Json.Str(v, "id") == selLv);
        string sub;
        if (Json.Bool(d, "def")) sub = L.T("Стандартный", "Standard");
        else {
            sub = curLv != null ? L.T("Уровень ", "Level ") + Json.Str(curLv, "n") + L.T(" из ", " of ") + Json.Int(d, "lvN") : "";
            string th = Json.Str(d, "thn");
            if (th.Length > 0) sub += (sub.Length > 0 ? " · " : "") + L.T("коллекция «", "collection “") + th + L.T("»", "”");
        }
        var chips = new StackPanel { Orientation = Orientation.Horizontal };
        var ctl = chips;
        if (ch.Count > 1) foreach (var c in ch) {
            string cid = Json.Str(c, "id");
            ctl.Children.Add(Stage.Chip(Img.Make(Json.Str(c, "sw"), 24, 24), cid == selCh, Json.Str(c, "name"), () => { selCh = cid; Ctl.Panel.Refresh(); }));
        }
        if (lv.Count > 1) foreach (var v in lv) {
            string vid = Json.Str(v, "id"); var t = Ui.MonoTb(Json.Str(v, "n"), 11, vid == selLv ? Ui.T1 : Ui.T2); t.HorizontalAlignment = HorizontalAlignment.Center;
            ctl.Children.Add(Stage.Chip(t, vid == selLv, L.T("Уровень ", "Level ") + Json.Str(v, "n"), () => { selLv = vid; Ctl.Panel.Refresh(); }));
        }
        bool on = Json.Bool(d, "on"), same = on && selLv == Json.Str(d, "curLv") && selCh == Json.Str(d, "curCh");
        var put = Ui.Pri(L.T("Надеть", "Put on"), 13, !Ctl.Busy && !same, () => Share.Open("skin", "gun:" + gunId + ":" + id + ":" + selLv + ":" + selCh), 32, 8);
        put.Margin = new Thickness(12, 0, 0, 0); put.VerticalAlignment = VerticalAlignment.Bottom;
        string tag = gunName.ToUpperInvariant() + " · " + (idx + 1) + L.T(" из ", " of ") + n;
        return Stage.Make(236, Json.Str(d, "bn"), hero, tag, on, Stage.Info(Short(Json.Str(d, "name")), sub), put, chips.Children.Count > 0 ? chips : null);
    }

    // ── брелоки, спреи, флексы, карточки: сетка ──
    static void Tiles(StackPanel b, List<Dictionary<string, object>> l, string cat) {
        if (cat == "buddy") { var n = Ui.Note(L.T("Брелоки — только посмотреть: как Riot хранит брелок на оружии (лоадаут v3), ещё не измерено — надень брелок в игре",
                                                  "Buddies are view-only for now: how Riot stores a buddy on a weapon (loadout v3) is not measured yet — equip it in the game")); n.Margin = new Thickness(0, 0, 0, 8); b.Children.Add(n); }
        if ((cat == "spray" || cat == "flex") && pickId.Length > 0) { Slots(b, l); return; }
        var all = l.FindAll(d => Json.Str(d, "cat") == cat);
        if (all.Count == 0) { b.Children.Add(Ui.Note(L.T("На аккаунте пусто", "Nothing on the account"))); return; }
        var list = all.FindAll(Match);
        b.Children.Add(Stage.GridHead(cat == "buddy" ? L.T("Твои брелоки", "Your buddies") : cat == "spray" ? L.T("Твои спреи", "Your sprays") : cat == "flex" ? L.T("Твои флексы", "Your flex") : L.T("Твои карточки", "Your cards"), list.Count.ToString()));
        var g = new UniformGrid { Columns = 6, Margin = new Thickness(-4, 0, -4, 0) };
        foreach (var d in list) {
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name"); bool on = Json.Bool(d, "on");
            Action click = null;
            if (cat == "card") click = () => Share.Open("skin", "card:" + id);
            else if (cat == "spray" || cat == "flex") click = () => { pickId = id; pickType = cat == "flex" ? TFlex : TSpray; pickName = nm; Ctl.Panel.ResetScroll = true; Ctl.Panel.Refresh(); };
            g.Children.Add(Stage.Cell(Json.Str(d, "icon"), 56, 56, nm, false, on, 1, click));
        }
        b.Children.Add(g);
        if (list.Count == 0) b.Children.Add(Ui.Note(L.T("Ничего не нашлось", "Nothing found")));
    }

    // Спрей/флекс выбран — в какой слот колеса (порядок — как в игре).
    static void Slots(StackPanel b, List<Dictionary<string, object>> l) {
        b.Children.Add(Stage.GridHead("«" + pickName + "» — " + L.T("в какой слот?", "which slot?"), ""));
        foreach (var s in Json.Dicts(Json.Get(l[0], "slots"))) {
            int i = Json.Int(s, "i");
            string what = (i + 1) + " · " + (Json.Str(s, "type") == "flex" ? L.T("флекс", "flex") : L.T("спрей", "spray"));
            b.Children.Add(Ui.Row(what, Json.Str(s, "name"), "", 0, () => { string spec = "expr:" + i + ":" + pickType + ":" + pickId; pickId = ""; Share.Open("skin", spec); }));
        }
        b.Children.Add(Ui.Row(L.T("Отмена", "Cancel"), "", "", 0, () => { pickId = ""; Ctl.Panel.Refresh(); }));
    }

    // ── титулы: строки в две колонки ──
    static void Titles(StackPanel b, List<Dictionary<string, object>> l) {
        var list = l.FindAll(d => Json.Str(d, "cat") == "title" && Match(d));
        b.Children.Add(Stage.GridHead(L.T("Твои титулы", "Your titles"), list.Count.ToString()));
        var g = new UniformGrid { Columns = 2 };
        foreach (var d in list) {
            string id = Json.Str(d, "id");
            g.Children.Add(Ui.Row(Json.Str(d, "name"), "", Json.Bool(d, "on") ? "on" : "", 0, () => Share.Open("skin", "title:" + id)));
        }
        b.Children.Add(g);
    }
}
