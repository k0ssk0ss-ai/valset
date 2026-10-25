// PagesLists.cs — страницы-списки (Что отличается, Про, Аккаунты, Бэкапы): загрузка ядром в фоне, кэш на время открытия панели.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;

static class Lists {
    static readonly Dictionary<string, List<Dictionary<string, object>>> cache = new Dictionary<string, List<Dictionary<string, object>>>();
    static readonly HashSet<string> loading = new HashSet<string>(), failed = new HashSet<string>();
    static int gen;
    public static bool HistoryTab;         // Бэкапы: «моих настроек»
    public static string Confirm;          // ключ строки, ждущей «Вернуть? Да / Нет»

    // Панель открыли заново / что-то записали — списки устарели.
    public static void Reset() { cache.Clear(); failed.Clear(); loading.Clear(); gen++; ResetView(); }
    public static void ResetView() { Confirm = null; }
    public static bool Failed(string name) { return failed.Contains(name); }
    public static void Retry(string name) { failed.Remove(name); cache.Remove(name); Ctl.Raise(); }

    // Есть в кэше — вернуть; нет — запустить загрузку и вернуть null (панель перерисуется по готовности).
    public static List<Dictionary<string, object>> Get(string name) {
        List<Dictionary<string, object>> r;
        if (cache.TryGetValue(name, out r)) return r;
        if (failed.Contains(name) || loading.Contains(name)) return null;
        loading.Add(name); int g = gen;
        Ctl.Post(() => {
            var list = Json.ParseArray(Core.Run("list " + name, null, 60000));
            Ctl.Ui.BeginInvoke(new Action(() => {
                if (g != gen) { Ctl.Raise(); return; }   // сброс по пути: просим перерисовку, список запросится заново
                loading.Remove(name);
                if (list == null) failed.Add(name); else cache[name] = list;
                Ctl.Raise();
            }));
        });
        return null;
    }
}

static class PagesLists {
    // Загрузилось? Иначе в b уже добавлен «…» или ошибка.
    public static List<Dictionary<string, object>> Load(string name, StackPanel b) {
        var l = Lists.Get(name);
        if (l != null) return l;
        if (Lists.Failed(name)) {
            b.Children.Add(Ui.Note(L.T("Не удалось загрузить список", "Could not load the list")));
            b.Children.Add(Ui.Row(L.T("Повторить", "Retry"), "", "", 0, () => Lists.Retry(name)));
        } else b.Children.Add(Ui.Loading());
        return null;
    }

    public static void Diff(StackPanel b) {
        var l = Load("diff", b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Отличий нет", "No differences"))); return; }
        foreach (var d in l) {
            string o = Json.Str(d, "old"), n = Json.Str(d, "new");
            b.Children.Add(Ui.Row(Json.Str(d, "what"), (o.Length > 0 ? o : "—") + " → " + (n.Length > 0 ? n : "—"), "", 0, null));
        }
    }

    public static void Pros(StackPanel b) {
        var l = Load("pros", b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Список пуст", "The list is empty"))); return; }
        // чувствительность про пересчитывается под твой DPI — без него ядро откажет
        if (l.Exists(x => Json.Bool(x, "needsDpi"))) {
            b.Children.Add(Ui.Note(L.T("Сначала выбери DPI своей мыши:", "First pick your mouse DPI:")));
            b.Children.Add(DpiRow());
        }
        foreach (var d in l) {
            string nick = Json.Str(d, "nick"), label = Json.Str(d, "label"), team = Json.Str(d, "team"), hint = Json.Str(d, "hint");
            string title = label.Length > 0 ? label : (team.Length > 0 ? nick + " · " + team : nick);
            b.Children.Add(Ui.Row(title, hint, "", 0, () => Share.Open("pro", nick)));   // сначала предпросмотр, запись — по кнопке
        }
    }

    public static UIElement DpiRow() {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 8) };
        foreach (var dpi in new[] { "400", "800", "1600", "3200" }) {
            string v = dpi;
            var btn = Ui.Btn(v, 13, 0xFFFFFF, 0x2D2D2D, 0x3A3A3A, true, () => Ctl.DoAction("set:dpi=" + v, false), 30, 6);
            btn.Width = 64; btn.Margin = new Thickness(0, 0, 6, 0);
            row.Children.Add(btn);
        }
        return row;
    }

    static bool IsOk(string st) {
        string s = st.ToLowerInvariant();
        return s == "ok" || s == "same" || s == "mine" || s == "yours" || s == "true" || s == "√" || s == "synced" || s == "match";
    }

