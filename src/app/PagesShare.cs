// PagesShare.cs — «Код для друга» (переключатель «Добавить надетые скины» → do share:skins) и предпросмотр перед записью: вставка кода (кнопка, ссылка valset:code/<код>)
// и примерка про (список «Про», ссылка valset:pro/<ник>), набор косметики (PagesSets.cs, вид loadout), один предмет («Все скины», PagesSkins.cs, вид skin). Пишет только кнопка в предпросмотре — ссылка сама ничего не применяет.
using System;
using System.Text;
using System.Windows;
using System.Windows.Controls;

static class Share {
    public static string Kind = "", Arg = "";   // предпросмотр: code | pro | loadout | skin и сам код / ник / id набора / предмет

    static string Id() { return Kind + ":" + Arg; }   // одно и то же для `list` (предпросмотр) и `do` (запись)

    // Открыть предпросмотр; список читается заново — облако аккаунта могло поменяться.
    public static void Open(string kind, string arg) {
        Kind = kind; Arg = arg;
        if (!Ctl.Panel.IsVisible) Ctl.Panel.ShowPanel();
        Lists.Retry(Id());
        if (Ctl.Panel.Page == "preview") Ctl.Panel.Refresh(); else Ctl.Panel.Go("preview");
    }

    // Код из текста: от «VALSET» до первого постороннего символа, без пробелов и переносов (их вставляют мессенджеры).
    // Только символы кода — ядро получает его одной строкой аргумента. null — кода нет.
    // VALSET3 (base64url): перенос внутри кода — точка; ядро пробует код с кусками после неё и без них (вдруг это подпись).
    public static string Clean(string t) {
        t = t ?? "";
        int i = t.IndexOf("VALSET", StringComparison.OrdinalIgnoreCase);
        if (i < 0 || t.Length < i + 8) return null;
        bool v3 = t[i + 6] == '3', gap = false;
        var sb = new StringBuilder(t.Substring(i, 8));
        for (int k = i + 8; k < t.Length; k++) {
            char c = t[k];
            if (char.IsWhiteSpace(c)) { gap = true; continue; }
            bool cjk = c >= (char)0x4E00 && c <= (char)0x8DFF, b64 = c < 128 && (char.IsLetterOrDigit(c) || c == '+' || c == '/' || c == '-' || c == '_');
            if (!(cjk || b64 || c == '=')) break;
            if (gap && v3) sb.Append('.');
            gap = false; sb.Append(c);
        }
        return sb.Length > 8 ? sb.ToString() : null;
    }

    // Ссылка valset:code/<код>: префикс можно не писать — иероглифы значат VALSET2, буквы и цифры — VALSET3.
    public static string FromLink(string val) {
        val = val ?? "";
        if (val.IndexOf("VALSET", StringComparison.OrdinalIgnoreCase) >= 0) return Clean(val);
        foreach (char c in val) if (c >= (char)0x4E00 && c <= (char)0x8DFF) return Clean("VALSET2:" + val);
        return Clean("VALSET3:" + val);
    }

    // ── Код для друга ──
    public static bool WithSkins;   // «Добавить надетые скины»: по умолчанию выкл., не запоминается

    public static void Page(StackPanel b) {
        b.Children.Add(Ui.Row(L.T("Поделиться", "Share"), WithSkins ? L.T("скопировать код настроек и надетых скинов", "copy the code of your settings and worn skins") : L.T("скопировать код твоих настроек", "copy your settings code"),
                              "", 0, () => Ctl.DoAction(WithSkins ? "share:skins" : "share", false)));
        b.Children.Add(Ui.Toggle(L.T("Добавить надетые скины", "Add worn skins"), WithSkins, on => { WithSkins = on; Ctl.Panel.Refresh(); }));
        b.Children.Add(Ui.Row(L.T("Вставить код", "Paste code"), L.T("из буфера обмена; сначала покажу, что изменится", "from the clipboard; shows what changes first"), "", 0, Paste));
        b.Children.Add(Ui.Note(L.T("В коде: бинды, чувствительность, прицел, HUD и звук. Надетые скины добавятся, только если включить переключатель, и у друга наденутся те, что у него есть. Без графики и без данных аккаунта. У друга должен быть VALSET.",
                                   "The code holds binds, sensitivity, crosshair, HUD and audio. Worn skins only with the switch on; your friend gets the ones they own. No graphics, no account data. Your friend needs VALSET.")));
    }
    static void Paste() {
        string t = null;
        try { t = Clean(Clipboard.GetText()); } catch (Exception e) { Dbg.Log("буфер: " + e.Message); }
        if (t == null) {
            Ctl.ResultOk = false; Ctl.ResultUndo = false;
            Ctl.ResultMsg = L.T("В буфере обмена нет кода VALSET. Скопируй его целиком.", "No VALSET code in the clipboard. Copy all of it.");
            Ctl.Raise(); return;
        }
        Open("code", t);
    }

