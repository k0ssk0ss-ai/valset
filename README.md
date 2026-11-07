# VALSET

**Your VALORANT settings on all your accounts.**
Binds, sensitivity, crosshair, interface, on-screen stats and graphics: save them once on your main account,
then apply them to any account you play on — and if it isn't yours, its own settings come back afterwards.

[Русская версия](README.ru.md)

> Windows 10 / 11. Nothing to install besides VALSET itself — everything it needs ships with Windows.
> Interface in English and Russian (picked automatically, switch in Help).

## Install

**One command**: press **Win+R**, paste this line, press Enter:

```
powershell -c "[Net.ServicePointManager]::SecurityProtocol=3072;irm https://raw.githubusercontent.com/k0ssk0ss-ai/valset/main/install.ps1|iex"
```

It downloads the [latest release](../../releases/latest), checks it against the published SHA-256, installs it and
opens the menu. Afterwards VALSET lives as an icon near the clock (tray); the console menu is the “VALSET” Start-menu
shortcut or the `valset` command. What the command does is in [install.ps1](install.ps1) — about 40 lines, worth a read.

**Or manually:** download `VALSET-<version>.zip` from [Releases](../../releases/latest), unzip, run `valset.cmd` and
press **Y** when asked to install. Windows may say “Windows protected your PC” (downloaded, unsigned file) —
“More info” → “Run anyway”. `valset.cmd` is a plain-text PowerShell script: open it in Notepad if in doubt.

**Updates.** On start VALSET asks GitHub once whether a new version is out (at most once per 12 hours; nothing about
you is sent). If there is one, the panel shows “Version X is out” and an “Update” button: VALSET downloads the new
`valset.cmd`, checks its SHA-256 against the release and installs it over the old one. Settings, backups and sets stay.
To turn it off: Settings → “Check for updates” (“Check now” still works). Manual rollback: run `valset.cmd.prev` from
`%USERPROFILE%\valset` and agree to install.

## How to use

1. Open the Riot Client and log into your **main** account.
2. **Tray icon / menu → “Save”** — VALSET takes your settings from it. Once is enough.
3. Log into another account → **“Apply mine”** (before launching the game).
   VALSET shows exactly what will change and asks first. After the game the account gets its own settings back.
4. From then on, changes you make in game on accounts that have your settings are picked up automatically
   (pro try-ons are not). Each update is a history point: **More → History** to roll back.

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
- **Share code** (tray panel → Share code): “Share” copies a short `VALSET3:…` line (about 200 characters: binds,
  sensitivity, crosshair, HUD, audio; no graphics, no account data). With “Add worn skins” on, the code also carries
  what you wear (weapons, sprays, flexes, card, title); your friend gets the ones they own. The friend presses
  “Paste code”, sees what changes and applies it (backup + Undo). Your friend needs VALSET.
- **Tray app** (on by default, starts with Windows, can be turned off in its settings): shows the account status,
  notifications with buttons, auto-apply on login. It polls nothing — it waits for Riot Client events.
- **All skins** (tray panel → Skins → All skins, or the “VALSET · skins” button over the game menu in Windowed
  Fullscreen, or Ctrl+Alt+S in the game menu): everything your account owns, with pictures; pick one — see what changes —
  put it on (backup + undo). The Collections tab groups skins by collection (bundle): preview all its weapons, put on
  every owned skin of a collection at once, or save it as a set.
- **Report a bug** (bottom of the tray panel): copies diagnostics (versions, last log lines; Riot IDs, PUUIDs, your
  Windows user name and tokens masked) to the clipboard and opens a new GitHub issue form — paste them there.

## Safety — honestly

- VALSET **does not touch the game**: not its files, memory or process. It doesn't need or interfere with Vanguard.
- It only works with the **Riot Client on your PC** and the **Riot settings cloud**, the same place the game
  itself saves your settings to. No password is needed or asked
  for: you log in yourself in the Riot Client.
- It only writes what you could change in the game's settings yourself. A backup is made before every write.
- It sends your data nowhere except Riot. The code is open — you can read all of it.
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

**My antivirus complains about valset-app.exe.** It is a small program VALSET compiles on your PC from its open
source (src\app). Some antivirus products are wary of unsigned executables. Don't need it — turn it off in its settings.

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
src\share.ps1      “Share code”: my settings as one line (VALSET3:…; VALSET2/1 still read), paste preview and write
src\codes.ps1, codec.ps1, codeparts.ps1   VALSET3 format: dictionaries (append only), bytes and numbers, sections + CRC
src\shareskins.ps1 worn skins in the share code (UUID prefixes resolved via the catalog; only owned ones go on)
src\sets.ps1       “Skins”: cosmetic sets (save, preview, put on, bind to an agent, auto on agent lock-in)
src\skins.ps1      “All skins”: owned items by category (valorant-api catalog by game version, entitlements), put one on
src\collections.ps1  “All skins” → Collections: skins by collection (valorant-api themes), put on a collection, set pictures
src\report.ps1     “Report a bug”: diagnostics text with private data masked (`valset do report`)
src\loadout.ps1    Riot loadout: region/shard, GET/PUT playerloadout, agent select, item names (valorant-api.com, cached)
src\cloud.ps1      requests to Riot with retries: growing pause, token lifetime, fresh token from the client
src\accounts.ps1   accounts by Riot ID, main account, status
src\agent.ps1      config, toasts, login check (`valset watch`)
src\app.ps1, src\app\*.cs   tray app (C#, built on your PC); Ui.cs + UiIcons.cs — design tokens, shared controls,
                   line icons; PagesHome.cs — main flyout; PagesSkins.cs + PagesStage.cs + Img.cs — “All skins” window (rail,
                   stage, grid) and lazy images; PagesColl.cs — collections and one collection's preview; Overlay.cs — “VALSET · skins” button over the game menu (own window, no injection)
src\do.ps1         `valset state` / `valset do` — JSON interface for the app
src\install.ps1    install, uninstall
install.ps1        one-command installer (no BOM: it runs via irm | iex)
build.ps1          bundles everything into dist\valset.cmd + the release zip
tests\run-tests.ps1  checks on fixture data (never writes to the cloud)
```

- Every UI string is a pair `(L 'русский' 'English')`; the language comes from `config.json` or Windows languages.
- All `.ps1` files except `install.ps1` are **UTF-8 with BOM** (PowerShell 5.1 needs it for Cyrillic). Tests check it.
- UI characters must exist in Consolas and Lucida Console (Windows 10 console). Tests check it.
- Build: `powershell -ExecutionPolicy Bypass -File build.ps1`. Tests: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`.
- Decisions, measurements and unverified spots — [NOTES.md](NOTES.md) (Russian); changes — [CHANGELOG.md](CHANGELOG.md).
