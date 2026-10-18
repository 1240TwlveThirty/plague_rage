#!/bin/sh
# Абляция разброса HP зомби (задача 6b, этап 3): sh bench/balance/spread_ablation_run.sh "<godot.exe>"   (из корня проекта)
# s = 0, 0.10, 0.15, 0.20 (calib_worker --hp-spread s); боты B2 и B5, seed 1-5, без даров; наборы: без карточек; карточки №1, 2, 3, 17, 25, 27,
# 36, 37 по одной; дар «Закалённая сталь» 3. Файлы bench/balance/spread_v1_runs/<s>_<набор>_<бот>_s<seed>.txt, итог bench/spread_ablation_v1.txt.
GODOT="$1"; DIR="bench/balance/spread_v1_runs"
T0=$(date +%s)
CARDS="meteor_blades silver_vs_dead serrated_arrows last_stand desperate_charge long_spears reserve_fund blood_for_blood"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <имя> <аргументы воркера...>
	while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
	name="$1"; shift
	"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- "$@" > "$DIR/$name.txt" 2> "$DIR/${name}_err.txt" &
}
for s in 0 0.10 0.15 0.20; do
	for bot in B2 B5; do
		for seed in 1 2 3 4 5; do
			one "${s}_none_${bot}_s$seed" $bot $seed --hp-spread $s
			for c in $CARDS; do
				one "${s}_${c}_${bot}_s$seed" $bot $seed --hp-spread $s --cards $c
			done
			one "${s}_tempered_steel_3_${bot}_s$seed" $bot $seed --hp-spread $s --gifts tempered_steel:3
		done
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 400, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/spread_aggregate.gd -- $(( $(date +%s) - T0 ))
