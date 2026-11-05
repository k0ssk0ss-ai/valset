// SelfTest.cs — VALSET_SELFTEST=1 (+ VALSET_DEBUG=1): обходит все страницы панели и пишет исключения в лог.
using System;
using System.Windows.Threading;

static class SelfTest {
    static readonly string[] Pagelist = { "apply", "save", "diff", "pros", "share", "sets", "skins", "accounts", "backups", "settings", "help" };
    static int step;
    static DispatcherTimer t;

    public static void Start() {
        t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        t.Tick += (s, e) => Tick();
        Dbg.Log("selftest: старт");
        Ctl.Panel.ShowPanel(null);
        t.Start();
    }

    static void Tick() {
        try {
            if (step < Pagelist.Length) {
                Dbg.Log("selftest: страница " + Pagelist[step]);
                if (Ctl.Panel.Page != PanelWin.Home) Ctl.Panel.Back();
                Ctl.Panel.Go(Pagelist[step]); Ctl.Panel.Rebuild();
                if (Pagelist[step] == "backups" && step >= 0) { Lists.HistoryTab = false; }
            } else if (step == Pagelist.Length) {
                Lists.HistoryTab = true; Ctl.Panel.Rebuild(); Dbg.Log("selftest: бэкапы, вкладка настроек");
            } else if (step == Pagelist.Length + 1) {
                Lists.Confirm = "history:h2"; Ctl.Panel.Rebuild(); Dbg.Log("selftest: подтверждение");
            } else if (step == Pagelist.Length + 2) {
                Ctl.Panel.Back(); Ctl.Panel.Rebuild(); Ctl.DoAction("pro:s1mple", false); Dbg.Log("selftest: do");
            } else if (step == Pagelist.Length + 3) {
                Ctl.Panel.HidePanel();
                Ctl.Panel.ShowPanel(new System.Drawing.Rectangle(600, 700, 220, 28));
                Dbg.Log("selftest: у значка " + Ctl.Panel.Left + "," + Ctl.Panel.Top);
            } else {
                t.Stop(); Dbg.Log("selftest: ГОТОВО");
            }
        } catch (Exception e) { Dbg.Log("selftest: ИСКЛЮЧЕНИЕ " + e); }
        step++;
    }
}

// VALSET_SELFTEST=coll:<id> (+ VALSET_DEBUG=1): замер памяти на странице коллекции — только чтение (list), без записи.
// Шаги по 3 с: открыть коллекцию, пролистать до конца (все картинки), замер, скрыть панель, замер.
static class SelfColl {
    static string id; static int step; static DispatcherTimer t;

    public static void Start(string coll) {
        id = coll;
        t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        t.Tick += (s, e) => Tick();
        Log("старт");
        t.Start();
    }

    static void Log(string what) {
        GC.Collect(); GC.WaitForPendingFinalizers();
        using (var p = System.Diagnostics.Process.GetCurrentProcess())
            Dbg.Log("selfcoll: " + what + " — WS " + (p.WorkingSet64 >> 20) + " МБ, private " + (p.PrivateMemorySize64 >> 20) + " МБ, managed " + (GC.GetTotalMemory(false) >> 20) + " МБ");
    }

    static void Tick() {
        try {
            step++;
            if (step == 1) { Ctl.Panel.ShowPanel(null); Colls.Open(id, "selftest"); }
            else if (step >= 2 && step <= 7) { var sv = Ctl.Panel.Scroller; if (sv != null) sv.ScrollToVerticalOffset(sv.VerticalOffset + 300); }
            else if (step == 8) Log("коллекция открыта, всё пролистано");
            else if (step == 9) Ctl.Panel.HidePanel();
            else if (step == 10) { Mem.Trim(); Log("панель скрыта"); }
            else if (step == 11) { t.Stop(); Dbg.Log("selfcoll: ГОТОВО"); }
        } catch (Exception e) { Dbg.Log("selfcoll: ИСКЛЮЧЕНИЕ " + e); }
    }
}