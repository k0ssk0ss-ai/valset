// PagesSets.cs — «Скины»: наборы косметики (ядро — sets.ps1). Клик по набору — предпросмотр «было → станет»
// (PagesShare.cs, вид loadout), надеть — кнопкой в нём. Привязка к агенту — страница setagent; автосмена — переключатель.
using System;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Threading;

static class Sets {
    static TextBox name;           // поле имени живёт между перерисовками панели, иначе набранное пропадёт
    static bool naming;            // открыто поле «Сохранить как набор»
    static string agentFor = "", agentForName = "", agentCur = "";   // страница setagent: какой набор и его агент сейчас

    public static void Page(StackPanel b) {
        var s = Ctl.Cur;
        b.Children.Add(Ui.Toggle(L.T("Менять скины при выборе агента", "Switch skins on agent select"), s.SetsAuto,
            on => { s.SetsAuto = on; Ctl.DoAction("set:setsAuto=" + (on ? "on" : "off"), false); }));
        b.Children.Add(Ui.Note(L.T("Зафиксируешь агента — надену его набор, он будет в этом матче. Набор, надетый посреди матча, виден со следующего.",
                                   "Lock in an agent and its set goes on for that match. A set put on mid-match shows from the next match.")));
        if (naming) NameBox(b);
        else b.Children.Add(Ui.Row(L.T("Сохранить текущие как набор", "Save current as a set"),
            L.T("скины с цветом и уровнем, брелоки, спреи, карточка, титул, рамка", "skins with variant and level, buddies, sprays, card, title, border"), "", 0,
            () => { naming = true; Ctl.Panel.Refresh(); }));
        b.Children.Add(Ui.Sep(6, 6));
        var l = PagesLists.Load("loadouts", b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Наборов пока нет", "No sets yet"))); return; }
        foreach (var d in l) {
            string id = Json.Str(d, "id"), nm = Json.Str(d, "name"), ag = Json.Str(d, "agent"), key = "loadoutdel:" + id;
            if (Lists.Confirm == key) { b.Children.Add(ConfirmDel(nm, key)); continue; }
            var box = new StackPanel { Margin = new Thickness(0, 0, 0, 6) };
            box.Children.Add(Ui.Row(nm, Json.Str(d, "hint"), "", 0, () => Share.Open("loadout", id)));
            var wrap = new WrapPanel { Margin = new Thickness(6, 0, 0, 0) };
            wrap.Children.Add(Small(L.T("Агент…", "Agent…"), () => { agentFor = id; agentForName = nm; agentCur = ag; Ctl.Panel.Go("setagent"); }));
            wrap.Children.Add(Small(L.T("Удалить", "Delete"), () => { Lists.Confirm = key; Ctl.Panel.Refresh(); }));
            box.Children.Add(wrap);
            b.Children.Add(box);
        }
    }

    static Border Small(string text, Action click) {
        var x = Ui.Btn(text, 12, 0xE8E8E8, 0x333333, 0x404040, !Ctl.Busy, click, 26, 5);
        x.Margin = new Thickness(4, 0, 0, 4); return x;
    }

    static UIElement ConfirmDel(string nm, string doId) {
        var box = new Border { Background = Ui.Br(0x2B2B2B), CornerRadius = new CornerRadius(6), Padding = new Thickness(10, 6, 10, 8), Margin = new Thickness(0, 0, 0, 2) };
        var sp = new StackPanel();
        sp.Children.Add(Ui.Tb(L.T("Удалить набор «", "Delete set “") + nm + L.T("»?", "”?"), 13.5, 0xFFFFFF, FontWeights.SemiBold));
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        var yes = Ui.Btn(L.T("Да", "Yes"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, true, () => { Lists.Confirm = null; Ctl.DoAction(doId, false); }, 26, 5); yes.MinWidth = 60;
        var no = Ui.Btn(L.T("Нет", "No"), 12.5, 0xE0E0E0, 0x3A3A3A, 0x484848, true, () => { Lists.Confirm = null; Ctl.Panel.Refresh(); }, 26, 5); no.MinWidth = 60;
        no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no); sp.Children.Add(r);
        box.Child = sp; return box;
    }

    // Поле имени: Enter — сохранить, Esc — закрыть.
    static void NameBox(StackPanel b) {
        if (name == null) {
            name = new TextBox { FontSize = 13.5, MaxLength = 32, Padding = new Thickness(6, 4, 6, 4), Margin = new Thickness(10, 4, 10, 4),
                                 Background = Ui.Br(0x2B2B2B), Foreground = Ui.Br(0xFFFFFF), CaretBrush = Ui.Br(0xFFFFFF), BorderBrush = Ui.Br(0x3D8BFD) };
            name.KeyDown += (s, e) => {
                if (e.Key == Key.Enter) { e.Handled = true; SaveName(); }
                else if (e.Key == Key.Escape) { e.Handled = true; naming = false; Ctl.Panel.Refresh(); }
            };
        }
        var p = name.Parent as Panel; if (p != null) p.Children.Remove(name);
        var lbl = Ui.Tb(L.T("Имя набора", "Set name"), 12, 0x9A9A9A, null); lbl.Margin = new Thickness(10, 4, 10, 0);
        b.Children.Add(lbl);
        b.Children.Add(name);
        var r = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 2, 0, 4) };
        var yes = Ui.Btn(L.T("Сохранить", "Save"), 12.5, 0xFFFFFF, 0x3D8BFD, 0x5A9DFE, !Ctl.Busy, SaveName, 28, 5); yes.MinWidth = 90;
        var no = Ui.Btn(L.T("Отмена", "Cancel"), 12.5, 0xE0E0E0, 0x3A3A3A, 0x484848, true, () => { naming = false; Ctl.Panel.Refresh(); }, 28, 5); no.MinWidth = 70;
        no.Margin = new Thickness(6, 0, 0, 0);
        r.Children.Add(yes); r.Children.Add(no); b.Children.Add(r);
        var tb = name;
        tb.Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => { tb.Focus(); Keyboard.Focus(tb); tb.CaretIndex = tb.Text.Length; }));
    }

    static void SaveName() {
        string t = (name.Text ?? "").Trim();
        if (t.Length == 0 || Ctl.Busy) return;
        naming = false; name.Text = "";
        Ctl.DoAction("loadoutsave:" + B64(t), false);   // имя — base64url: без пробелов и кавычек в командной строке
    }

    static string B64(string t) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(t)).TrimEnd('=').Replace('+', '-').Replace('/', '_'); }

    // ── Агент для набора ──
    public static void Agents(StackPanel b) {
        b.Children.Add(Ui.Note(L.T("Набор «", "Set “") + agentForName + L.T("» надевать при выборе агента:", "” goes on when you lock in:")));
        b.Children.Add(Ui.Row(L.T("Без агента", "No agent"), "", agentCur.Length == 0 ? "✓" : "", Ctl.Green, () => Bind("none")));
        var l = PagesLists.Load("agents", b); if (l == null) return;
        if (l.Count == 0) { b.Children.Add(Ui.Note(L.T("Список агентов не загрузился (нет сети?) — открой позже.", "The agent list did not load (no network?) — open again later."))); return; }
        var g = new UniformGrid { Columns = 2 };
        foreach (var d in l) {
            string aid = Json.Str(d, "id");
            g.Children.Add(Ui.Nav(Json.Str(d, "name") + (aid == agentCur ? "  ✓" : ""), () => Bind(aid)));
        }
        b.Children.Add(g);
        b.Children.Add(Ui.Note(L.T("У агента один набор: выберешь занятого — у прежнего набора привязка снимется.", "One set per agent: picking a taken agent unbinds the previous set.")));
    }

    static void Bind(string agent) {
        string id = agentFor;
        Ctl.Panel.Back();
        Ctl.DoAction("loadoutbind:" + id + ":" + agent, false);
    }
}