    // ── Предпросмотр ──
    public static string Title() {
        return Kind == "pro" ? L.T("Примерить ", "Try on ") + Arg : Kind == "loadout" ? L.T("Надеть набор", "Put on the set") : Kind == "coll" ? L.T("Надеть коллекцию", "Put on the collection") : Kind == "skin" ? L.T("Надеть", "Put on") : L.T("Вставить код", "Paste code");
    }

    public static void Preview(StackPanel b) {
        var l = PagesLists.Load(Id(), b); if (l == null) return;
        bool ok = true, same = false; int n = 0;
        foreach (var d in l) {
            string err = Json.Str(d, "error"), what = Json.Str(d, "what");
            if (err.Length > 0) {
                ok = false; b.Children.Add(Ui.Note(err));
                if (Json.Bool(d, "needsDpi")) b.Children.Add(PagesLists.DpiRow());
            } else if (what.Length > 0) {
                string o = Json.Str(d, "old"), w = Json.Str(d, "new"); n++;
                b.Children.Add(Ui.Row(what, (o.Length > 0 ? o : "—") + " → " + (w.Length > 0 ? w : "—"), "", 0, null));
            } else {
                same = Json.Bool(d, "same");
                string acc = Json.Str(d, "account"), info = Json.Str(d, "info");
                b.Children.Add(Ui.Note(info + (acc.Length > 0 ? "\n" + L.T("Аккаунт: ", "Account: ") + acc : "")));
                Pics(b, Json.Dicts(Json.Get(d, "pics")));
            }
        }
        if (!ok) return;
        if (same) {
            b.Children.Add(Ui.Note(L.T("Уже так надето. Игра могла прочитать старое: она читает скины при входе в матч или стрельбище. Надень ещё раз и зайди заново.", "Already on. The game may have read the old one: it reads skins when you enter a match or the range. Put it on again and re-enter.")));
            if (Kind == "loadout" || Kind == "skin" || Kind == "coll") {
                string fid = Id() + "!force";
                var again = Ui.Sec(L.T("Надеть ещё раз", "Put on again"), 13, !Ctl.Busy, () => { Ctl.Panel.Back(); Ctl.DoAction(fid, false); }, 32, 6);
                again.MinWidth = 150; again.Margin = new Thickness(0, 4, 0, 4);
                b.Children.Add(again);
            }
            return;
        }
        if (n == 0) b.Children.Add(Ui.Note(L.T("Видимых отличий нет (мелочи вроде профилей прицела)", "No visible differences (small things like crosshair profiles)")));
        b.Children.Add(Ui.Note(Kind == "loadout" || Kind == "skin" || Kind == "coll"
            ? L.T("Перед этим VALSET делает бэкап. «Отменить» работает сразу. Скины видны после входа в матч или стрельбище. Экран «Коллекция» в игре покажет старое до перезапуска игры.", "VALSET makes a backup first. “Undo” works right away. Skins show after you enter a match or the range. The in-game Collection screen shows the old one until the game restarts.")
            : Kind == "pro"
            ? L.T("На время: после игры вернутся исходные настройки. «Отменить» работает сразу.", "For now: originals come back after the game. “Undo” works right away.")
            : L.T("Насовсем. Перед этим VALSET делает бэкап. «Отменить» работает сразу или позже в «Бэкапах».", "Permanent. VALSET makes a backup first. “Undo” works right away or later in Backups.")));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 4) };
        string id = Id();
        var yes = Ui.Pri(Kind == "pro" ? L.T("Примерить", "Try on") : Kind == "loadout" || Kind == "skin" || Kind == "coll" ? L.T("Надеть", "Put on") : L.T("Перенести", "Apply"), 13, !Ctl.Busy,
                         () => { Ctl.Panel.Back(); Ctl.DoAction(id, false); }, 32, 6);
        yes.MinWidth = 110;
        var no = Ui.Sec(L.T("Отмена", "Cancel"), 13, true, () => Ctl.Panel.Back(), 32, 6);
        no.MinWidth = 80; no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no);
        b.Children.Add(r);
    }

    // Картинки набора / коллекции перед «Надеть»: скины — полосой, карточка, спреи и флексы — квадратами (Img.cs, только видимые).
    static void Pics(StackPanel b, System.Collections.Generic.List<System.Collections.Generic.Dictionary<string, object>> pics) {
        if (pics.Count == 0) return;
        var w = new WrapPanel { Margin = new Thickness(6, 0, 0, 6) };
        foreach (var p in pics) {
            bool gun = Json.Str(p, "t") == "gun";
            var im = gun ? Img.Make(Json.Str(p, "i"), 96, 30) : Img.Make(Json.Str(p, "i"), 40, 40);
            im.Margin = new Thickness(0, 0, 8, 6); im.VerticalAlignment = VerticalAlignment.Center;
            string n = Json.Str(p, "n"); if (n.Length > 0) im.ToolTip = n;
            w.Children.Add(im);
        }
        b.Children.Add(w);
    }
}
