# Сборщик balance_gap -> bench/balance_gap.txt. Параметр -Conclusion: строка вывода (пишется последней).
param([string]$Conclusion = "")
$enc = New-Object Text.UTF8Encoding $false
$inv = [Globalization.CultureInfo]::InvariantCulture
$dir = "C:\Projects\plague-rage\bench\balance\gap_runs"
$bots = "B1","B2","B4","B5","B6","B7"
$desc = @{B1="пехота, оружие, лучники, ворота"; B2="пехота, оружие"; B4="пехота, оружие, лучники (без ворот)"; B5="пехота, лучники, ворота (без оружия)";
  B6="случайный доступный товар, до 2 покупок за передышку, остаток лежит"; B7="как B1, пехота на 150 px вперёд к дороге"}
$runs = @(); $waves = @()
foreach ($file in Get-ChildItem "$dir\B*.txt" | ? Name -notmatch "_err") {
  foreach ($l in Get-Content $file.FullName -Encoding utf8) {
    $f = $l -split ","
    if ($f[0] -eq "RUN") { $runs += [pscustomobject]@{bot=$f[1];seed=[int]$f[2];defeat=[int]$f[3];full=[int]$f[4]} }
    if ($f[0] -eq "WAVE") { $waves += [pscustomobject]@{bot=$f[1];seed=[int]$f[2];w=[int]$f[3];z=[int]$f[4];inf=[int]$f[5];arch=[int]$f[6];infEnd=[int]$f[7];archEnd=[int]$f[8];
      goldStart=[int]$f[9];goldAfter=[int]$f[10];buys=$f[11];total=$f[12];ka=[int]$f[13];kmi=[int]$f[14];kma=[int]$f[15];kills=[int]$f[16];gate=[int]$f[17];gmax=[int]$f[18];ticks=[int]$f[19]} } } }
function DW($r) { if (-not $r) { $null } elseif ($r.defeat -eq 0) { if ($r.full -eq 1) { 41 } else { $null } } else { $r.defeat } }
function Fmt($v) { if ($v -eq $null) { "—" } elseif ($v -ge 41) { "≥40" } else { "$v" } }
function Med($a) { $s = @($a | ? { $_ -ne $null } | Sort-Object); if ($s.Count -eq 0) { return $null }; $s[[int][math]::Floor($s.Count / 2)] }
function Pct($a, $b) { if ($b -le 0) { "—" } else { [string]::Format($inv, "{0:F0}%", 100.0 * $a / $b) } }
$bad = @($waves | ? { $_.ka + $_.kmi + $_.kma -ne $_.kills }).Count
$L = @("balance_gap: рабочие JSON (p31, gate_max_gain 300), 3 seed, лимит 40 волн. Покупки на всё золото по кругу (кроме B6).",
  "Счётчики (bench/balance/main_gap.gd): добивающий удар — стрела / ближний бой пехоты / ближний бой лучников. Строк, где сумма не равна убитым за волну: $bad.", "",
  "Волны поражения:", "бот | s1/s2/s3 (медиана) | покупки")
foreach ($b in $bots) {
  $d = @(1..3 | % { $s = $_; DW ($runs | ? { $_.bot -eq $b -and $_.seed -eq $s } | Select-Object -First 1) })
  $L += "{0} | {1}/{2}/{3} ({4}) | {5}" -f $b, (Fmt $d[0]), (Fmt $d[1]), (Fmt $d[2]), (Fmt (Med $d)), $desc[$b] }
$L += ""; $L += "Срезы по волнам, seed 1 (куплено всего = пехота-лучники-оружие-ворота на старте волны; доля стрел — по трём seed):"
$L += "бот | волна | зомби | пехота/лучники на старте | потери пехота/лучники | золото на старте передышки | куплено всего | убийства: стрелы / пехота / лучники врукопашную | доля стрел s1 | доля стрел 3 seed"
foreach ($b in "B1","B2","B4","B5","B6","B7") {
  foreach ($w in 5, 10, 15, 20) {
    $r = $waves | ? { $_.bot -eq $b -and $_.seed -eq 1 -and $_.w -eq $w } | Select-Object -First 1
    if (-not $r) { $L += "{0} | {1} | — (не дожил)" -f $b, $w; continue }
    $all = @($waves | ? { $_.bot -eq $b -and $_.w -eq $w })
    $L += "{0} | {1} | {2} | {3}/{4} | {5}/{6} | {7} | {8} | {9} / {10} / {11} | {12} | {13}" -f $b, $w, $r.z, $r.inf, $r.arch, ($r.inf - $r.infEnd), ($r.arch - $r.archEnd),
      $r.goldStart, $r.total, $r.ka, $r.kmi, $r.kma, (Pct $r.ka $r.kills), (Pct (($all | Measure-Object ka -Sum).Sum) (($all | Measure-Object kills -Sum).Sum)) } }
$L += ""; $L += "Итог по всем волнам до поражения (сумма трёх seed):"
$L += "бот | убито зомби | доля стрел | золото на старте последней передышки (s1) | куплено всего к концу (s1)"
foreach ($b in $bots) {
  $all = @($waves | ? bot -eq $b); $last = $waves | ? { $_.bot -eq $b -and $_.seed -eq 1 } | Sort-Object w | Select-Object -Last 1
  $k = ($all | Measure-Object kills -Sum).Sum
  $L += "{0} | {1} | {2} | {3} | {4}" -f $b, $k, (Pct (($all | Measure-Object ka -Sum).Sum) $k), $last.goldStart, $last.total }
$L += ""; $L += "Кривые, seed 1 (волна: пехота+лучники на старте, потери, золото на старте передышки, покупки в передышке, доля стрел, ворота конец/макс):"
foreach ($b in $bots) {
  $L += "$b :"
  $L += (($waves | ? { $_.bot -eq $b -and $_.seed -eq 1 } | Sort-Object w | % { "  в{0}: {1}+{2} −{3}, золото {4}, покупки {5}, стрелы {6}, ворота {7}/{8}" -f $_.w, $_.inf, $_.arch,
    (($_.inf - $_.infEnd) + ($_.arch - $_.archEnd)), $_.goldStart, $_.buys, (Pct $_.ka $_.kills), $_.gate, $_.gmax }) -join "`n") }
if ($Conclusion) { $L += ""; $L += "Вывод: $Conclusion" }
[IO.File]::WriteAllText("C:\Projects\plague-rage\bench\balance_gap.txt", ($L -join "`n") + "`n", $enc)
$L