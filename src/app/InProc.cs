// InProc.cs — ядро в самом приложении: один runspace PowerShell, valset.cmd загружен в режиме lib, вызовы — Invoke-Core.
// Не вышло (загрузка или исключение) — Core.Run возвращается к запуску cmd.exe для этого вызова.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Threading;

static class InProc {
    static readonly object gate = new object();
    static Runspace rs;
    static DateTime stamp, failedStamp;

    // Загрузка ядра в фоне при старте приложения (0,4 с), чтобы первый запрос панели не ждал.
    public static void Preload() {
        new Thread(() => { lock (gate) { try { Ensure(); } catch (Exception e) { Dbg.Log("inproc: preload " + e.Message); } } }) { IsBackground = true, Name = "core-load" }.Start();
    }

    // Под gate. false — ядро в процессе недоступно.
    static bool Ensure() {
        DateTime st;
        try { st = File.GetLastWriteTimeUtc(Core.Cmd); } catch { return false; }
        if (rs != null && (st != stamp || rs.RunspaceStateInfo.State != RunspaceState.Opened)) { Dbg.Log("inproc: перезагрузка runspace"); Close(); }
        if (rs != null) return true;
        if (st == failedStamp) return false;   // этот valset.cmd уже не загрузился — пока его не переустановят, не пробуем
        try { Load(); stamp = st; Dbg.Log("inproc: ядро загружено"); return true; }
        catch (Exception e) { Dbg.Log("inproc: загрузка не удалась: " + e.Message); Close(); failedStamp = st; return false; }
    }

    static void Load() {
        string text = File.ReadAllText(Core.Cmd, Encoding.UTF8);
        var r = RunspaceFactory.CreateRunspace();
        r.ThreadOptions = PSThreadOptions.ReuseThread;
        r.Open();
        rs = r;
        r.SessionStateProxy.SetVariable("vsText", text);
        r.SessionStateProxy.SetVariable("vsFile", Core.Cmd);
        using (var ps = PowerShell.Create()) {
            ps.Runspace = r;
            ps.AddScript("$env:VALSET_FILE = $vsFile; . ([ScriptBlock]::Create($vsText)) lib; Remove-Variable vsText; if (-not (Get-Command Invoke-Core -ErrorAction SilentlyContinue)) { throw 'Invoke-Core not found' }", false);
            ps.Invoke();
        }
    }

    static void Close() {
        var r = rs; rs = null;
        if (r != null) { try { r.CloseAsync(); } catch { } }
    }

    // state | list <вид> | do <действие> | watch [-AfterGame] → строка JSON; null — не вышло, нужен запасной путь через cmd.
    public static string Call(string cmd, string arg, string token, int timeoutMs) {
        lock (gate) {
            try {
                if (!Ensure()) return null;
                using (var ps = PowerShell.Create()) {
                    ps.Runspace = rs;
                    ps.AddCommand("Invoke-Core").AddArgument(cmd).AddArgument(arg ?? "").AddArgument(token ?? "");
                    var ar = ps.BeginInvoke();
                    if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) {
                        Dbg.Log("inproc: таймаут " + cmd + " " + arg);
                        try { ps.Stop(); } catch { }
                        Close();
                        return "{\"ok\":false,\"message\":\"timeout\",\"error\":\"timeout\"}";
                    }
                    string last = null;
                    foreach (var o in ps.EndInvoke(ar)) if (o != null) last = o.ToString();
                    return last;
                }
            } catch (Exception e) { Dbg.Log("inproc: " + e.Message); return null; }
        }
    }
}
