# Рабочий минимум тестов plague-rage по очереди: PASS или FAIL и время каждого шага.
# Запуск из любого места:  $env:GODOT_EXE = "<путь к godot.exe>";  powershell -File bench\run_all.ps1 [-Quick]
# -Quick пропускает серию 50 боёв и замеры тика. Каждый шаг не дольше 300 с ($StepTimeoutSec): иначе процесс убивается, шаг FAIL,
# зависшие шаги перечисляются в конце. Смоуки открывают окно игры: во время них не трогать мышь и клавиатуру.
# Регрессия сравнивает рабочий scripts/main.gd с эталоном bench/ref/main_ref.gd (обновить: python bench/make_ref.py [коммит]).
param([switch]$Quick)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT_EXE
if (-not $godot -or -not (Test-Path $godot)) {
	Write-Host "FAIL  GODOT_EXE не задана или файла нет: '$godot'"
	exit 2
}
$tmp = Join-Path $env:TEMP "plague_rage_run_all"
New-Item -ItemType Directory -Force $tmp | Out-Null
$failed = 0
$StepTimeoutSec = 300   # шаг дольше — процесс убивается, шаг считается проваленным
$hungSteps = @()
$total = [System.Diagnostics.Stopwatch]::StartNew()

# Один шаг: программа с аргументами, вывод в файл; PASS — код 0, нет слов провала, есть ожидаемая строка.
function Step([string]$name, [string]$exe, [string[]]$argv, [string]$expect) {
	$out = Join-Path $tmp "out.txt"
	$err = Join-Path $tmp "err.txt"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$p = Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory $root -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
	$null = $p.Handle   # без этого ExitCode после WaitForExit(мс) бывает пустым
	$hung = -not $p.WaitForExit($StepTimeoutSec * 1000)
	if ($hung) {
		# завис: убить процесс, шаг провален, прогон идёт дальше
		try { $p.Kill() } catch {}
		$p.WaitForExit(10000) | Out-Null
		$script:hungSteps += ("{0} ({1:N0} с)" -f $name, $sw.Elapsed.TotalSeconds)
	}
	$sw.Stop()
	$text = (Get-Content $out -Raw -Encoding UTF8) + "`n" + (Get-Content $err -Raw -Encoding UTF8)
	$bad = [regex]::Matches($text, "НЕТ|FAIL|SCRIPT ERROR|Parse Error|Failed to load").Count
	$ok = (-not $hung) -and ($p.ExitCode -eq 0) -and ($bad -eq 0) -and ($text -match $expect)
	if ($hung) { $text += "`nFAIL: таймаут $StepTimeoutSec с, процесс убит" }
	$line = ""
	if ($text -match "(?m)^.*($expect).*$") { $line = $Matches[0].Trim() }
	if ($line.Length -gt 150) { $line = $line.Substring(0, 150) }
	Write-Host ("{0}  {1,-34} {2,6:N1} с  {3}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $name, $sw.Elapsed.TotalSeconds, $line)
	if (-not $ok) {
		$script:failed += 1
		$text -split "`n" | Where-Object { $_ -match "НЕТ|FAIL|SCRIPT ERROR|Parse Error|Failed to load" } | ForEach-Object { Write-Host ("        " + $_.Trim()) }
	}
}

function Godot([string]$name, [string]$script, [string]$expect, [string[]]$extra = @(), [switch]$Window) {
	$argv = @()
	if (-not $Window) { $argv += "--headless" }
	$argv += @("--path", "`"$root`"", "-s", $script)
	if ($extra.Count -gt 0) { $argv += "--"; $argv += $extra }
	Step $name $godot $argv $expect
}

Step "копии main (make_v39.py)" "python" @("bench/make_v39.py") "ok"
Step "парсинг main.gd" $godot @("--headless", "--path", "`"$root`"", "--check-only", "-s", "res://scripts/main.gd") "Godot Engine"
Godot "регрессия против эталона" "res://bench/regress.gd" "REGRESS: провалов 0"
Godot "пауза, деление, посты (v39)" "res://bench/check_v39.gd" "CHECK: провалов 0"
Godot "выбор, группа, детерминизм (v40)" "res://bench/check_v40.gd" "CHECK: провалов 0"
Godot "забег: Game, победа, хаб (v41)" "res://bench/check_v41.gd" "CHECK: провалов 0"
Godot "сохранение, дневник, концовки (v42)" "res://bench/check_v42.gd" "CHECK: провалов 0"
Godot "модификаторы: дары (v43)" "res://bench/check_v43.gd" "CHECK: провалов 0"
Godot "Сияние, магазин даров (v44)" "res://bench/check_v44.gd" "CHECK: провалов 0"
Godot "статы на лету, Mods.value (v46)" "res://bench/check_v46.gd" "CHECK: провалов 0"
Godot "статы волны, доход, скорость удара (v47)" "res://bench/check_v47.gd" "CHECK: провалов 0"
Godot "карточки: данные, валидатор (v48c)" "res://bench/check_v48_cards.gd" "CHECK: провалов 0"
Godot "карточки: условия C и особые K (v49c)" "res://bench/check_v49_conds.gd" "CHECK: провалов 0"
Godot "карточки: выбор в забеге (v53)" "res://bench/check_v53_pick.gd" "CHECK: провалов 0"
Godot "Клич Благодати (v54)" "res://bench/check_v54_warcry.gd" "CHECK: провалов 0"
Godot "карточки в HUD: индикаторы (v51)" "res://bench/check_v51.gd" "CHECK: провалов 0"
Godot "разброс HP зомби (v52)" "res://bench/check_v52.gd" "CHECK: провалов 0"
Godot "иконки карточек и даров (v56)" "res://bench/check_v56.gd" "CHECK: провалов 0"
Godot "приказ «отход» (v53)" "res://bench/check_v53.gd" "CHECK: провалов 0"
Godot "копейщики (v54)" "res://bench/check_v54.gd" "CHECK: провалов 0"
Godot "блок и «Стена щитов» (v55)" "res://bench/check_v55.gd" "CHECK: провалов 0"
Godot "возврат павших, «Лазарет» и №40 (v57)" "res://bench/check_v57.gd" "CHECK: провалов 0"
Godot "скорость боя attack_rate (v58)" "res://bench/check_v58.gd" "CHECK: провалов 0"
Godot "замена урона скоростью атаки в данных (v59)" "res://bench/check_v59.gd" "CHECK: провалов 0"
Godot "герой (v60)" "res://bench/check_v60.gd" "CHECK: провалов 0"
Godot "ручной удар героя (v61)" "res://bench/check_v61.gd" "CHECK: провалов 0"
Godot "карточки героя, место в тройке (v64)" "res://bench/check_v64.gd" "CHECK: провалов 0"
Godot "арты: спрайтшит героя, иллюстрации отрядов (v65)" "res://bench/check_v65.gd" "CHECK: провалов 0"
Godot "рамки: арт и срез 9-slice (v68)" "res://bench/make_ui_scaled.gd" "UI_ART: проверка пройдена" @("check")
Godot "рамки: тема и где применена (v68)" "res://bench/check_v68_ui.gd" "CHECK: провалов 0"
Godot "верхняя панель боя и окошко Сияния (v69)" "res://bench/check_v69_hud.gd" "CHECK: провалов 0"
Godot "меню, хаб, пауза по Esc (v45)" "res://bench/check_v45.gd" "CHECK: провалов 0"
Godot "подгонка слоя замка (v48)" "res://bench/check_v48.gd" "CHECK: провалов 0"
Godot "настройки, полный экран (v49)" "res://bench/check_v49.gd" "CHECK: провалов 0"
Godot "клавиши, переназначение (v50)" "res://bench/check_v50.gd" "CHECK: провалов 0"
Godot "переводы ru/en (таблица, ключи)" "res://bench/check_translations.gd" "CHECK: провалов 0"
Godot "геометрия расстановки (v27)" "res://bench/check_v27.gd" "раздача слотов"
Godot "отряды: создание, слияние (v28)" "res://bench/check_v28.gd" "да"
Godot "управление строем (v29)" "res://bench/check_v29.gd" "да"
Godot "смоук с окном: пауза (v39)" "res://bench/smoke_v39.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: мышь (v40)" "res://bench/smoke_v40.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: меню, хаб (v41)" "res://bench/smoke_v41.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: дневник (v42)" "res://bench/smoke_v42.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: F11 (v49)" "res://bench/smoke_v49.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: языки (v51)" "res://bench/smoke_v51.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: звук (v52)" "res://bench/smoke_v52.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: выбор карточки (v53)" "res://bench/smoke_v53_cards.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: возврат павших, «Оружие: скорость атаки» (6d)" "res://bench/smoke_6d.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: Клич Благодати (v54)" "res://bench/smoke_v54_warcry.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: карточки в HUD (v51h)" "res://bench/smoke_v51_cardhud.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: иконки в хабе (v56)" "res://bench/smoke_v56_icons.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: герой (v60)" "res://bench/smoke_v60.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: удар героя (v61)" "res://bench/smoke_v61.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: кровь, искры, пятна (v62)" "res://bench/smoke_v62.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: куски тела, тряска на удар (v63)" "res://bench/smoke_v63.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: карточки героя (v64)" "res://bench/smoke_v64_cards.gd" "SMOKE: провалов 0" @("$tmp") -Window
Godot "смоук с окном: арты — кнопки, герой (v65)" "res://bench/smoke_v65_art.gd" "SMOKE: провалов 0" @("$tmp") -Window
if (-not $Quick) {
	Godot "серия 50 боёв" "res://bench/series.gd" "SERIES\|"
	Godot "тик: волна 20 слоя 1" "res://bench/time_v35.gd" "TIME\|" @("1", "20", "0", "caps", "1", "res://scripts/main.gd")
	Godot "тик: 3000 юнитов, синтетика" "res://bench/time_v39.gd" "SYN\|" @("res://bench/main_v39_3000.gd")
	Godot "тик: 3000 юнитов с копейщиками" "res://bench/time_v39.gd" "SYN\|" @("res://bench/main_v39_3000.gd", "spear")
	Godot "тик: 3000 юнитов с героем" "res://bench/time_v39.gd" "SYN\|" @("res://bench/main_v39_3000.gd", "hero")
}
$total.Stop()
if ($hungSteps.Count -gt 0) {
	Write-Host ("Зависли (таймаут {0} с): {1}" -f $StepTimeoutSec, ($hungSteps -join "; "))
} else {
	Write-Host "Зависших шагов нет"
}
Write-Host ("{0}: провалов {1}, всего {2:N0} с" -f $(if ($failed -eq 0) { "ИТОГ PASS" } else { "ИТОГ FAIL" }), $failed, $total.Elapsed.TotalSeconds)
exit $(if ($failed -eq 0) { 0 } else { 1 })
