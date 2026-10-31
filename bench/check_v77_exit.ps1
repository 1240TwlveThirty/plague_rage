# Задача 27: игра закрывается без зависания. С окном (мышь и клавиатуру не трогать). Своя пустая папка данных пользователя
# (APPDATA во временной папке; первый проход — пустая, следующие — уже с settings.cfg и сохранением, как у игрока).
# 1) Дочерний bench/diag_v77_exit.gd: меню, пауза в бою, бой, хаб, пауза в хабе — кнопка «Выход» или запрос закрытия окна
#    (NOTIFICATION_WM_CLOSE_REQUEST + close_requested, как Alt+F4); процесс должен выйти сам за $LimitSec с, сохранение записано.
# 2) Настоящая игра без -s (главное меню; --scene=battle|hub|pick): WM_CLOSE окну (Process.CloseMainWindow — то же сообщение,
#    что Alt+F4 через SC_CLOSE и крестик) — процесс выходит за $LimitSec с.
# Печатает EXIT: провалов N. Запуск: $env:GODOT_EXE = "<godot.exe>"; powershell -File bench\check_v77_exit.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT_EXE
$LimitSec = 20       # выход после действия
$StartSec = 60       # окно и сцена готовы
$fails = 0
$app = Join-Path $env:TEMP ("pr_exit77_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $app | Out-Null
$userDir = Join-Path $app "Godot\app_userdata\Plague_Rage"
$oldApp = $env:APPDATA
$env:APPDATA = $app   # дочерние процессы пишут user:// сюда; настоящие данные игрока не трогаются

function Check([string]$name, [bool]$ok, [string]$detail = "") {
	if ($ok) { Write-Host "  $name`: да" } else { Write-Host "  $name`: НЕТ $detail"; $script:fails += 1 }
}

function Launch([string[]]$argv) {
	$out = Join-Path $app "out.txt"
	$err = Join-Path $app "err.txt"
	Remove-Item $out, $err -ErrorAction SilentlyContinue
	$p = Start-Process -FilePath $godot -ArgumentList $argv -WorkingDirectory $root -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
	$null = $p.Handle
	return @{ p = $p; out = $out; err = $err }
}

function Finish($h, [string]$name, [double]$limit) {
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$done = $h.p.WaitForExit([int]($limit * 1000))
	if (-not $done) { try { $h.p.Kill() } catch {}; $h.p.WaitForExit(10000) | Out-Null }
	$text = "" + (Get-Content $h.out -Raw -Encoding UTF8) + (Get-Content $h.err -Raw -Encoding UTF8)
	$bad = [regex]::Matches($text, "SCRIPT ERROR|Parse Error|Failed to load").Count
	Check ("{0}: процесс вышел сам за {1:N1} с (код {2})" -f $name, $sw.Elapsed.TotalSeconds, $(if ($done) { $h.p.ExitCode } else { "-" })) ($done -and $h.p.ExitCode -eq 0 -and $bad -eq 0) "(завис, код не 0 или ошибка скрипта)"
}

# 1) из состояний, способом
$cases = @(@("menu", "button"), @("menu", "close"), @("pause", "button"), @("pause", "close"), @("battle", "close"),
	@("hub", "close"), @("hubpause", "button"), @("hubpause", "close"))
foreach ($c in $cases) {
	$save = Join-Path $userDir "bench_v77x\save.json"
	$h = Launch @("--path", "`"$root`"", "-s", "res://bench/diag_v77_exit.gd", "--", $c[0], $c[1])
	Finish $h ("{0}, {1}" -f $c[0], $c[1]) ($StartSec + $LimitSec)
	$text = "" + (Get-Content $h.out -Raw -Encoding UTF8)
	Check ("{0}, {1}: дошёл до действия, сохранение записано" -f $c[0], $c[1]) (($text -match "EXITTEST\|quit") -and (Test-Path $save)) $text.Trim()
}

# 3) предохранитель: подключён во всех view_* и shots_* (сам или в базовом скрипте) и срабатывает на зависшей сцене
foreach ($f in Get-ChildItem (Join-Path $root "bench") -File | Where-Object { $_.Name -match '^(view|shots)_.*\.gd$' }) {
	$src = Get-Content $f.FullName -Raw -Encoding UTF8
	$base = [regex]::Match($src, '(?m)^extends "res://bench/([^"]+)"')
	if ($base.Success) { $src += Get-Content (Join-Path $root ("bench/" + $base.Groups[1].Value)) -Raw -Encoding UTF8 }
	Check ("предохранитель в {0}" -f $f.Name) ($src -match 'bench/watchdog\.gd"\)\.arm\(self\)')
}
$cfg = Get-Content (Join-Path $root "data/bench.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$hangSec = [double]$cfg.watchdog_sec.diag_v77_hang
$h = Launch @("--headless", "--path", "`"$root`"", "-s", "res://bench/diag_v77_hang.gd")
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$done = $h.p.WaitForExit([int](($hangSec + $LimitSec) * 1000))
if (-not $done) { try { $h.p.Kill() } catch {} }
$t = $sw.Elapsed.TotalSeconds
$text = "" + (Get-Content $h.out -Raw -Encoding UTF8) + (Get-Content $h.err -Raw -Encoding UTF8)
Check ("зависшая сцена: предохранитель закрыл за {0:N1} с (лимит {1} с), код {2}, сообщение с именем скрипта" -f $t, $hangSec, $(if ($done) { $h.p.ExitCode } else { "-" })) `
	($done -and $h.p.ExitCode -eq [int]$cfg.watchdog_exit_code -and $t -ge $hangSec -and $text -match "предохранитель — diag_v77_hang\.gd")

# 2) настоящая игра, WM_CLOSE окну
foreach ($scene in @("", "battle", "hub", "pick")) {
	$argv = @("--path", "`"$root`"")
	if ($scene -ne "") { $argv += @("--", "--scene=$scene") }
	$name = $(if ($scene -eq "") { "игра: главное меню" } else { "игра: --scene=$scene" })
	$h = Launch $argv
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$ready = $false
	while ($sw.Elapsed.TotalSeconds -lt $StartSec -and -not $h.p.HasExited) {
		$h.p.Refresh()
		$txt = "" + (Get-Content $h.out -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
		if ($h.p.MainWindowHandle -ne 0 -and ($scene -eq "" -or $txt -match "SCENE\|$scene")) { $ready = $true; break }
		Start-Sleep -Milliseconds 250
	}
	Start-Sleep -Seconds 2   # пара секунд жизни сцены: подсказки, музыка, автозагрузки
	Check "$name`: окно открылось, сцена готова" $ready
	$h.p.CloseMainWindow() | Out-Null
	Finish $h "$name, WM_CLOSE" $LimitSec
}

$env:APPDATA = $oldApp
Remove-Item -Recurse -Force $app -ErrorAction SilentlyContinue
Write-Host "EXIT: провалов $fails"
exit $(if ($fails -gt 0) { 1 } else { 0 })
