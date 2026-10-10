# build-pros.ps1 — собирает pros.json из сырых данных pros-raw\part*.json (+ правки overrides.json).
# Сырые данные: prosettings.net + vlr.gg + ответы Twitch-ботов (сбор 2026-10-11, NOTES п. 3б).
# В облако идут: чувствительность, scoped, миникарта (поворот, центр, размер, масштаб); прицел — кодом игры
# (переводится при применении). Графика — как есть, для будущего.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$raw  = Join-Path $repo 'pros-raw'
$inv  = [Globalization.CultureInfo]::InvariantCulture
$ov   = Get-Content (Join-Path $raw 'overrides.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Num($v) {
    if ($null -eq $v -or "$v" -eq '') { return $null }
    $d = 0.0
    if ([double]::TryParse(("$v" -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { $d } else { $null }
}
function OnOff($v) { switch -regex ("$v") { '^(On|Yes|True)$' { $true } '^(Off|No|False)$' { $false } default { $null } } }

$pros = foreach ($f in Get-ChildItem $raw -Filter 'part*.json' | Sort-Object Name) {
    foreach ($e in @(Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ }) {
        $o = $ov.($e.nick.ToLower())
        $dpi  = if ($o.dpi) { $o.dpi } else { Num $e.mouse.dpi }
        $sens = if ($o.sens) { $o.sens } else { Num $e.mouse.sens }
        $zoom = if ($o.scopedSens) { $o.scopedSens } else { Num $e.mouse.scopedSens }
        $code = if ($o.crosshair) { $o.crosshair } else { $e.crosshair.code }
        if ($code -and $code -notmatch '^0;.*;') { $code = $null }

        $fl = @(); $bl = @()
        if ($sens) { $fl += [ordered]@{ settingEnum = 'EAresFloatSettingName::MouseSensitivity'; value = $sens } }
        if ($zoom) { $fl += [ordered]@{ settingEnum = 'EAresFloatSettingName::MouseSensitivityZoomed'; value = $zoom } }
        $m = $e.minimap
        if (Num $m.size) { $fl += [ordered]@{ settingEnum = 'EAresFloatSettingName::MinimapSize'; value = (Num $m.size) } }
        if (Num $m.zoom) { $fl += [ordered]@{ settingEnum = 'EAresFloatSettingName::MinimapZoom'; value = (Num $m.zoom) } }
        if ("$($m.rotate)" -match '^(Rotate|Fixed)$') { $bl += [ordered]@{ settingEnum = 'EAresBoolSettingName::MinimapRotates'; value = ($m.rotate -eq 'Rotate') } }
        $c = OnOff $m.keepCentered
        if ($null -ne $c) { $bl += [ordered]@{ settingEnum = 'EAresBoolSettingName::MinimapTranslates'; value = $c } }

        if (-not $fl.Count -and -not $code) { continue }   # нечего примерять
        $prefs = [ordered]@{}
        if ($fl.Count) { $prefs.floatSettings = $fl }
        if ($bl.Count) { $prefs.boolSettings = $bl }
        $upd = $null; if ($e.updated) { try { $upd = [datetime]::Parse($e.updated, $inv).ToString('yyyy-MM-dd') } catch { } }
        [ordered]@{
            nick = $e.nick; team = $e.team; active = [bool]$e.active; twitch = $e.twitch
            source = @($e.sources)[0]; updated = $upd; dpi = $dpi; crosshair = $code
            prefs = $prefs; graphics = $e.graphics
        }
    }
}
$pros = @($pros | Sort-Object { -[int]$_.active }, { $_.nick })
$json = ConvertTo-Json -InputObject ([ordered]@{ version = 1; pros = $pros }) -Depth 8
[IO.File]::WriteAllText((Join-Path $repo 'pros.json'), $json, (New-Object Text.UTF8Encoding $false))
"pros.json: $($pros.Count) про, с прицелом $(@($pros | Where-Object { $_.crosshair }).Count)"
