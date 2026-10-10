# VALSET

**Your VALORANT settings on all your accounts — in two seconds.**
Binds, sensitivity, crosshair, interface, on-screen stats and graphics: save them once on your main account,
then apply them to any account you play on — and if it isn't yours, its own settings come back afterwards.

[Русская версия](README.ru.md)

> Windows 10 / 11. Nothing to install besides VALSET itself — everything it needs ships with Windows.
> Interface in English and Russian (picked automatically, switch in Help).

## Install

**One command** — press **Win+R**, paste this line, press Enter:

```
powershell -c "[Net.ServicePointManager]::SecurityProtocol=3072;irm https://raw.githubusercontent.com/k0ssk0ss-ai/valset/main/install.ps1|iex"
```

It downloads the [latest release](../../releases/latest), checks it against the published SHA-256, installs it and
opens the menu. Afterwards the menu opens with **Ctrl+Alt+V** (or the “VALSET” Start-menu shortcut, or the `valset`
command). What the command does is in [install.ps1](install.ps1) — about 40 lines, worth a read.

**Or manually:** download `VALSET-<version>.zip` from [Releases](../../releases/latest), unzip, run `valset.cmd` and
press **Y** when asked to install. Windows may say “Windows protected your PC” (downloaded, unsigned file) —
“More info” → “Run anyway”. `valset.cmd` is a plain-text PowerShell script: open it in Notepad if in doubt.

## How to use

1. Open the Riot Client and log into your **main** account.
2. **Ctrl+Alt+V → “Save as mine”** — VALSET takes your settings from it.
3. Log into another account → **Ctrl+Alt+V → “Apply mine”** (before launching the game).
   VALSET shows exactly what will change and asks first. After the game the account gets its own settings back.

The main screen says which account you are on and whether it has your settings, and shows only what makes sense
right now (apply, save, restore originals) — usually 1–3 items. Everything else is under **More**. Press **?** for help.

### What else it does

- **Partial**: apply or save binds only, or graphics only.
- **For now — by default**: applying to any account except your main one is temporary — the account's original
  settings are kept and come back ~3 s after you close the game (with the helper; otherwise “Restore originals”
  before you log out). Mark your own accounts “mine” once, or pick “permanently”, to skip the restore.
- **What differs** — the full list “on account → yours”.
- **Crosshairs**: for now — only yours on the account, no mix-ups (its own come back with the originals);
  permanently — the account's crosshairs are kept, yours is added and made active (the game allows 15).
- **Graphics** are per PC: after “Save” they go to every account on this PC (asks once if the PC is shared).
- **Accounts** by Riot ID: where settings match, where they don't, which one is main.
- **Backups** (More → Backups): an account as it was before an apply; your own settings at an earlier version.
- **Background helper — optional** (off by default): notifications “this account has different settings” and
  auto-apply on login. It polls nothing — it waits for Riot Client events. ~5 MB of memory.
- **Ctrl+Alt+V does nothing while the game is in focus** — so you never minimize it by accident.

## Safety — honestly

- VALSET **does not touch the game**: not its files, memory or process. It doesn't need or interfere with Vanguard.
- It only talks to the **Riot Client on your PC** (the same local interface trackers and overlays use) and to the
  **Riot settings cloud** — the same place the game itself saves your settings to. No password is needed or asked
  for: you log in yourself in the Riot Client.
- It only writes what you could change in the game's settings yourself. A backup is made before every write.
- Nothing is sent anywhere else. The code is open — you can read all of it.
- Riot's Terms of Service forbid sharing accounts — whose account you log into is your own responsibility.
- This is an **unofficial** tool, not reviewed or endorsed by Riot Games. The Riot Client interfaces it uses are
  unofficial and may change after an update — VALSET may stop working until it's fixed. Use at your own risk
  (see [LICENSE](LICENSE)).

## FAQ

**Do I need to close the game?** Apply before launching it: the game reads settings at startup. If it's already
running, the settings take effect after a restart; graphics are written automatically after you exit.

**Where are my settings stored?** In `%USERPROFILE%\valset`. Uninstalling doesn't touch them.

**How do I uninstall?** Run `valset uninstall` — removes the shortcut, the command and the helper from startup.
Delete `%USERPROFILE%\valset` manually if you no longer need your saved settings.

**My antivirus complains about valset-agent / valset-open.exe.** These are tiny programs VALSET compiles on your PC
from its open source (the optional background helper and the Ctrl+Alt+V in-game guard). Some antivirus products are
wary of unsigned executables. Don't need the helper — don't turn it on.

---

## For developers

```
src\valset.ps1     entry point: Riot API, save/apply, commands, language
src\ui.ps1         screens, arrow-key lists (inline options), progress bars
src\menu.ps1       main screen: plain-language status, only what's needed now, first run, help, single window
src\more.ps1       “More” screen: manual apply/save, accounts, helper, backups
src\keys.ps1       binds: action catalogue, key names
src\schema.ps1     my settings file + human-readable labels for the preview
src\graphics.ps1   graphics: per-account local files on this PC, deferred writes
src\diff.ps1       preview: what will change
src\crosshair.ps1  crosshair profiles: “for now” — only yours, “permanently” — merged
src\backups.ps1    account rollback and my settings history
src\pros.ps1       “Pro settings”: try a pro's settings for now (list — pros.json in this repo)
src\accounts.ps1   accounts by Riot ID, main account, status
src\agent.ps1      background helper: watcher (C#, Riot Client events) + check
src\install.ps1    install, uninstall, Ctrl+Alt+V in-game guard
install.ps1        one-command installer (no BOM: it runs via irm | iex)
build.ps1          bundles everything into dist\valset.cmd + the release zip
tests\run-tests.ps1  checks on fixture data (never writes to the cloud)
```

- Every UI string is a pair `(L 'русский' 'English')`; the language comes from `config.json` or Windows languages.
- All `.ps1` files except `install.ps1` are **UTF-8 with BOM** (PowerShell 5.1 needs it for Cyrillic). Tests check it.
- UI characters must exist in Consolas and Lucida Console (Windows 10 console). Tests check it.
- Build: `powershell -ExecutionPolicy Bypass -File build.ps1`. Tests: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`.
- Decisions, measurements and unverified spots — [NOTES.md](NOTES.md) (Russian); changes — [CHANGELOG.md](CHANGELOG.md).
