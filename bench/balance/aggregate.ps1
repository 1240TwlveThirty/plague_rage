# Сборщик свипа баланса: bench/balance/runs/w*.txt -> bench/balance_sweep.txt
$enc = New-Object Text.UTF8Encoding $false
$inv = [Globalization.CultureInfo]::InvariantCulture
$bal = "C:\Projects\plague-rage\bench\balance"
$pts = @{}
foreach ($l in Get-Content "$bal\points.txt" -Encoding utf8) { if ($l -match "^\d") { $f = $l -split ","; $pts[[int]$f[0]] = $f } }
$runs = @(); $waves = @(); $rejects = @{}; $skips = @{}
foreach ($file in Get-ChildItem "$bal\runs\w*.txt" | ? Name -notmatch "_err") {
  foreach ($l in Get-Content $file.FullName -Encoding utf8) {
    $f = $l -split ","
    switch ($f[0]) {
      "RUN" { $runs += [pscustomobject]@{p=[int]$f[1];bot=$f[2];seed=[int]$f[3];defeat=[int]$f[4];full=[int]$f[5]} }
      "WAVE" { $waves += [pscustomobject]@{p=[int]$f[1];bot=$f[2];seed=[int]$f[3];w=[int]$f[4];z=[int]$f[5];army=[int]$f[6];loss=[int]$f[7];gold=[int]$f[8];gate=[int]$f[9];gmax=[int]$f[10]} }
      "REJECT" { $rejects[[int]$f[1]] = $f[2] }
      "SKIP" { $skips[[int]$f[1]] = 1 } } } }
function DW($r) { if ($r -eq $null) { return $null }; if ($r.defeat -eq 0) { if ($r.full -eq 1) { return 41 } else { return $null } }; return $r.defeat }
function Fmt($v) { if ($v -eq $null) { "—" } elseif ($v -ge 41) { "≥40" } else { "$v" } }
$res = @()
foreach ($pp in ($runs | Select-Object -ExpandProperty p -Unique)) {
  if ($rejects.ContainsKey($pp)) { continue }
  $get = { param($b, $s) $runs | ? { $_.p -eq $pp -and $_.bot -eq $b -and $_.seed -eq $s } | Select-Object -First 1 }
  $b1 = @((DW (& $get "B1" 1)), (DW (& $get "B1" 2))); $b2 = @((DW (& $get "B2" 1)), (DW (& $get "B2" 2))); $b3 = @((DW (& $get "B3" 1)), (DW (& $get "B3" 2)))
  if ($b1 -contains $null) { continue }   # точка не досчитана
  $b1m = ($b1[0] + $b1[1]) / 2.0
  $w1 = @($waves | ? { $_.p -eq $pp -and $_.bot -eq "B1" })
  $early = @($w1 | ? { $_.w -le 10 -and $_.army -gt 0 } | % { $_.loss / $_.army })
  $late = @($w1 | ? { $_.w -ge 11 -and $_.w -le 20 -and $_.army -gt 0 } | % { $_.loss / $_.army })
  $em = if ($early.Count) { ($early | Measure-Object -Average).Average * 100 } else { 0 }
  $lm = if ($late.Count) { ($late | Measure-Object -Average).Average * 100 } else { $null }
  $gate1 = @($w1 | ? { $_.w -eq 1 } | ? { $_.gate -lt $_.gmax }).Count -eq 0
  $c = @(($b1m -ge 22 -and $b1m -le 32), (($b3 -notcontains $null) -and $b3[0] -lt 12 -and $b3[1] -lt 12), ($em -ge 3 -and $em -le 15), ($lm -ne $null -and $lm -gt $em), $gate1)
  $s1 = $w1 | ? seed -eq 1
  $at = { param($w) $r = $s1 | ? w -eq $w | Select-Object -First 1; if ($r) { "$($r.army)/$($r.gold)" } else { "—" } }
  $res += [pscustomobject]@{p=$pp; par=$pts[$pp]; b1=$b1; b2=$b2; b3=$b3; b1m=$b1m; em=$em; lm=$lm; gate1=$gate1; score=@($c | ? { $_ }).Count; crit=$c; a10=(& $at 10); a20=(& $at 20); a30=(& $at 30)} }
