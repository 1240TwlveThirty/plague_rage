#!/bin/sh
# Абляция даров: sh bench/balance/ablation_run.sh "<godot.exe>"   (из корня проекта; время прогона — в шапке итога)
# Боты B2 и B5, seed 1-5, осада I, волны без предела. Наборы: без даров, каждый дар из GIFTS отдельно на уровнях 1-3,
# все видимые дары gifts.json вместе на уровне 1, 2, 3 (ALL). Метрика — непрерывная волна смерти (bench/balance/ablation_aggregate.gd).
# Забеги — bench/balance/calib_worker.gd --gifts ...; файлы bench/balance/ablation_$VER_runs/<набор>_<бот>_s<seed>.txt; итог — bench/gift_ablation_$VER.txt.
# v4 (задача 6a): шесть даров экономики и «Резерв» +10/20/30%. Прежние прогоны v1-v3 (gift_ablation_v1..v3.txt, их папки) не пересчитываются;
# v3 шёл по GIFTS="tempered_steel sturdy_shields marksmen spoils mine reserve" при «Резерве» +5/10/15%.
GODOT="$1"; VER="v4"; DIR="bench/balance/ablation_${VER}_runs"
T0=$(date +%s)
GIFTS="armory smith_thomas repairers watch discipline radiance_reserve reserve"
ALL="tempered_steel sturdy_shields marksmen spoils mine reserve armory smith_thomas repairers watch discipline radiance_reserve"
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
	for g in $GIFTS; do
		run "${g}_$lvl" "$g:$lvl"
	done
	all=""
	for g in $ALL; do
		all="$all,$g:$lvl"
	done
	run "all_$lvl" "${all#,}"
done
wait
N=$(( (1 + 3 * $(echo $GIFTS | wc -w) + 3) * 10 ))
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из $N, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/ablation_aggregate.gd -- $(( $(date +%s) - T0 )) $VER "$(echo $GIFTS | tr ' ' ',')"
