// Update.cs — обновления в приложении: одна проверка при запуске (ядро `list update`, кэш 12 ч — update.ps1), строка
// «Вышла версия X» внизу главной и кнопка «Проверить сейчас» в настройках. Таймеров нет: попытка при каждом новом state,
// пока проверка не случится (идёт игра или кнопка поверх игры на экране — ждём следующего state).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

static class Upd {
    public static bool Newer, Confirm, Checking;
    public static string Latest = "", Url = "", Status = "";   // Status — итог «Проверить сейчас» для настроек
    static bool started;

    // Из ApplyState: один раз за запуск, только если включено и не во время игры.
    public static void TryStart() {
        if (started || !Ctl.HaveState) return;
        if (!Ctl.Cur.UpdateCheck) { started = true; return; }
        if (Ctl.IsGame() || (Ctl.Overlay != null && Ctl.Overlay.Shown)) return;
        started = true;
        Check(false);
    }

    // now — кнопка «Проверить сейчас»: спросить GitHub, даже если проверка выключена или кэш свежий.
    public static void Check(bool now) {
        if (Checking) return;
        Checking = true; if (now) Status = ""; Ctl.Raise();
        Ctl.Post(() => {
            var d = Json.Parse(Core.Run("list update" + (now ? ":now" : ""), null, 30000));
            Ctl.Ui.BeginInvoke(new Action(() => { Checking = false; Apply(d, now); Ctl.Raise(); }));
        });
    }

    static void Apply(Dictionary<string, object> d, bool now) {
        if (d == null || Json.Str(d, "error").Length > 0) { if (now) Status = L.T("Не получилось проверить", "Could not check"); return; }
        if (Json.Bool(d, "off")) return;
        Newer = Json.Bool(d, "newer"); Latest = Json.Str(d, "latest"); Url = Json.Str(d, "url");
        if (now) Status = Newer ? L.T("Вышла версия ", "Version available: ") + Latest : L.T("У тебя последняя версия", "You have the latest version");
    }

    public static void Off() { Newer = false; Confirm = false; }

    // Строка внизу главной: «Вышла версия X» · «Что нового» · «Обновить» → подтверждение в той же строке.
    public static UIElement Row() {
        if (!Newer || Latest.Length == 0 || Latest == Ctl.Cur.Ver) return null;
        var g = new Grid { Margin = new Thickness(16, 4, 16, 12) };
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        string text = Confirm ? L.T("Поставить ", "Install ") + Latest + L.T("? Приложение перезапустится", "? The app will restart")
                              : L.T("Вышла версия ", "Version ") + Latest + L.T("", " is out");
        var t = Ui.Tb(text, 12, Ui.T2, null); t.VerticalAlignment = VerticalAlignment.Center; t.Margin = new Thickness(0, 0, 8, 0);
        g.Children.Add(t);
        var btns = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        Border a, b;
        if (Confirm) {
            a = Ui.Sec(L.T("Нет", "No"), 12, true, () => { Confirm = false; Ctl.Raise(); }, 26, 6);
            b = Ui.Pri(L.T("Да", "Yes"), 12, !Ctl.Busy, () => { Confirm = false; Ctl.DoAction("update", false); }, 26, 6);
        } else {
            a = Ui.Sec(L.T("Что нового", "What's new"), 12, true, OpenNotes, 26, 6);
            b = Ui.Pri(L.T("Обновить", "Update"), 12, !Ctl.Busy, () => { Confirm = true; Ctl.Raise(); }, 26, 6);
        }
        a.Margin = new Thickness(0, 0, 6, 0);
        btns.Children.Add(a); btns.Children.Add(b);
        Grid.SetColumn(btns, 1); g.Children.Add(btns);
        return g;
    }

    static void OpenNotes() {
        if (!Url.StartsWith("https://github.com/k0ssk0ss-ai/valset/", StringComparison.OrdinalIgnoreCase)) return;
        try { Process.Start(new ProcessStartInfo(Url) { UseShellExecute = true }); } catch (Exception e) { Dbg.Log("обновления: " + e.Message); }
    }
}
