// PagesColl.cs — «Все скины» → «Коллекции» (ядро — collections.ps1, `list collections` / `list collection:<id>`).
// Вкладка: карточки коллекций (свои скины — ярко, чужие — тускло, для справки); пустой поиск — только коллекции со своими
// скинами, поиск — по всем. Страница skinscoll: большие картинки оружия, его цвета и уровни,
// «Надеть коллекцию» (предпросмотр «было → станет» — PagesShare.cs, вид coll) и «Сохранить как набор» (PagesSets.cs).
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
        Skins.FindBox(b);
        string q = Skins.Query();
        int shown = 0, more = 0;
        foreach (var d in l) {
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name");
            if (id.Length == 0) continue;
            if (q.Length == 0 ? Json.Int(d, "own") == 0 : nm.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0) continue;
            if (shown >= MaxCards) { more++; continue; }
            b.Children.Add(Card(d)); shown++;
        }
        if (shown == 0) b.Children.Add(Ui.Note(q.Length == 0 ? L.T("Своих коллекций нет — найди любую поиском.", "No collections of your own — search for any.") : L.T("Ничего не нашлось", "Nothing found")));
        if (more > 0) b.Children.Add(Ui.Note(L.T("Ещё " + more + " — уточни поиск.", more + " more — refine the search.")));
        if (q.Length == 0 && shown > 0) b.Children.Add(Ui.Note(L.T("Здесь коллекции, где есть твои скины. Любую другую — поиском (посмотреть, надеть нельзя).", "These are collections with your skins. Any other — by search (to look at, not to put on).")));
    }

    static Border Card(Dictionary<string, object> d) {
        string id = Json.Str(d, "id"), nm = Json.Str(d, "name");
        int own = Json.Int(d, "own"), n = Json.Int(d, "n");
        var sp = new StackPanel();
        var head = new DockPanel();
        var cnt = Ui.Tb(own + " / " + n, 11.5, own > 0 ? Ctl.Green : 0x9A9A9Au, null); cnt.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(cnt, Dock.Right); head.Children.Add(cnt);
        var t = Ui.Tb(nm, 13, 0xFFFFFF, FontWeights.SemiBold); t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap;
        head.Children.Add(t);
        sp.Children.Add(head);
        var w = new WrapPanel { Margin = new Thickness(0, 3, 0, 0) };
        foreach (var x in Json.Dicts(Json.Get(d, "items"))) {
            var im = Img.Make(Json.Str(x, "i"), 64, 22); im.Margin = new Thickness(0, 0, 6, 3);
            if (!Json.Bool(x, "o")) im.Opacity = Dim;
            w.Children.Add(im);
        }
        sp.Children.Add(w);
        var box = new Border { Child = sp, CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 5, 8, 4), Margin = new Thickness(0, 0, 0, 3), Background = Brushes.Transparent };
        Ui.Hover(box, 0, 0x2B2B2B, true, () => Open(id, nm));
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
        b.Children.Add(Ui.Tb(L.T("Своих скинов: ", "Own skins: ") + own + L.T(" из ", " of ") + n + (own < n ? L.T(" · тусклые — для справки, надеть нельзя", " · dim ones are for reference, can't be put on") : ""), 12, 0x9A9A9A, null));
        if (put > 0) {
            var r = new WrapPanel { Margin = new Thickness(0, 6, 0, 6) };
            var go = Ui.Btn(L.T("Надеть коллекцию →", "Put on the collection →"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, !Ctl.Busy, () => Share.Open("coll", Id), 28, 5);
            go.Margin = new Thickness(0, 0, 6, 4); r.Children.Add(go);
            var save = Ui.Btn(L.T("Сохранить как набор", "Save as a set"), 12.5, 0xE8E8E8, 0x333333, 0x404040, !Ctl.Busy, () => Sets.StartNaming(Id, Name), 28, 5);
            save.Margin = new Thickness(0, 0, 0, 4); r.Children.Add(save);
            b.Children.Add(r);
        } else b.Children.Add(Ui.Note(own > 0 ? L.T("Свои скины этой коллекции — на оружии, которого нет в лоадауте.", "Your skins from this collection are for weapons not in the loadout.")
                                               : L.T("Из этой коллекции на аккаунте ничего нет — только посмотреть.", "Nothing from this collection on the account — view only.")));
        for (int i = 1; i < l.Count; i++) Skin(b, l[i]);
    }

    // Скин: большая картинка выбранного цвета, цвета (клик — показать), уровни (свои — светлые).
    static void Skin(StackPanel b, Dictionary<string, object> d) {
        string sid = Json.Str(d, "id"), nm = Json.Str(d, "name");
        bool own = Json.Bool(d, "own"), on = Json.Bool(d, "on");
        var lv = Json.Dicts(Json.Get(d, "lv")); var ch = Json.Dicts(Json.Get(d, "ch"));
        string sel; if (!pick.TryGetValue(sid, out sel) && ch.Count > 0) sel = Json.Str(ch[0], "id");
        Dictionary<string, object> cur = ch.Find(c => Json.Str(c, "id") == sel);
        string icon = cur != null && Json.Str(cur, "icon").Length > 0 ? Json.Str(cur, "icon") : Json.Str(d, "icon");

        var sp = new StackPanel { Margin = new Thickness(0, 8, 0, 2) };
        var t = Ui.Tb(nm, 13, own ? 0xFFFFFFu : 0x9A9A9Au, FontWeights.SemiBold); t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap;
        sp.Children.Add(t);
        string sub = Json.Str(d, "wn") + " · " + (!own ? L.T("нет на аккаунте", "not on the account") : on ? L.T("надет", "on") : L.T("есть", "owned"));
        if (own && !Json.Bool(d, "gun")) sub += L.T(" · оружия нет в лоадауте", " · weapon not in the loadout");
        sp.Children.Add(Ui.Tb(sub, 11.5, on ? Ctl.Green : 0x9A9A9Au, null));
        var big = Img.Make(icon, 280, 80); big.HorizontalAlignment = HorizontalAlignment.Left; big.Margin = new Thickness(0, 4, 0, 4);
        if (!own) big.Opacity = Dim;
        sp.Children.Add(big);

        if (ch.Count > 1) {
            var row = new WrapPanel();
            foreach (var c in ch) {
                string cid = Json.Str(c, "id"); bool cOwn = Json.Bool(c, "own"), isSel = cid == sel;
                var im = Img.Make(Json.Str(c, "icon"), 56, 18); if (!cOwn) im.Opacity = Dim;
                var cell = new Border { Child = im, Padding = new Thickness(3), Margin = new Thickness(0, 0, 4, 4), CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(2),
                                        BorderBrush = isSel ? Ui.Br(0x3D8BFD) : Ui.Br(0x333333), Background = Ui.Br(0x2B2B2B), Cursor = Cursors.Hand,
                                        ToolTip = Json.Str(c, "name") + (cOwn ? "" : L.T(" — нет на аккаунте", " — not on the account")) };
                cell.MouseLeftButtonUp += (s, e) => { pick[sid] = cid; Ctl.Panel.Refresh(); };
                row.Children.Add(cell);
            }
            sp.Children.Add(row);
        }

        if (lv.Count > 1) {   // уровни: свои — светлые, чужие — тусклые (только подпись)
            var row = new WrapPanel { Margin = new Thickness(0, 0, 0, 2) };
            row.Children.Add(Ui.Tb(L.T("Уровни ", "Levels "), 11.5, 0x9A9A9A, null));
            foreach (var v in lv) { var x = Ui.Tb(Json.Str(v, "n") + " ", 11.5, Json.Bool(v, "own") ? 0xE8E8E8u : 0x5A5A5Au, Json.Bool(v, "own") ? FontWeights.SemiBold : (FontWeight?)null); row.Children.Add(x); }
            sp.Children.Add(row);
        }
        b.Children.Add(sp);
    }
}
