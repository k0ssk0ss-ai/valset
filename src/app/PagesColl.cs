// PagesColl.cs — «Все скины» → «Коллекции» (ядро — collections.ps1, `list collections` / `list collection:<id>`).
// Вкладка: карточки коллекций (свои скины — ярко, чужие — тускло, для справки); пустой поиск — только коллекции со своими
// скинами, поиск — по всем. Страница skinscoll: сцена с баннером коллекции, «Надеть коллекцию» (предпросмотр «было → станет» —
// PagesShare.cs, вид coll) и «Сохранить как набор» (PagesSets.cs); ниже — скины: картинка выбранного цвета, цвета и уровни.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

static class Colls {
    public static string Id = "", Name = "";
    static readonly Dictionary<string, string> pick = new Dictionary<string, string>();   // скин → цвет, который показываем
    const int MaxCards = 30;
    const double Dim = 0.33;

    // ── вкладка «Коллекции» ──
    public static void List(StackPanel b) {
        var l = PagesLists.Load("collections", b); if (l == null) return;
        string err = l.Count > 0 ? Json.Str(l[0], "error") : "";
        if (err.Length > 0) { b.Children.Add(Ui.Note(err)); b.Children.Add(Ui.Row(L.T("Повторить", "Retry"), "", "", 0, () => Lists.Retry("collections"))); return; }
        string q = Skins.Query();
        int shown = 0, more = 0;
        var cards = new List<UIElement>();
        foreach (var d in l) {
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name");
            if (id.Length == 0) continue;
            if (q.Length == 0 ? Json.Int(d, "own") == 0 : nm.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0) continue;
            if (shown >= MaxCards) { more++; continue; }
            cards.Add(Card(d)); shown++;
        }
        b.Children.Add(Stage.GridHead(q.Length == 0 ? L.T("Коллекции с твоими скинами", "Collections with your skins") : L.T("Найдено", "Found"), shown.ToString()));
        foreach (var c in cards) b.Children.Add(c);
        if (shown == 0) b.Children.Add(Ui.Note(q.Length == 0 ? L.T("Своих коллекций нет — найди любую поиском", "No collections of your own — search for any") : L.T("Ничего не нашлось", "Nothing found")));
        if (more > 0) b.Children.Add(Ui.Note(L.T("Ещё " + more + " — уточни поиск", more + " more — refine the search")));
        if (q.Length == 0 && shown > 0) b.Children.Add(Ui.Note(L.T("Любую другую коллекцию — поиском: посмотреть можно, надеть нельзя", "Any other collection — by search: to look at, not to put on")));
    }

    static Border Card(Dictionary<string, object> d) {
        string id = Json.Str(d, "id"), nm = Json.Str(d, "name");
        int own = Json.Int(d, "own"), n = Json.Int(d, "n");
        var sp = new StackPanel();
        var head = new DockPanel();
        var cnt = Ui.MonoTb(own + " / " + n, 11, own > 0 ? Ui.T2 : Ui.T3);
        DockPanel.SetDock(cnt, Dock.Right); head.Children.Add(cnt);
        head.Children.Add(Ui.Tb1(nm, 13, Ui.T1, FontWeights.Medium));
        sp.Children.Add(head);
        var w = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        foreach (var x in Json.Dicts(Json.Get(d, "items"))) {
            var im = Img.Make(Json.Str(x, "i"), 64, 22); im.Margin = new Thickness(0, 0, 8, 4);
            if (!Json.Bool(x, "o")) im.Opacity = Dim;
            w.Children.Add(im);
        }
        sp.Children.Add(w);
        var box = Ui.Card(sp, new Thickness(12, 10, 12, 8)); box.Margin = new Thickness(0, 0, 0, 8);
        Ui.Hover(box, Ui.Bg2, Ui.Bg3, true, () => Open(id, nm));
        return box;
    }

    public static void Open(string id, string nm) {
        Id = id; Name = nm; pick.Clear();
        Ctl.Panel.Go("skinscoll");
    }

