#!/bin/sh
# Абляция карточек v2 (задача 6b, этап 4): бот B7 (держит пехотой и ремонтирует ворота ниже 60%), seed 1-5, без даров, осада I.
# sh bench/balance/card_v2_run.sh "<godot.exe>" (из корня проекта). Наборы: без карточек; карточки №10, 11, 12, 14, 16, 31 по одной;
# дары «Ремонтники» (repairers) и «Дозор» (watch) ур. 1-3. Файлы bench/balance/card_v2_runs/, итог bench/card_ablation_v2.txt.
GODOT="$1"; DIR="bench/balance/card_v2_runs"
T0=$(date +%s)
CARDS="steadfast mobile_reserve sentries stone_parapets quick_repair iron_wall"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <имя> <аргументы воркера после бота и seed...>
	name="$1"; shift
	for seed in 1 2 3 4 5; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- B7 $seed "$@" > "$DIR/${name}_B7_s$seed.txt" 2> "$DIR/${name}_B7_s${seed}_err.txt" &
	done
}
one none
for c in $CARDS; do
	one "$c" --cards $c
done
for g in repairers watch; do
	for lvl in 1 2 3; do
		one "${g}_$lvl" --gifts "$g:$lvl"
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 65, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/card_v2_aggregate.gd -- $(( $(date +%s) - T0 ))
