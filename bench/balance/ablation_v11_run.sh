#!/bin/sh
# Абляция v11 (задача 9, этап C): sh bench/balance/ablation_v11_run.sh "<godot.exe>" [итерация, по умолчанию it0]   (из корня проекта)
# Дар spear_wall («Сомкнутые щиты», блок +п. п. всем воинам со щитом) 1-3 и база без даров; боты B2, B5, B7, seed 1-5, осада I,
# волны без предела. B8 пропущен: копейщики выключены в данных v1. Уровни дара — как в data/gifts.json на момент прогона
# (пишутся в levels.txt итерации). Файлы bench/balance/ablation_v11_runs/<итерация>/, итог bench/gift_ablation_v11.txt
# (bench/balance/abl9_aggregate.gd, все итерации из папки по порядку имён).
GODOT="$1"; IT="${2:-it0}"; DIR="bench/balance/ablation_v11_runs/$IT"
T0=$(date +%s)
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
grep '"spear_wall"' data/gifts.json | sed 's/.*"levels": \(\[[^]]*\]\).*/\1/' > "$DIR/levels.txt"
one() {   # <набор> <бот> <аргументы воркера после бота и seed>
	name="$1"; bot="$2"; shift 2
	for seed in 1 2 3 4 5; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed "$@" > "$DIR/${name}_${bot}_s$seed.txt" 2> "$DIR/${name}_${bot}_s${seed}_err.txt" &
	done
}
for bot in B2 B5 B7; do
	one none $bot
	for lvl in 1 2 3; do
		one "sw_$lvl" $bot --gifts "spear_wall:$lvl"
	done
done
wait
echo "$(( $(date +%s) - T0 ))" > "$DIR/secs.txt"
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 60, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/abl9_aggregate.gd
