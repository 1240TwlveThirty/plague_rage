#!/bin/sh
# Равный бюджет (задача 8, этап D): sh bench/balance/spear_budget_run.sh "<godot.exe>" [метка итерации]   (из корня проекта)
# Бот B7 с армией из пехоты (300) и из копейщиков на ту же цену (200; покупки пехоты — копейщиками), с приказом «держать» и без;
# бот B8 (половина пехотных покупок — копейщики) с «держать» и без. Seed 1-5, без даров и карточек, осада I, волны без предела.
# Файлы bench/balance/spear_budget_runs/, итог bench/spear_budget.txt (bench/balance/spear_budget_aggregate.gd).
GODOT="$1"; TAG="${2:-}"; DIR="bench/balance/spear_budget_runs"
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <набор> <аргументы воркера после бота и seed>
	name="$1"; bot="$2"; shift 2
	for seed in 1 2 3 4 5; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed "$@" > "$DIR/${name}_s$seed.txt" 2> "$DIR/${name}_s${seed}_err.txt" &
	done
}
one inf_hold B7
one inf_free B7 --hold off
one spear_hold B7 --army spear
one spear_free B7 --army spear --hold off
one b8_hold B8
one b8_free B8 --hold off
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 30, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/spear_budget_aggregate.gd -- "$TAG"
