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
