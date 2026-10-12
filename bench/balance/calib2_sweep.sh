#!/bin/sh
# Калибровка осады I, этап 2: свип множителя численности. sh bench/balance/calib2_sweep.sh "<godot.exe>" <папка в bench/balance> <множители через пробел>
# В каждой точке 30 забегов (B1-B6 x seed 1-5), до 10 процессов сразу. Файлы: <папка>/m<множитель>_<бот>_s<seed>.txt.
GODOT="$1"; DIR="bench/balance/$2"; shift 2
mkdir -p "$DIR"
for m in "$@"; do
	for bot in B1 B2 B3 B4 B5 B6; do
		for seed in 1 2 3 4 5; do
			while [ "$(jobs -r | wc -l)" -ge 10 ]; do sleep 0.3; done
			"$GODOT" --headless --path . -s res://bench/balance/calib_worker.gd -- $bot $seed $m > "$DIR/m${m}_${bot}_s$seed.txt" 2> "$DIR/m${m}_${bot}_s${seed}_err.txt" &
		done
	done
done
wait
echo "завершено: $(grep -l '^RUN,' "$DIR"/*.txt | wc -l), с ошибками: $(find "$DIR" -name '*_err.txt' -size +0 | wc -l)"
