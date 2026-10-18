#!/bin/sh
# Абляция даров: sh bench/balance/ablation_run.sh "<godot.exe>"   (из корня проекта; время прогона — в шапке итога)
# Боты B2 и B5, seed 1-5, осада I, волны без предела. Наборы: без даров, каждый видимый дар отдельно на уровнях 1-3, все они вместе на уровне 1, 2, 3.
# Забеги — bench/balance/calib_worker.gd --gifts ...; файлы bench/balance/ablation_v3_runs/<набор>_<бот>_s<seed>.txt; итог — bench/gift_ablation_v3.txt
# (непрерывная волна смерти, золото в начале последней волны после покупок). Скрытый fortress_walls не прогоняется.
# Прежние прогоны: bench/gift_ablation_v1.txt (золото за убитого 2) и bench/gift_ablation_v2.txt, папки ablation_runs/ и ablation_v2_runs/ — не пересчитываются.
GODOT="$1"; DIR="bench/balance/ablation_v3_runs"
T0=$(date +%s)
GIFTS="tempered_steel sturdy_shields marksmen spoils mine reserve"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
run() {   # <набор> <аргумент --gifts или пусто>
	for bot in B2 B5; do
		for seed in 1 2 3 4 5; do
			while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
			if [ -z "$2" ]; then
				"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed > "$DIR/$1_${bot}_s$seed.txt" 2> "$DIR/$1_${bot}_s${seed}_err.txt" &
			else
				"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed --gifts "$2" > "$DIR/$1_${bot}_s$seed.txt" 2> "$DIR/$1_${bot}_s${seed}_err.txt" &
			fi
		done
	done
}
run none ""
for lvl in 1 2 3; do
	all=""
	for g in $GIFTS; do
		run "${g}_$lvl" "$g:$lvl"
		all="$all,$g:$lvl"
	done
	run "all_$lvl" "${all#,}"
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 220, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/ablation_aggregate.gd -- $(( $(date +%s) - T0 ))
