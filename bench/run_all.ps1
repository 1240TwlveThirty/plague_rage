# Рабочий минимум тестов plague-rage по очереди: PASS или FAIL и время каждого шага.
# Запуск из любого места:  $env:GODOT_EXE = "<путь к godot.exe>";  powershell -File bench\run_all.ps1 [-Quick]
# -Quick пропускает серию 50 боёв и замеры тика. Смоуки открывают окно игры: во время них не трогать мышь и клавиатуру.
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
$total = [System.Diagnostics.Stopwatch]::StartNew()

# Один шаг: программа с аргументами, вывод в файл; PASS — код 0, нет слов провала, есть ожидаемая строка.
function Step([string]$name, [string]$exe, [string[]]$argv, [string]$expect) {
	$out = Join-Path $tmp "out.txt"
	$err = Join-Path $tmp "err.txt"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$p = Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory $root -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
	$sw.Stop()
	$text = (Get-Content $out -Raw -Encoding UTF8) + "`n" + (Get-Content $err -Raw -Encoding UTF8)
	$bad = [regex]::Matches($text, "НЕТ|FAIL|SCRIPT ERROR|Parse Error|Failed to load").Count
	$ok = ($p.ExitCode -eq 0) -and ($bad -eq 0) -and ($text -match $expect)
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
Godot "геометрия расстановки (v27)" "res://bench/check_v27.gd" "раздача слотов"
Godot "отряды: создание, слияние (v28)" "res://bench/check_v28.gd" "да"
Godot "управление строем (v29)" "res://bench/check_v29.gd" "да"
Godot "смоук с окном: пауза (v39)" "res://bench/smoke_v39.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: мышь (v40)" "res://bench/smoke_v40.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: меню, хаб (v41)" "res://bench/smoke_v41.gd" "SMOKE: провалов 0" @() -Window
Godot "смоук с окном: дневник (v42)" "res://bench/smoke_v42.gd" "SMOKE: провалов 0" @() -Window
if (-not $Quick) {
	Godot "серия 50 боёв" "res://bench/series.gd" "SERIES\|"
	Godot "тик: волна 20 слоя 1" "res://bench/time_v35.gd" "TIME\|" @("1", "20", "0", "caps", "1", "res://scripts/main.gd")
	Godot "тик: 3000 юнитов, синтетика" "res://bench/time_v39.gd" "SYN\|" @("res://bench/main_v39_3000.gd")
}
$total.Stop()
Write-Host ("{0}: провалов {1}, всего {2:N0} с" -f $(if ($failed -eq 0) { "ИТОГ PASS" } else { "ИТОГ FAIL" }), $failed, $total.Elapsed.TotalSeconds)
exit $(if ($failed -eq 0) { 0 } else { 1 })
