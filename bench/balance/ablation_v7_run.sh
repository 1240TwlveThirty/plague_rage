#!/bin/sh
# Абляция v7 (задача 8, этап D): sh bench/balance/ablation_v7_run.sh "<godot.exe>"   (из корня проекта)
# B8 (держит пехоту и копейщиков, ремонтирует, половина пехотных покупок — копейщики) и B7, seed 1-5, осада I, волны без предела.
# B8: без даров; дар «Стена щитов» (spear_wall) 1-3; карточки №9 «Строй щитов» и №11 «Подвижный резерв»; все видимые дары ур. 1-3 с «Стеной щитов»
# (all_N) и без неё (allno_N). B7: без даров; карточки №9 и №11. Файлы bench/balance/ablation_v7_runs/, итоги bench/gift_ablation_v7.txt
# и bench/card_ablation_v3.txt (bench/balance/v7_aggregate.gd).
GODOT="$1"; DIR="bench/balance/ablation_v7_runs"
T0=$(date +%s)
ALL="tempered_steel sturdy_shields marksmen spoils mine reserve armory smith_thomas repairers watch discipline radiance_reserve infirmary war_cry spear_wall"
ALLNO="tempered_steel sturdy_shields marksmen spoils mine reserve armory smith_thomas repairers watch discipline radiance_reserve infirmary war_cry"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <набор> <бот> <аргументы воркера после бота и seed>
	name="$1"; bot="$2"; shift 2
	for seed in 1 2 3 4 5; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed "$@" > "$DIR/${name}_${bot}_s$seed.txt" 2> "$DIR/${name}_${bot}_s${seed}_err.txt" &
	done
}
join() {   # <ids> <уровень>
	out=""
	for g in $1; do out="$out,$g:$2"; done
	echo "${out#,}"
}
for bot in B7 B8; do
	one none $bot
	one card_shield_wall $bot --cards shield_wall
	one card_mobile_reserve $bot --cards mobile_reserve
done
for lvl in 1 2 3; do
	one "spear_wall_$lvl" B8 --gifts "spear_wall:$lvl"
	one "all_$lvl" B8 --gifts "$(join "$ALL" $lvl)"
	one "allno_$lvl" B8 --gifts "$(join "$ALLNO" $lvl)"
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 75, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/v7_aggregate.gd -- $(( $(date +%s) - T0 ))
