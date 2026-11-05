// Img.cs — картинки предметов для «Все скины»: только те, что видны в прокрутке панели, по одной в фоновом потоке.
// Диск: %USERPROFILE%\valset\cache\img (файл скачивается один раз); память: уменьшенные копии, пока панель открыта.
// Адреса — только https://media.valorant-api.com/ (из каталога ядра, skins.ps1).
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

static class Img {
    const string Host = "https://media.valorant-api.com/";
    static readonly string Dir = Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE") ?? "", "valset\\cache\\img");
    static readonly Dictionary<string, ImageSource> mem = new Dictionary<string, ImageSource>();   // ключ: адрес|ширина
    static readonly List<Image> pending = new List<Image>();       // ещё не видны
    static readonly Queue<Image> queue = new Queue<Image>();       // ждут потока загрузки
    static readonly HashSet<string> failed = new HashSet<string>();
    static readonly AutoResetEvent wake = new AutoResetEvent(false);
    static Thread worker;

    // Место под картинку; источник — сразу из памяти или позже, когда станет видна (Scan).
    public static Image Make(string url, double w, double h) {
        var im = new Image { Width = w, Height = h, Stretch = Stretch.Uniform, SnapsToDevicePixels = true };
        RenderOptions.SetBitmapScalingMode(im, BitmapScalingMode.HighQuality);
        if (string.IsNullOrEmpty(url) || !url.StartsWith(Host, StringComparison.OrdinalIgnoreCase) || failed.Contains(url)) return im;
        ImageSource src;
        if (mem.TryGetValue(Key(url, w), out src)) { im.Source = src; return im; }
        im.Tag = url; pending.Add(im);
        return im;
    }

    static string Key(string url, double w) { return url + "|" + (int)w; }

    // Панель перерисована — прежние места не нужны.
    public static void BeginPage() { pending.Clear(); lock (queue) queue.Clear(); }

    // Панель закрыта — отдать память.
    public static void Clear() { BeginPage(); mem.Clear(); }

    // Видимые (с запасом в 120 px) — в очередь загрузки.
    public static void Scan(ScrollViewer sv) {
        if (pending.Count == 0 || sv == null) return;
        double top = -120, bottom = sv.ViewportHeight + 120;
        for (int i = pending.Count - 1; i >= 0; i--) {
            var im = pending[i];
            if (!im.IsVisible) continue;
            double y;
            try { y = im.TransformToAncestor(sv).Transform(new Point(0, 0)).Y; } catch { continue; }
            if (y + im.Height < top || y > bottom) continue;
            pending.RemoveAt(i);
            lock (queue) queue.Enqueue(im);
        }
        if (worker == null) { worker = new Thread(Work) { IsBackground = true, Name = "img", Priority = ThreadPriority.BelowNormal }; worker.Start(); }
        wake.Set();
    }

    static void Work() {
        while (true) {
            Image im = null; string url = null; double w = 0, scale = 1.5;
            lock (queue) if (queue.Count > 0) im = queue.Dequeue();
            if (im == null) { wake.WaitOne(); continue; }
            im.Dispatcher.Invoke(new Action(() => { url = im.Tag as string; w = im.Width; }));
            if (url == null) continue;
            ImageSource src = null;
            try { src = Load(url, (int)Math.Round(w * scale)); }
            catch (Exception e) { Dbg.Log("картинка " + url + ": " + e.Message); }
            var img = im; string u = url; double ww = w;
            im.Dispatcher.BeginInvoke(new Action(() => {
                if (src == null) { failed.Add(u); return; }
                mem[Key(u, ww)] = src;
                img.Source = src;
            }));
        }
    }

    // Файл с диска (нет — скачать), уменьшить до нужной ширины, заморозить (можно отдать в поток интерфейса).
    static ImageSource Load(string url, int px) {
        string name = url.Substring(Host.Length).Replace('/', '_');
        foreach (char c in name) if (!(char.IsLetterOrDigit(c) || c == '_' || c == '-' || c == '.')) throw new ArgumentException("имя файла");
        string path = Path.Combine(Dir, name);
        if (!File.Exists(path)) {
            Directory.CreateDirectory(Dir);
            string tmp = path + ".tmp";
            using (var wc = new WebClient()) wc.DownloadFile(url, tmp);
            if (File.Exists(path)) File.Delete(tmp); else File.Move(tmp, path);
        }
        var b = new BitmapImage();
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            b.BeginInit();
            b.CacheOption = BitmapCacheOption.OnLoad;   // файл можно закрыть сразу
            b.DecodePixelWidth = Math.Max(16, px);
            b.StreamSource = fs;
            b.EndInit();
        }
        b.Freeze();
        return b;
    }
}
