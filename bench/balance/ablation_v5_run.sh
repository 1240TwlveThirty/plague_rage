#!/bin/sh
# Абляция v5 (задача 7, Клич Благодати): sh bench/balance/ablation_v5_run.sh "<godot.exe>"   (из корня проекта)
# Боты B2 и B5, seed 1-5, осада I, волны без предела, бот жмёт клич при готовности и зомби ближе 400 к отряду (calib_worker --war-cry on).
# Наборы: без даров; war_cry 1-3; все видимые дары ур. 1-3 с кличем (all_N) и без него (allno_N).
# Файлы bench/balance/ablation_v5_runs/, итог bench/gift_ablation_v5.txt (ablation_aggregate.gd, версия v5).
GODOT="$1"; VER="v5"; DIR="bench/balance/ablation_${VER}_runs"
T0=$(date +%s)
GIFTS="war_cry"
ALL="tempered_steel sturdy_shields marksmen spoils mine reserve armory smith_thomas repairers watch discipline radiance_reserve infirmary war_cry"
ALLNO="tempered_steel sturdy_shields marksmen spoils mine reserve armory smith_thomas repairers watch discipline radiance_reserve infirmary"
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
join() {   # <ids> <уровень>
	out=""
	for g in $1; do out="$out,$g:$2"; done
	echo "${out#,}"
}
run none ""
for lvl in 1 2 3; do
	for g in $GIFTS; do
		run "${g}_$lvl" "$g:$lvl"
	done
	run "all_$lvl" "$(join "$ALL" $lvl)"
	run "allno_$lvl" "$(join "$ALLNO" $lvl)"
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 100, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/ablation_aggregate.gd -- $(( $(date +%s) - T0 )) $VER war_cry
