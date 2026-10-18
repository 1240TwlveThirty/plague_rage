#!/bin/sh
# Абляция v10 (задача 6d, этап D): sh bench/balance/ablation_v10_run.sh "<godot.exe>"   (из корня проекта)
# Повтор после замены damage -> attack_rate в данных. Боты B2, B5, B7, B8, seed 1-5, осада I, волны без предела: без даров и карточек;
# карточки №1, 2, 3, 7, 17, 25, 27, 31, 33, 36, 37 (как в data/cards.json); дары «Закалённая сталь» и «Меткие стрелки» 1-3;
# «Оружие» (как в data/shop.json) 1-3 покупки даром. Итоги bench/card_ablation_v6.txt, bench/gift_ablation_v10.txt.
GODOT="$1"; DIR="bench/balance/ablation_v10_runs"
T0=$(date +%s)
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <набор> <бот> <аргументы воркера после бота и seed>
	name="$1"; bot="$2"; shift 2
	for seed in 1 2 3 4 5; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed "$@" > "$DIR/${name}_${bot}_s$seed.txt" 2> "$DIR/${name}_${bot}_s${seed}_err.txt" &
	done
}
for bot in B2 B5 B7 B8; do
	one none $bot
	for c in meteor_blades silver_vs_dead serrated_arrows long_shot last_stand desperate_charge long_spears iron_wall shield_cover reserve_fund blood_for_blood; do
		one "card_$c" $bot --cards $c
	done
	for lvl in 1 2 3; do
		one "ts_$lvl" $bot --gifts "tempered_steel:$lvl"
		one "mk_$lvl" $bot --gifts "marksmen:$lvl"
		one "w_$lvl" $bot --weapons-free $lvl
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 420, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/abl6d_aggregate.gd -- v10 $(( $(date +%s) - T0 ))
