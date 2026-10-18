#!/bin/sh
# Абляция v6 (задача 6b, этап 2: лечение между волнами heal_base 0.5): sh bench/balance/ablation_v6_run.sh "<godot.exe>"   (из корня проекта)
# Боты B2 и B5, seed 1-5, осада I, волны без предела. Наборы: без даров; «Лазарет» (infirmary) 1-3; карточка №40 «Полевая кухня»
# (--cards field_kitchen). Файлы bench/balance/ablation_v6_runs/, итог bench/gift_ablation_v6.txt (ablation_aggregate.gd, версия v6).
GODOT="$1"; VER="v6"; DIR="bench/balance/ablation_${VER}_runs"
T0=$(date +%s)
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
run() {   # <набор> <аргументы воркера после бота и seed>
	name="$1"; shift
	for bot in B2 B5; do
		for seed in 1 2 3 4 5; do
			while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
			"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed "$@" > "$DIR/${name}_${bot}_s$seed.txt" 2> "$DIR/${name}_${bot}_s${seed}_err.txt" &
		done
	done
}
run none
for lvl in 1 2 3; do
	run "infirmary_$lvl" --gifts "infirmary:$lvl"
done
run card_field_kitchen --cards field_kitchen
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 50, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/ablation_aggregate.gd -- $(( $(date +%s) - T0 )) $VER infirmary
