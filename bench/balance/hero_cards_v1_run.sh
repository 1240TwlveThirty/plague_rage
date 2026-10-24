#!/bin/sh
# Абляция карточек героя v1 (задача 14, этап C): sh bench/balance/hero_cards_v1_run.sh "<godot.exe>"   (из корня проекта)
# Бот B9 (B7 + герой, держит J и ведёт героя к скоплению зомби), seed 1-10, осада I, волны без предела, без даров: без карточек;
# карточки №41 «Широкий замах», №42 «Быстрые руки», №43 «Закалка командира» по одной с начала забега (--cards).
# №44 и №45 не замеряются: бот к ним слеп (герой гибнет с контакта и почти не бывает ниже 40% живым долго; B9 уводит героя от армии).
# Данные героя — рабочий data/hero.json. Файлы bench/balance/hero_cards_v1_runs/, итог bench/hero_card_ablation_v1.txt.
GODOT="$1"; DIR="bench/balance/hero_cards_v1_runs"
T0=$(date +%s)
mkdir -p "$DIR"; rm -f "$DIR"/*.txt
one() {   # <набор> <аргументы воркера после бота и seed>
	name="$1"; shift
	for seed in 1 2 3 4 5 6 7 8 9 10; do
		while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
		"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- B9 $seed "$@" > "$DIR/${name}_B9_s$seed.txt" 2> "$DIR/${name}_B9_s${seed}_err.txt" &
	done
}
one none
for c in wide_swing quick_hands commander_temper; do
	one "card_$c" --cards $c
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l) из 40, с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
"$GODOT" --headless --path . -s res://bench/balance/hero_cards_aggregate.gd -- $(( $(date +%s) - T0 ))
