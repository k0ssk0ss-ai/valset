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
    // Уже загружен — вернуть, иначе null (загрузку не запускает).
    public static List<Dictionary<string, object>> Peek(string name) { List<Dictionary<string, object>> r; return cache.TryGetValue(name, out r) ? r : null; }
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
            var btn = Ui.Sec(v, 13, true, () => Ctl.DoAction("set:dpi=" + v, false), 30, 6);
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
            if (Json.Bool(d, "main")) sub.Add(L.T("основной", "main"));
            if (d.ContainsKey("own") && !Json.Bool(d, "own")) sub.Add(L.T("не твой", "not yours"));
            if (st.Length > 2 && !IsOk(st)) sub.Add(st);
            if (chk.Length > 0) sub.Add(L.T("проверен ", "checked ") + chk);
            string mark = st.Length == 0 ? "" : (IsOk(st) ? "on" : "warn");
            var box = new StackPanel { Margin = new Thickness(0, 0, 0, 6) };
            box.Children.Add(Ui.Row(name.Length > 0 ? name : puuid, string.Join(" · ", sub.ToArray()), mark, 0, null));
            var wrap = new WrapPanel { Margin = new Thickness(6, 0, 0, 0) };
            foreach (var a in Json.Dicts(Json.Get(d, "actions"))) {
                string aid = Json.Str(a, "id"), pid = puuid;
                var btn = Ui.Sec(Json.Str(a, "label"), 12, true, () => Ctl.DoAction("account:" + pid + ":" + aid, false), 26, 5);
                btn.Margin = new Thickness(4, 0, 0, 4); wrap.Children.Add(btn);
            }
            if (wrap.Children.Count > 0) box.Children.Add(wrap);
            b.Children.Add(box);
        }
    }

    public static void Backups(StackPanel b) {
        var tabs = Ui.Seg(Tab(L.T("Бэкапы аккаунта", "Account backups"), 0, !Lists.HistoryTab), Tab(L.T("История моих настроек", "My settings history"), 1, Lists.HistoryTab));
        tabs.Margin = new Thickness(8, 0, 0, 8); b.Children.Add(tabs);
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
            b.Children.Add(Ui.Row(when.Length > 0 ? when : id, sub, cur ? L.T("сейчас", "now") : "", 0, click));
        }
    }

    static Border Tab(string text, int col, bool active) {
        return Ui.SegItem(text, active, () => { if (active) return; Lists.HistoryTab = col == 1; Lists.ResetView(); Ctl.Panel.Refresh(); });
    }

    static UIElement ConfirmRow(string when, string sub, string doId) {
        return Ui.Ask(L.T("Вернуть: ", "Restore: ") + when + "?", sub,
                      Ui.Pri(L.T("Да", "Yes"), 12, true, () => { Lists.Confirm = null; Ctl.DoAction(doId, false); }, 28, 8),
                      Ui.Sec(L.T("Нет", "No"), 12, true, () => { Lists.Confirm = null; Ctl.Panel.Refresh(); }, 28, 8));
    }
}
