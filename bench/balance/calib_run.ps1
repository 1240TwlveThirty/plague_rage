# Калибровка осады I, этап 1: 30 забегов ботов (B1-B6 x seed 1-5) параллельно, затем сборка bench/calibration_v1.txt.
# Запуск:  $env:GODOT_EXE = "<путь к godot.exe>";  powershell -File bench\balance\calib_run.ps1 [-Jobs 8]
param([int]$Jobs = 8)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$godot = $env:GODOT_EXE
if (-not $godot -or -not (Test-Path $godot)) {
	Write-Host "FAIL  GODOT_EXE не задана или файла нет: '$godot'"
	exit 2
}
$runs = Join-Path $PSScriptRoot "calib_runs"
New-Item -ItemType Directory -Force $runs | Out-Null
Remove-Item (Join-Path $runs "*.txt") -Confirm:$false -ErrorAction SilentlyContinue
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$live = @()
foreach ($bot in "B1", "B2", "B3", "B4", "B5", "B6") {
	foreach ($seed in 1..5) {
		while (@($live | Where-Object { -not $_.HasExited }).Count -ge $Jobs) { Start-Sleep -Milliseconds 300 }
		$argv = @("--headless", "--path", "`"$root`"", "-s", "res://bench/balance/calib_worker.gd", "--", $bot, "$seed")
		$live += Start-Process -FilePath $godot -ArgumentList $argv -WorkingDirectory $root -NoNewWindow -PassThru `
			-RedirectStandardOutput (Join-Path $runs "${bot}_s$seed.txt") -RedirectStandardError (Join-Path $runs "${bot}_s${seed}_err.txt")
	}
}
$live | ForEach-Object { $_.WaitForExit() }
$done = @(Get-ChildItem $runs -Filter "B*_s?.txt" | Where-Object { (Get-Content $_.FullName -Raw) -match "(?m)^RUN," }).Count
$errs = @(Get-ChildItem $runs -Filter "*_err.txt" | Where-Object { $_.Length -gt 0 }).Count
Write-Host ("забегов завершено {0} из 30, файлов с ошибками {1}, {2:N0} с" -f $done, $errs, $sw.Elapsed.TotalSeconds)
& $godot --headless --path $root -s res://bench/balance/calib_aggregate.gd
exit $(if ($done -eq 30 -and $errs -eq 0) { 0 } else { 1 })
