// PagesShare.cs — «Код для друга» и предпросмотр перед записью: вставка кода (кнопка, ссылка valset:code/<код>)
// и примерка про (список «Про», ссылка valset:pro/<ник>). Пишет только кнопка в предпросмотре — ссылка сама ничего не применяет.
using System;
using System.Text;
using System.Windows;
using System.Windows.Controls;

static class Share {
    public static string Kind = "", Arg = "";   // предпросмотр: code | pro и сам код / ник

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
    public static string Clean(string t) {
        t = t ?? "";
        int i = t.IndexOf("VALSET", StringComparison.OrdinalIgnoreCase);
        if (i < 0 || t.Length < i + 8) return null;
        var sb = new StringBuilder(t.Substring(i, 8));
        for (int k = i + 8; k < t.Length; k++) {
            char c = t[k];
            if (char.IsWhiteSpace(c)) continue;
            bool cjk = c >= (char)0x4E00 && c <= (char)0x8DFF, b64 = c < 128 && (char.IsLetterOrDigit(c) || c == '+' || c == '/');
            if (cjk || b64 || c == '=') sb.Append(c); else break;
        }
        return sb.Length > 8 ? sb.ToString() : null;
    }

    // ── Код для друга ──
    public static void Page(StackPanel b) {
        b.Children.Add(Ui.Row(L.T("Поделиться", "Share"), L.T("код твоих настроек — в буфер обмена", "your settings code — to the clipboard"), "", 0, () => Ctl.DoAction("share", false)));
        b.Children.Add(Ui.Row(L.T("Вставить код", "Paste code"), L.T("из буфера обмена; сначала покажу, что изменится", "from the clipboard; shows what changes first"), "", 0, Paste));
        b.Children.Add(Ui.Note(L.T("В коде — бинды, чувствительность, прицел, HUD и звук. Без графики и без данных аккаунта. У друга должен быть VALSET.",
                                   "The code holds binds, sensitivity, crosshair, HUD and audio. No graphics, no account data. Your friend needs VALSET.")));
    }

    static void Paste() {
        string t = null;
        try { t = Clean(Clipboard.GetText()); } catch (Exception e) { Dbg.Log("буфер: " + e.Message); }
        if (t == null) {
            Ctl.ResultOk = false; Ctl.ResultUndo = false;
            Ctl.ResultMsg = L.T("В буфере обмена нет кода VALSET — скопируй его целиком.", "No VALSET code in the clipboard — copy all of it.");
            Ctl.Raise(); return;
        }
        Open("code", t);
    }

    // ── Предпросмотр ──
    public static string Title() {
        return Kind == "pro" ? L.T("Примерить ", "Try on ") + Arg : L.T("Вставить код", "Paste code");
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
            }
        }
        if (!ok) return;
        if (same) { b.Children.Add(Ui.Note(L.T("Уже так — менять нечего.", "Already like this — nothing to change."))); return; }
        if (n == 0) b.Children.Add(Ui.Note(L.T("Отличия только служебные (профили прицела, агентские бинды и т. п.)", "Only internal differences (crosshair profiles, agent binds, etc.)")));
        b.Children.Add(Ui.Note(Kind == "pro"
            ? L.T("На время: после игры вернутся исходные; «Отменить» — сразу.", "For now: originals come back after the game; “Undo” works right away.")
            : L.T("Насовсем, перед записью — бэкап; «Отменить» — сразу или позже в «Бэкапах».", "Permanent, with a backup first; “Undo” right away or later in Backups.")));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 4) };
        string id = Id();
        var yes = Ui.Btn(Kind == "pro" ? L.T("Примерить", "Try on") : L.T("Записать", "Apply"), 13, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, !Ctl.Busy,
                         () => { Ctl.Panel.Back(); Ctl.DoAction(id, false); }, 32, 6);
        yes.MinWidth = 110;
        var no = Ui.Btn(L.T("Отмена", "Cancel"), 13, 0xE0E0E0, 0x3A3A3A, 0x484848, true, () => Ctl.Panel.Back(), 32, 6);
        no.MinWidth = 80; no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no);
        b.Children.Add(r);
    }
}
