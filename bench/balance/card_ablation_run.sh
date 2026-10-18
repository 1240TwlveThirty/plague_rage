#!/bin/sh
# Абляция карточек (задача 6, этап E): sh bench/balance/card_ablation_run.sh "<godot.exe>"   (из корня проекта; ~1300 забегов, около часа)
# Боты B2 и B5, осада I (слой 1), волны без предела, без даров (кроме набора pick_gifts1). Файлы — bench/balance/card_ablation_v1_runs/, итог —
# bench/card_ablation_v1.txt (bench/balance/card_ablation_aggregate.gd).
#   none — без карточек; <id> — одна карточка с начала забега (38 активных), seed 1-5;
#   pair_<a>__<b> — пара карточек (5 пар задания), seed 1-5;
#   var_<id> — варианты из bench/card_variants.json (скорость удара вместо урона; дар «Закалённая сталь» 1-3 как карточка и его вариант), seed 1-5;
#   pick_none / pick_gifts1 — настоящий выбор (--pick random: случайная карточка из тройки после волн 2, 5, 8), seed 1-200,
#   без даров и с набором «все видимые дары, уровень 1».
GODOT="$1"; DIR="bench/balance/card_ablation_v1_runs"
T0=$(date +%s)
CARDS="meteor_blades silver_vs_dead serrated_arrows infantry_temper heavy_shields light_infantry long_shot quick_reload steadfast mobile_reserve sentries stone_parapets strong_gates quick_repair last_stand blood_harvest marauders purse armorer_discount recruitment trophy_share vow_of_vengeance desperate_charge hunger_ration long_spears bet_on_brave heavy_baggage victory_sacrifice iron_wall first_volley shield_cover arrow_rain rich_vein reserve_fund blood_for_blood dark_vow grace_blessing field_kitchen"
GIFTS1="tempered_steel:1,sturdy_shields:1,marksmen:1,spoils:1,mine:1,reserve:1,armory:1,smith_thomas:1,repairers:1,watch:1,discipline:1,radiance_reserve:1,infirmary:1"
PAIRS="serrated_arrows,long_shot infantry_temper,steadfast marauders,armorer_discount last_stand,desperate_charge first_volley,quick_reload"
VARS="v_meteor_blades_as v_silver_vs_dead_as v_long_spears_as v_tempered_steel_1 v_tempered_steel_2 v_tempered_steel_3 v_tempered_steel_as_1 v_tempered_steel_as_2 v_tempered_steel_as_3"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <имя файла> <аргументы воркера...>
	while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
	name="$1"; shift
	"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- "$@" > "$DIR/$name.txt" 2> "$DIR/${name}_err.txt" &
}
for bot in B2 B5; do
	for seed in 1 2 3 4 5; do
		one "none_${bot}_s$seed" $bot $seed
		for c in $CARDS; do
			one "${c}_${bot}_s$seed" $bot $seed --cards $c
		done
		for p in $PAIRS; do
			one "pair_$(echo $p | sed 's/,/__/')_${bot}_s$seed" $bot $seed --cards $p
		done
		for v in $VARS; do
			one "var_${v}_${bot}_s$seed" $bot $seed --variants res://bench/card_variants.json --cards $v
		done
	done
	for seed in $(seq 1 200); do
		one "pick_none_${bot}_s$seed" $bot $seed --pick random
		one "pick_gifts1_${bot}_s$seed" $bot $seed --pick random --gifts "$GIFTS1"
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из $(ls "$DIR"/*.txt | grep -v _err | wc -l), с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/card_ablation_aggregate.gd -- $(( $(date +%s) - T0 ))
