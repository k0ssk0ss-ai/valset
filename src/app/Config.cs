// Config.cs — config.json ядра (читаем/правим по одному ключу) и автозапуск.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Microsoft.Win32;

static class Config {
    const string RunKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";

    static string FilePath() {
        return Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE") ?? "", "valset\\config.json");
    }

    static Dictionary<string, object> Read() {
        try {
            var d = Json.Ser().DeserializeObject(File.ReadAllText(FilePath(), Encoding.UTF8)) as Dictionary<string, object>;
            if (d != null) return d;
        } catch { }
        return new Dictionary<string, object>();
    }

    // Меняем только свой ключ, остальные не трогаем; запись через временный файл.
    public static void SetBool(string key, bool value) {
        try {
            string p = FilePath();
            Directory.CreateDirectory(Path.GetDirectoryName(p));
            var d = Read(); d[key] = value;
            string tmp = p + ".tmp";
            File.WriteAllText(tmp, Json.Ser().Serialize(d), new UTF8Encoding(false));
            if (File.Exists(p)) File.Replace(tmp, p, null); else File.Move(tmp, p);
        } catch (Exception e) { Dbg.Log("config: " + e.Message); }
    }

    public static bool IsAutostart() {
        try { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue("VALSET") != null; } catch { return false; }
    }

    public static void SetAutostart(bool on) {
        try {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey)) {
                if (on) {
                    string exe = System.Reflection.Assembly.GetEntryAssembly().Location;
                    k.SetValue("VALSET", "\"" + exe + "\" \"" + Core.Cmd + "\"");
                } else k.DeleteValue("VALSET", false);
            }
            SetBool("app", on);   // ядро при установке смотрит на config.app
        } catch (Exception e) { Dbg.Log("автозапуск: " + e.Message); }
    }
}
