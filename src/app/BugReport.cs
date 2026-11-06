// BugReport.cs — «Сообщить об ошибке»: диагностика (её собирает ядро, `do report`, личное уже замаскировано) — в буфер обмена,
// форма нового issue на GitHub — в браузере. В адресе только заголовок и пустой шаблон: никаких данных пользователя.
using System;
using System.Diagnostics;
using System.Windows;

static class BugReport {
    const string Issues = "https://github.com/k0ssk0ss-ai/valset/issues/new";

    public static string Url() {
        string title = L.T("Ошибка: ", "Bug: ");
        string body = L.T("Что случилось: ...\n\nЧто ожидал: ...\n\nДиагностика скопирована в буфер — вставь ниже (Ctrl+V):\n\n",
                          "What happened: ...\n\nWhat you expected: ...\n\nDiagnostics are in the clipboard — paste them below (Ctrl+V):\n\n");
        return Issues + "?title=" + Uri.EscapeDataString(title) + "&body=" + Uri.EscapeDataString(body);
    }

    // Вызывать из потока интерфейса (буфер обмена). Возвращает текст ошибки или null.
    public static string Open(string text) {
        try { Clipboard.SetText(text); }
        catch (Exception e) { Dbg.Log("буфер: " + e.Message); return L.T("Не удалось положить диагностику в буфер обмена — попробуй ещё раз", "Could not copy the diagnostics to the clipboard — try again"); }
        try { Process.Start(new ProcessStartInfo(Url()) { UseShellExecute = true }); }
        catch (Exception e) { Dbg.Log("браузер: " + e.Message); return L.T("Диагностика в буфере, но браузер не открылся — создай issue на github.com/k0ssk0ss-ai/valset", "Diagnostics are in the clipboard, but the browser did not open — create an issue at github.com/k0ssk0ss-ai/valset"); }
        return null;
    }
}
