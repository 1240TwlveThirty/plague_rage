#!/bin/sh
# Абляция v8 (задача 6d, этап A): sh bench/balance/ablation_v8_run.sh "<godot.exe>"   (из корня проекта)
# Боты B2, B5, B7, B8, seed 1-5, осада I, волны без предела: без даров и карточек; «Лазарет» (recover +10/20/30%) 1-3;
# карточка №40 «Полевой госпиталь» (recover +20%). Файлы bench/balance/ablation_v8_runs/, итоги bench/gift_ablation_v8.txt
# и bench/card_ablation_v4.txt (bench/balance/abl6d_aggregate.gd v8).
# Задача 9: копейщики выключены в данных v1 — воркер пропускает B8 и --army spear (строка SKIP, код 2); для повтора старых замеров
# с B8 добавить воркеру --spears on (значения дара «Стена щитов» с задачи 9 другие: блок всем, а не копейщикам).
GODOT="$1"; DIR="bench/balance/ablation_v8_runs"
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
	for lvl in 1 2 3; do
		one "infirmary_$lvl" $bot --gifts "infirmary:$lvl"
	done
	one card_field_kitchen $bot --cards field_kitchen
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 100, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/abl6d_aggregate.gd -- v8 $(( $(date +%s) - T0 ))
