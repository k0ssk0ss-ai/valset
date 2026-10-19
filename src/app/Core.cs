// Core.cs — вызов ядра (valset.cmd) и разбор его JSON.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

static class Json {
    public static JavaScriptSerializer Ser() { var s = new JavaScriptSerializer(); s.MaxJsonLength = int.MaxValue; return s; }

    // Берём последнюю строку-объект: перед JSON в выводе может быть мусор.
    public static Dictionary<string, object> Parse(string text) {
        if (string.IsNullOrEmpty(text)) return null;
        string line = null;
        foreach (var l in text.Split('\n')) { var x = l.Trim().TrimStart('\uFEFF'); if (x.StartsWith("{")) line = x; }
        if (line == null) return null;
        try { return Ser().DeserializeObject(line) as Dictionary<string, object>; } catch { return null; }
    }

    public static object Get(Dictionary<string, object> d, string k) {
        object v; return d != null && d.TryGetValue(k, out v) ? v : null;
    }
    public static string Str(Dictionary<string, object> d, string k) { var v = Get(d, k); return v == null ? "" : v.ToString(); }
    public static bool? NBool(Dictionary<string, object> d, string k) {
        var v = Get(d, k);
        if (v == null) return null;
        if (v is bool) return (bool)v;
        string s = v.ToString().ToLowerInvariant();
        if (s == "true" || s == "1") return true;
        if (s == "false" || s == "0" || s == "") return false;
        double n; if (double.TryParse(s, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out n)) return n != 0;
        return true;
    }
    public static bool Bool(Dictionary<string, object> d, string k) { return NBool(d, k) == true; }
    public static int Int(Dictionary<string, object> d, string k) {
        var v = Get(d, k); int n;
        return v != null && int.TryParse(v.ToString(), out n) ? n : 0;
    }
    // Последняя строка-массив JSON; null — ядро не ответило или JSON не разобрался.
    public static List<Dictionary<string, object>> ParseArray(string text) {
        if (string.IsNullOrEmpty(text)) return null;
        string line = null;
        foreach (var l in text.Split((char)10)) { var x = l.Trim().TrimStart((char)0xFEFF); if (x.StartsWith("[")) line = x; }
        if (line == null) return null;
        try { return Dicts(Ser().DeserializeObject(line)); } catch { return null; }
    }

    // Элементы-объекты из массива; строки становятся {what: строка}.
    public static List<Dictionary<string, object>> Dicts(object v) {
        var r = new List<Dictionary<string, object>>(); var e = v as IEnumerable;
        if (e == null || v is string) return r;
        foreach (var o in e) {
            var d = o as Dictionary<string, object>;
            if (d != null) r.Add(d);
            else if (o != null) { d = new Dictionary<string, object>(); d["what"] = o.ToString(); r.Add(d); }
        }
        return r;
    }

    public static List<string> List(Dictionary<string, object> d, string k) {
        var r = new List<string>(); var v = Get(d, k) as IEnumerable;
        if (v != null && !(v is string)) foreach (var o in v) if (o != null) r.Add(o.ToString());
        return r;
    }
}

// Ответ `valset state`.
class State {
    public bool Client, Game, IsMain, Have, Temp, Pending, AutoApply, Notify, Badge, Own = true;
    public bool? Same;
    public int Diff;
    public string Account = "", Puuid = "", Suggested = "", Lang = "", Error = "";
    public List<Dictionary<string, object>> DiffList = new List<Dictionary<string, object>>();
    public List<string> Synced = new List<string>();

