// Tray.cs — значок в трее (рисуется кодом, цвет = статус) и контекстное меню.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Windows.Forms;

class Tray : IDisposable {
    readonly NotifyIcon ni = new NotifyIcon();
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    readonly Dictionary<uint, Icon> icons = new Dictionary<uint, Icon>();
    uint curColor;

    public ContextMenuStrip Menu { get { return menu; } }

    public Tray() {
        menu.Opening += (s, e) => Build();
        ni.ContextMenuStrip = menu;
        ni.MouseUp += (s, e) => { if (e.Button == MouseButtons.Left) Ctl.Panel.Toggle(); };
        ni.Text = "VALSET";
        ni.Icon = IconFor(Ctl.Gray); curColor = Ctl.Gray;
        ni.Visible = true;
    }

    public void Update() {
        var st = Ctl.GetStatus();
        if (st.Color != curColor) { curColor = st.Color; ni.Icon = IconFor(st.Color); }
        string acc = Ctl.Cur.Account.Length > 0 ? Ctl.Cur.Account : "—";
        string t = "VALSET — " + acc + ": " + st.Text;
        ni.Text = t.Length > 63 ? t.Substring(0, 62) + "…" : t;   // у NotifyIcon предел 63 знака
    }

    void Build() {
        menu.Items.Clear();
        menu.Items.Add(new ToolStripMenuItem(L.T("Открыть консоль", "Open console"), null, (s, e) => Core.Console("")));
        var auto = new ToolStripMenuItem(L.T("Автозапуск", "Start with Windows"), null, (s, e) => Config.SetAutostart(!Config.IsAutostart()));
        auto.Checked = Config.IsAutostart();
        menu.Items.Add(auto);
        var badge = new ToolStripMenuItem(L.T("Значок у клиента", "Badge on the client"), null, (s, e) => Ctl.SetBadge(!Ctl.Cur.Badge));
        badge.Checked = Ctl.Cur.Badge;
        menu.Items.Add(badge);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(L.T("Выход", "Exit"), null, (s, e) => Ctl.Exit()));
    }

    // Меню из кнопки ⚙ на панели.
    public void ShowMenuAtCursor() { menu.Show(Control.MousePosition); }

    Icon IconFor(uint rgb) {
        Icon ic;
        if (icons.TryGetValue(rgb, out ic)) return ic;
        ic = Draw(Color.FromArgb((int)(0xFF000000u | rgb)));
        icons[rgb] = ic;
        return ic;
    }

    // Скруглённый квадрат цвета статуса с белой «V».
    static Icon Draw(Color fill) {
        int sz = Math.Max(16, SystemInformation.SmallIconSize.Width);
        using (var bmp = new Bitmap(sz, sz, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);
            float r = sz * 0.28f, d = r * 2, x0 = 0.5f, x1 = sz - 1.5f;
            using (var path = new GraphicsPath()) {
                path.AddArc(x0, x0, d, d, 180, 90); path.AddArc(x1 - d, x0, d, d, 270, 90);
                path.AddArc(x1 - d, x1 - d, d, d, 0, 90); path.AddArc(x0, x1 - d, d, d, 90, 90);
                path.CloseFigure();
                using (var b = new SolidBrush(fill)) g.FillPath(b, path);
            }
            using (var f = new Font("Segoe UI", sz * 0.62f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString("V", f, Brushes.White, new RectangleF(0, sz * 0.03f, sz, sz), sf);
            IntPtr h = bmp.GetHicon();
            var ic = (Icon)Icon.FromHandle(h).Clone();
            Native.DestroyIcon(h);
            return ic;
        }
    }

    public void Dispose() {
        ni.Visible = false; ni.Dispose(); menu.Dispose();
        foreach (var i in icons.Values) i.Dispose();
    }
}
