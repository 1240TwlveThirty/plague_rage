#!/bin/sh
# Замер героя v2 (задача 11: ручной удар, B9 держит J): sh bench/balance/hero_v2_run.sh "<godot.exe>"   (из корня проекта)
# B7 (без героя) и B9 (B7 + герой, бот ведёт его к скоплению зомби) на одних и тех же seed 1-10, осада I, волны без предела, без даров
# и карточек. Файлы bench/balance/hero_v2_runs/, итог bench/hero_v2.txt (bench/balance/hero_aggregate.gd).
GODOT="$1"; DIR="bench/balance/hero_v2_runs"
T0=$(date +%s)
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
for bot in B7 B9; do
	for seed in 1 2 3 4 5 6 7 8 9 10; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed > "$DIR/${bot}_s$seed.txt" 2> "$DIR/${bot}_s${seed}_err.txt" &
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 20, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/hero_aggregate.gd -- $(( $(date +%s) - T0 )) v2