    public static State From(Dictionary<string, object> d) {
        var s = new State();
        s.Client = Json.Bool(d, "client"); s.Game = Json.Bool(d, "game"); s.IsMain = Json.Bool(d, "isMain");
        s.Have = Json.Bool(d, "have"); s.Temp = Json.Bool(d, "temp"); s.Pending = Json.Bool(d, "pending");
        s.AutoApply = Json.Bool(d, "autoApply"); s.Notify = Json.Bool(d, "notify"); s.Badge = Json.Bool(d, "badge");
        s.Same = Json.NBool(d, "same"); s.Diff = Json.Int(d, "diff");
        s.Account = Json.Str(d, "account"); s.Puuid = Json.Str(d, "puuid"); s.Suggested = Json.Str(d, "suggested");
        s.Lang = Json.Str(d, "lang"); s.Error = Json.Str(d, "error");
        s.DiffList = Json.Dicts(Json.Get(d, "diffList"));
        s.Own = Json.NBool(d, "own") ?? (s.IsMain || s.Have); s.Synced = Json.List(d, "synced");
        return s;
    }
}

static class Core {
    public static string Cmd = "";

    // Скрытый вызов ядра, stdout как UTF-8. null — не запустилось. Зови не из потока интерфейса.
    public static string Run(string args, string gameToken, int timeoutMs) {
        var si = new ProcessStartInfo("cmd.exe", "/c \"\"" + Cmd + "\" " + args + "\"");
        si.CreateNoWindow = true; si.UseShellExecute = false; si.WindowStyle = ProcessWindowStyle.Hidden;
        si.RedirectStandardOutput = true; si.RedirectStandardError = true; si.RedirectStandardInput = true;
        si.StandardOutputEncoding = Encoding.UTF8; si.StandardErrorEncoding = Encoding.UTF8;
        si.EnvironmentVariables.Remove("VALSET_GAME_TOKEN");
        if (gameToken != null) si.EnvironmentVariables["VALSET_GAME_TOKEN"] = gameToken;
        var sp = args.Split(new[] { (char)32 }, 2);
        if (sp[0] == "state" || sp[0] == "list" || sp[0] == "do" || sp[0] == "watch") {
            Dbg.Log("core(in-proc): " + args);
            string ip = InProc.Call(sp[0], sp.Length > 1 ? sp[1] : "", gameToken, timeoutMs);
            if (ip != null) { Dbg.Log("core: <- " + (ip.Length > 300 ? ip.Substring(0, 300) : ip).Trim()); return ip; }
            Dbg.Log("core: in-proc недоступен, запасной путь через cmd");
        }
        Dbg.Log("core: " + args);
        try {
            using (var p = Process.Start(si)) {
                p.ErrorDataReceived += (s, e) => { };
                p.BeginErrorReadLine();
                p.StandardInput.Close();
                var rd = p.StandardOutput.ReadToEndAsync();
                if (!p.WaitForExit(timeoutMs)) { KillTree(p.Id); Dbg.Log("core: таймаут " + args); }
                string o = rd.Wait(3000) ? rd.Result : "";
                Dbg.Log("core: <- " + (o.Length > 300 ? o.Substring(0, 300) : o).Trim());
                return o;
            }
        } catch (Exception e) { Dbg.Log("core: ошибка запуска " + e.Message); return null; }
    }

    static void KillTree(int pid) {
        try { using (var k = Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + pid) { CreateNoWindow = true, UseShellExecute = false })) k.WaitForExit(5000); } catch { }
    }

    // Видимая консоль ядра («Про», «Ещё», меню).
    public static void Console(string args) {
        try { Process.Start(new ProcessStartInfo(Cmd, args) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(Cmd) }); } catch (Exception e) { Dbg.Log("консоль: " + e.Message); }
    }

    // Клиент Riot: путь из RiotClientInstalls.json, иначе стандартный; нет — меню ядра.
    public static void OpenRiotClient() {
        string exe = null;
        try {
            var j = Json.Parse(File.ReadAllText(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Riot Games\\RiotClientInstalls.json")));
            foreach (var k in new[] { "rc_default", "rc_live" }) { var p = Json.Str(j, k); if (p.Length > 0 && File.Exists(p)) { exe = p; break; } }
        } catch { }
        if (exe == null && File.Exists("C:\\Riot Games\\Riot Client\\RiotClientServices.exe")) exe = "C:\\Riot Games\\Riot Client\\RiotClientServices.exe";
        if (exe == null) { Console(""); return; }
        try { Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true }); } catch { Console(""); }
    }
}