    public static void Accounts(StackPanel b) {
        var l = Load("accounts", b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Аккаунтов нет", "No accounts"))); return; }
        foreach (var d in l) {
            string st = Json.Str(d, "state"), puuid = Json.Str(d, "puuid"), name = Json.Str(d, "name"), chk = Json.Str(d, "checked");
            var sub = new List<string>();
            if (Json.Bool(d, "main")) sub.Add(L.T("главный", "main"));
            if (d.ContainsKey("own") && !Json.Bool(d, "own")) sub.Add(L.T("не твой", "not yours"));
            if (st.Length > 2 && !IsOk(st)) sub.Add(st);
            if (chk.Length > 0) sub.Add(L.T("проверен ", "checked ") + chk);
            string mark = st.Length == 0 ? "" : (IsOk(st) ? "√" : "‼");
            var box = new StackPanel { Margin = new Thickness(0, 0, 0, 6) };
            box.Children.Add(Ui.Row(name.Length > 0 ? name : puuid, string.Join(" · ", sub.ToArray()), mark, mark == "√" ? Ctl.Green : Ctl.Amber, null));
            var wrap = new WrapPanel { Margin = new Thickness(6, 0, 0, 0) };
            foreach (var a in Json.Dicts(Json.Get(d, "actions"))) {
                string aid = Json.Str(a, "id"), pid = puuid;
                var btn = Ui.Btn(Json.Str(a, "label"), 12, 0xE8E8E8, 0x333333, 0x404040, true, () => Ctl.DoAction("account:" + pid + ":" + aid, false), 26, 5);
                btn.Margin = new Thickness(4, 0, 0, 4); wrap.Children.Add(btn);
            }
            if (wrap.Children.Count > 0) box.Children.Add(wrap);
            b.Children.Add(box);
        }
    }

    public static void Backups(StackPanel b) {
        var tabs = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        tabs.ColumnDefinitions.Add(new ColumnDefinition()); tabs.ColumnDefinitions.Add(new ColumnDefinition());
        tabs.Children.Add(Tab(L.T("аккаунта", "account"), 0, !Lists.HistoryTab));
        tabs.Children.Add(Tab(L.T("моих настроек", "my settings"), 1, Lists.HistoryTab));
        b.Children.Add(tabs);
        string name = Lists.HistoryTab ? "history" : "backups";
        var l = Load(name, b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Пока пусто", "Nothing yet"))); return; }
        foreach (var d in l) {
            string id = Json.Str(d, "id"), when = Json.Str(d, "when"), why = Json.Str(d, "why"), acc = Json.Str(d, "account");
            bool cur = Json.Bool(d, "current");
            string sub = (!Lists.HistoryTab && acc.Length > 0 ? acc + " · " : "") + why;
            string key = name + ":" + id, doId = (Lists.HistoryTab ? "history:" : "restore:") + id;
            if (Lists.Confirm == key) { b.Children.Add(ConfirmRow(when, sub, doId)); continue; }
            Action click = cur ? (Action)null : () => { Lists.Confirm = key; Ctl.Panel.Refresh(); };
            b.Children.Add(Ui.Row(when.Length > 0 ? when : id, sub, cur ? L.T("сейчас", "now") : "", Ctl.Green, click));
        }
    }

    static UIElement Tab(string text, int col, bool active) {
        var t = Ui.Btn(text, 12.5, active ? 0xFFFFFFu : 0xB0B0B0u, active ? 0x3D8BFDu : 0x2A2A2Au, active ? 0x5A9DFEu : 0x363636u, true, () => {
            if (active) return; Lists.HistoryTab = col == 1; Lists.ResetView(); Ctl.Panel.Refresh();
        }, 28, 5);
        t.Margin = new Thickness(col == 0 ? 0 : 2, 0, col == 0 ? 2 : 0, 0);
        Grid.SetColumn(t, col); return t;
    }

    static UIElement ConfirmRow(string when, string sub, string doId) {
        var box = new Border { Background = Ui.Br(0x2B2B2B), CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 6, 10, 8), Margin = new Thickness(0, 0, 0, 2) };
        var sp = new StackPanel();
        sp.Children.Add(Ui.Tb(L.T("Вернуть: ", "Restore: ") + when + "?", 13.5, 0xFFFFFF, FontWeights.SemiBold));
        if (sub.Length > 0) sp.Children.Add(Ui.Tb(sub, 11.5, 0x9A9A9A, null));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        var yes = Ui.Btn(L.T("Да", "Yes"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, true, () => { Lists.Confirm = null; Ctl.DoAction(doId, false); }, 26, 5); yes.MinWidth = 60;
        var no = Ui.Btn(L.T("Нет", "No"), 12.5, 0xE0E0E0, 0x3A3A3A, 0x484848, true, () => { Lists.Confirm = null; Ctl.Panel.Refresh(); }, 26, 5); no.MinWidth = 60;
        no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no); sp.Children.Add(r);
        box.Child = sp; return box;
    }
}
