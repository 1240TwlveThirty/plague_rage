# Сборщик свипа p31 x gate_max_gain -> bench/balance_p31_gate.txt
$enc = New-Object Text.UTF8Encoding $false
$inv = [Globalization.CultureInfo]::InvariantCulture
$dir = "C:\Projects\plague-rage\bench\balance\p31_gate_runs"
$runs = @(); $waves = @()
foreach ($file in Get-ChildItem "$dir\g*.txt" | ? Name -notmatch "_err") {
  foreach ($l in Get-Content $file.FullName -Encoding utf8) {
    $f = $l -split ","
    if ($f[0] -eq "RUN") { $runs += [pscustomobject]@{g=[int]$f[1];bot=$f[2];seed=[int]$f[3];defeat=[int]$f[4];full=[int]$f[5]} }
    if ($f[0] -eq "WAVE") { $waves += [pscustomobject]@{g=[int]$f[1];bot=$f[2];seed=[int]$f[3];w=[int]$f[4];z=[int]$f[5];army=[int]$f[6];loss=[int]$f[7];gold=[int]$f[8];gate=[int]$f[9];gmax=[int]$f[10]} } } }
function DW($r) { if ($r.defeat -eq 0) { if ($r.full -eq 1) { 41 } else { $null } } else { $r.defeat } }
function Fmt($v) { if ($v -eq $null) { "—" } elseif ($v -ge 41) { "≥40" } else { "$v" } }
function Med($a) { $s = @($a | ? { $_ -ne $null } | Sort-Object); if ($s.Count -eq 0) { return $null }; $s[[int][math]::Floor($s.Count / 2)] }
$L = @("balance_p31_gate: точка p31 (HP зомби 1.8, hp_growth 0.04, dmg_growth 0.04, count_step 45, gold_per_kill 2, gate_hp 1500), ремонт ворот = +gate_max_gain к максимуму.",
  "Боты B1 (inf_pack, weapons, archer_pack, gate), B2 (inf_pack, weapons), B3 (gate); покупки на всё золото; 3 seed; волна до 40.",
  "Критерии: (1) B1 медиана волны поражения 22–32; (2) B3 проигрывает до волны 12 (все seed); (3) потери B1 на волнах 1–10 3–15%; (4) на 11–20 выше; (5) волна 1 без урона воротам.", "",
  "gate_max_gain | B1 s1/s2/s3 (медиана) | B2 | B3 | критерии | потери B1 1–10 | 11–20 | ворота B1 конец/макс, волна 10 | волна 20 | армия/золото B1, волна 10 | 20 | 30")
foreach ($gain in 150, 300, 600) {
  $d = @{}; foreach ($b in "B1","B2","B3") { $d[$b] = @(1..3 | % { $s = $_; DW ($runs | ? { $_.g -eq $gain -and $_.bot -eq $b -and $_.seed -eq $s } | Select-Object -First 1) }) }
  $w1 = @($waves | ? { $_.g -eq $gain -and $_.bot -eq "B1" })
  $e = @($w1 | ? { $_.w -le 10 -and $_.army -gt 0 } | % { $_.loss / $_.army }); $em = if ($e.Count) { ($e | Measure-Object -Average).Average * 100 } else { 0 }
  $late = @($w1 | ? { $_.w -ge 11 -and $_.w -le 20 -and $_.army -gt 0 } | % { $_.loss / $_.army }); $lm = if ($late.Count) { ($late | Measure-Object -Average).Average * 100 } else { $null }
  $b1m = Med $d["B1"]
  $c = @(($b1m -ne $null -and $b1m -ge 22 -and $b1m -le 32), (@($d["B3"] | ? { $_ -ne $null -and $_ -lt 12 }).Count -eq 3), ($em -ge 3 -and $em -le 15), ($lm -ne $null -and $lm -gt $em), (@($w1 | ? { $_.w -eq 1 -and $_.gate -lt $_.gmax }).Count -eq 0))
  $s1 = $w1 | ? seed -eq 1
  $at = { param($w, $what) $r = $s1 | ? w -eq $w | Select-Object -First 1; if (-not $r) { "—" } elseif ($what -eq "gate") { "$($r.gate)/$($r.gmax)" } else { "$($r.army)/$($r.gold)" } }
  $L += [string]::Format($inv, "{0,13} | {1}/{2}/{3} ({4}) | {5}/{6}/{7} | {8}/{9}/{10} | {11}/5 ({12}) | {13:F1}% | {14} | {15} | {16} | {17} | {18} | {19}", $gain,
    (Fmt $d["B1"][0]), (Fmt $d["B1"][1]), (Fmt $d["B1"][2]), (Fmt $b1m), (Fmt $d["B2"][0]), (Fmt $d["B2"][1]), (Fmt $d["B2"][2]), (Fmt $d["B3"][0]), (Fmt $d["B3"][1]), (Fmt $d["B3"][2]),
    @($c | ? { $_ }).Count, (($c | % { if ($_) { "+" } else { "-" } }) -join ""), $em, $(if ($lm -ne $null) { [string]::Format($inv, "{0:F1}%", $lm) } else { "—" }),
    (& $at 10 "gate"), (& $at 20 "gate"), (& $at 10 "army"), (& $at 20 "army"), (& $at 30 "army")) }
$L += ""; $L += "Кривые B1, seed 1 (волна: армия на старте, потери, ворота конец/макс):"
foreach ($gain in 150, 300, 600) {
  $L += "gate_max_gain $gain :"
  $L += (($waves | ? { $_.g -eq $gain -and $_.bot -eq "B1" -and $_.seed -eq 1 } | Sort-Object w | % { "  в{0}: {1} −{2}, ворота {3}/{4}" -f $_.w, $_.army, $_.loss, $_.gate, $_.gmax }) -join "`n") }
[IO.File]::WriteAllText("C:\Projects\plague-rage\bench\balance_p31_gate.txt", ($L -join "`n") + "`n", $enc)
$L[0..7]