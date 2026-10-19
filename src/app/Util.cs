// Util.cs — язык строк, отладочный лог, обрезка памяти.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Threading;

static class L {
    public static bool En = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "ru";
    public static string T(string ru, string en) { return En ? en : ru; }

    // Число с существительным: 1 отличие, 2 отличия, 5 отличий
    public static string Plural(int n, string one, string few, string many, string enOne, string enMany) {
        if (En) return n + " " + (n == 1 ? enOne : enMany);
        int a = n % 100, b = n % 10;
        string w = (a >= 11 && a <= 14) ? many : b == 1 ? one : (b >= 2 && b <= 4) ? few : many;
        return n + " " + w;
    }
}

static class Dbg {
    static readonly bool On = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("VALSET_DEBUG"));
    static readonly object gate = new object();
    public static void Log(string m) {
        if (!On) return;
        try { lock (gate) File.AppendAllText(Path.Combine(Path.GetTempPath(), "valset-app-debug.log"), DateTime.Now.ToString("HH:mm:ss.fff") + " " + m + "\r\n"); } catch { }
    }
}

static class Mem {
    static DispatcherTimer timer;
    public static void Trim() {
        GC.Collect();
        try { using (var p = Process.GetCurrentProcess()) Native.EmptyWorkingSet(p.Handle); } catch { }
    }
    // Через 20 с тишины отдать память системе.
    public static void TrimSoon() {
        if (timer == null) {
            timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
            timer.Tick += (s, e) => { timer.Stop(); Trim(); };
        }
        timer.Stop(); timer.Start();
    }
}
