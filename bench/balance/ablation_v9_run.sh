#!/bin/sh
# Абляция v9 (задача 6d, этап C): sh bench/balance/ablation_v9_run.sh "<godot.exe>"   (из корня проекта)
# Боты B2, B5, B7, B8, seed 1-5, осада I, волны без предела. Оригинал и вариант «attack_rate вместо damage» (те же проценты и цели):
# карточки №1, 2, 3, 17, 25, 27, 36, 37 (бонус) и №7, 31, 33 (издержка); дары «Закалённая сталь» и «Меткие стрелки» 1-3
# (оригинал — дар, вариант — карточка-двойник из bench/card_variants.json); «Оружие +10%»: 1, 2, 3 покупки даром, damage против attack_rate,
# и «Оружие» на скорости без даровых покупок (меняются только покупки B2). Итоги bench/card_ablation_v5.txt, bench/gift_ablation_v9.txt.
GODOT="$1"; DIR="bench/balance/ablation_v9_runs"; V="res://bench/card_variants.json"
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
	for c in meteor_blades silver_vs_dead serrated_arrows last_stand desperate_charge long_spears reserve_fund blood_for_blood long_shot iron_wall shield_cover; do
		one "card_$c" $bot --cards $c
		one "card_${c}_ar" $bot --variants $V --cards "v_${c}_ar"
	done
	for lvl in 1 2 3; do
		one "ts_$lvl" $bot --gifts "tempered_steel:$lvl"
		one "ts_rate_$lvl" $bot --variants $V --cards "v_ts_rate_$lvl"
		one "mk_$lvl" $bot --gifts "marksmen:$lvl"
		one "mk_rate_$lvl" $bot --variants $V --cards "v_marksmen_rate_$lvl"
		one "w_dmg_$lvl" $bot --weapon-stat damage --weapons-free $lvl
		one "w_rate_$lvl" $bot --weapon-stat attack_rate --weapons-free $lvl
	done
	one w_rate_0 $bot --weapon-stat attack_rate
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 840, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/abl6d_aggregate.gd -- v9 $(( $(date +%s) - T0 ))