$ranked = $res | Sort-Object @{e={$_.score}; Descending=$true}, @{e={[math]::Abs($_.b1m - 27)}}
$L = @("balance_sweep: свип баланса, точки из bench/balance/points.txt (60 случайных из сетки 3^6, seed 20261009), по 2 seed, волна до 40, бюджет 90 мин.",
  "Боты: B1 круг inf_pack, weapons, archer_pack, gate; B2 inf_pack, weapons; B3 gate; покупки на всё золото, отряды на стартовых местах, приказ «атака».",
  "Критерии: (1) B1 медиана волны поражения 22–32; (2) B3 проигрывает до волны 12 (оба seed); (3) потери B1 за волну, волны 1–10, 3–15% армии; (4) потери на волнах 11–20 выше, чем на 1–10; (5) первая волна без урона воротам.",
  "", ("Досчитано точек: {0}; отброшено рано (B1 < волны 6): {1}; не начато из-за бюджета: {2}; всего точек 60." -f $res.Count, $rejects.Count, $skips.Count), "",
  "Топ-5 (параметры: HP зомби ×, hp_growth, dmg_growth, count_step, gold_per_kill, gate_hp):",
  "точка | параметры | критерии | B1 s1/s2 | B2 s1/s2 | B3 s1/s2 | потери 1–10, % | потери 11–20, % | армия/золото B1 (seed 1) в. 10 | в. 20 | в. 30")
foreach ($r in ($ranked | Select-Object -First 5)) {
  $par = "×{0}, {1}, {2}, {3}, {4}, {5}" -f $r.par[1], $r.par[2], $r.par[3], $r.par[4], $r.par[5], $r.par[6]
  $L += [string]::Format($inv, "p{0:D2} | {1} | {2}/5 ({3}) | {4}/{5} | {6}/{7} | {8}/{9} | {10:F1} | {11} | {12} | {13} | {14}", $r.p, $par, $r.score, (($r.crit | % { if ($_) { "+" } else { "-" } }) -join ""),
    (Fmt $r.b1[0]), (Fmt $r.b1[1]), (Fmt $r.b2[0]), (Fmt $r.b2[1]), (Fmt $r.b3[0]), (Fmt $r.b3[1]), $r.em, $(if ($r.lm -ne $null) { [string]::Format($inv, "{0:F1}", $r.lm) } else { "—" }), $r.a10, $r.a20, $r.a30) }
$L += ""; $L += "Все досчитанные точки по рейтингу:"
foreach ($r in $ranked) { $L += [string]::Format($inv, "p{0:D2} ({1}) {2}/5, B1 {3}/{4}, B3 {5}/{6}, потери 1–10 {7:F1}%", $r.p, ($r.par[1..6] -join ","), $r.score, (Fmt $r.b1[0]), (Fmt $r.b1[1]), (Fmt $r.b3[0]), (Fmt $r.b3[1]), $r.em) }
if ($ranked) {
  $best = @($ranked)[0]
  $L += ""; $L += "Лучшая точка p{0:D2}: полная кривая B1, seed 1 (волна, зомби, армия на старте, потери, % армии, золото в конце, ворота конец/макс):" -f $best.p
  foreach ($r in ($waves | ? { $_.p -eq $best.p -and $_.bot -eq "B1" -and $_.seed -eq 1 } | Sort-Object w)) {
    $L += [string]::Format($inv, "{0,3} | {1,5} | {2,5} | {3,4} | {4,5:F1}% | {5,6} | {6}/{7}", $r.w, $r.z, $r.army, $r.loss, $(if ($r.army) { 100.0 * $r.loss / $r.army } else { 0 }), $r.gold, $r.gate, $r.gmax) } }
$L += ""; $L += "Отброшенные рано: " + (($rejects.Keys | Sort-Object | % { "p{0:D2}" -f $_ }) -join ", ")
[IO.File]::WriteAllText("C:\Projects\plague-rage\bench\balance_sweep.txt", ($L -join "`n") + "`n", $enc)
$L[0..14]