    // ── страница коллекции ──
    public static void Page(StackPanel b) {
        string kind = "collection:" + Id;
        var l = PagesLists.Load(kind, b); if (l == null) return;
        var info = l.Count > 0 ? l[0] : null;
        string err = info != null ? Json.Str(info, "error") : "";
        if (err.Length > 0) { b.Children.Add(Ui.Note(err)); b.Children.Add(Ui.Row(L.T("Повторить", "Retry"), "", "", 0, () => Lists.Retry(kind))); return; }
        int own = Json.Int(info, "own"), n = Json.Int(info, "n"), put = Json.Int(info, "put");
        string sub = L.T("Своих скинов: ", "Own skins: ") + own + L.T(" из ", " of ") + n;
        StackPanel ctl = null;
        if (put > 0) {
            ctl = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(12, 0, 0, 0) };
            var save = Ui.Sec(L.T("Сохранить как набор", "Save as a set"), 13, !Ctl.Busy, () => Sets.StartNaming(Id, Name), 32, 8);
            save.Margin = new Thickness(0, 0, 8, 0); ctl.Children.Add(save);
            ctl.Children.Add(Ui.Pri(L.T("Надеть коллекцию", "Put on the collection"), 13, !Ctl.Busy, () => Share.Open("coll", Id), 32, 8));
        }
        string bn = Json.Str(info, "bn");
        UIElement hero = null;   // баннера нет — на сцене первый свой скин коллекции
        if (bn.Length == 0) for (int i = 1; i < l.Count && hero == null; i++) if (Json.Bool(l[i], "own")) hero = Img.Make(Json.Str(l[i], "icon"), 300, 80);
        b.Children.Add(Stage.Make(168, bn, hero, L.T("Коллекция", "Collection"), false, Stage.Info(Name, sub), ctl));
        if (put == 0) b.Children.Add(Ui.Note(own > 0 ? L.T("Свои скины этой коллекции — на оружии, которого нет в лоадауте", "Your skins from this collection are for weapons not in the loadout")
                                                     : L.T("Из этой коллекции на аккаунте ничего нет — только посмотреть", "Nothing from this collection on the account — view only")));
        else if (own < n) b.Children.Add(Ui.Note(L.T("Тусклые — для справки, надеть нельзя", "Dim ones are for reference, can't be put on")));
        for (int i = 1; i < l.Count; i++) Skin(b, l[i]);
    }

    // Скин: карточка — большая картинка выбранного цвета, справа имя и состояние, ниже цвета (клик — показать) и уровни (свои — светлые).
    static void Skin(StackPanel b, Dictionary<string, object> d) {
        string sid = Json.Str(d, "id"), nm = Json.Str(d, "name");
        bool own = Json.Bool(d, "own"), on = Json.Bool(d, "on");
        var lv = Json.Dicts(Json.Get(d, "lv")); var ch = Json.Dicts(Json.Get(d, "ch"));
        string sel; if (!pick.TryGetValue(sid, out sel) && ch.Count > 0) sel = Json.Str(ch[0], "id");
        Dictionary<string, object> cur = ch.Find(c => Json.Str(c, "id") == sel);
        string icon = cur != null && Json.Str(cur, "icon").Length > 0 ? Json.Str(cur, "icon") : Json.Str(d, "icon");

        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(232) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        var big = Img.Make(icon, 216, 64); big.HorizontalAlignment = HorizontalAlignment.Left; big.VerticalAlignment = VerticalAlignment.Center;
        if (!own) big.Opacity = Dim;
        g.Children.Add(big);
        var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var head = new StackPanel { Orientation = Orientation.Horizontal };
        head.Children.Add(Ui.Tb1(Skins.Short(nm, Json.Str(d, "wn")), 13, own ? Ui.T1 : Ui.T2, FontWeights.Medium));
        if (on) { var dot = Ui.Dot(Ui.Acc, 6); dot.Margin = new Thickness(8, 0, 0, 0); head.Children.Add(dot); }
        sp.Children.Add(head);
        string sub = Json.Str(d, "wn") + " · " + (!own ? L.T("нет на аккаунте", "not on the account") : on ? L.T("надет", "on") : L.T("есть", "owned"));
        if (own && !Json.Bool(d, "gun")) sub += L.T(" · оружия нет в лоадауте", " · weapon not in the loadout");
        var s = Ui.Tb1(sub, 12, Ui.T2, null); s.Margin = new Thickness(0, 2, 0, 0); sp.Children.Add(s);
        if (lv.Count > 1) {   // уровни: свои — светлые, чужие — тусклые
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
            row.Children.Add(Ui.Tb(L.T("Уровни ", "Levels "), 11, Ui.T3, null));
            foreach (var v in lv) { var x = Ui.MonoTb(Json.Str(v, "n") + " ", 11, Json.Bool(v, "own") ? Ui.T1 : Ui.T3); row.Children.Add(x); }
            sp.Children.Add(row);
        }
        Grid.SetColumn(sp, 1); g.Children.Add(sp);
        var outer = new StackPanel(); outer.Children.Add(g);

        if (ch.Count > 1) {
            var row = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
            foreach (var c in ch) {
                string cid = Json.Str(c, "id"); bool cOwn = Json.Bool(c, "own"), isSel = cid == sel;
                var im = Img.Make(Json.Str(c, "icon"), 56, 18); if (!cOwn) im.Opacity = Dim;
                var cell = new Border { Child = im, Padding = new Thickness(4), Margin = new Thickness(0, 0, 6, 0), CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(isSel ? 1.5 : 1),
                                        BorderBrush = isSel ? Ui.Br(Ui.T1) : Ui.Line, Background = Ui.Br(Ui.Bg3), Cursor = Cursors.Hand,
                                        ToolTip = Json.Str(c, "name") + (cOwn ? "" : L.T(" — нет на аккаунте", " — not on the account")) };
                cell.MouseLeftButtonUp += (o, e) => { pick[sid] = cid; Ctl.Panel.Refresh(); };
                row.Children.Add(cell);
            }
            outer.Children.Add(row);
        }
        var card = Ui.Card(outer, new Thickness(12)); card.Margin = new Thickness(0, 0, 0, 8);
        b.Children.Add(card);
    }
}
