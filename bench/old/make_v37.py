# Копии для тестов v37: python bench/make_v37.py (из корня проекта).
#   bench/v37_bad/unit_types_{missing,format,nofield}.json — лист лучника: нет файла / не тот формат / нет поля sprite
#   bench/main_v37_bad_{...}.gd — scripts/main.gd с UNIT_TYPES_PATH на эти JSON;  bench/main_v37_3000.gd — UNIT_COUNT = 3000
import io
import os
import re

src = io.open('scripts/main.gd', encoding='utf-8', newline='').read()
js = io.open('data/unit_types.json', encoding='utf-8', newline='').read()
os.makedirs('bench/v37_bad', exist_ok=True)
variants = {
    'missing': js.replace('"sprite": "res://art/bowman.png"', '"sprite": "res://art/no_such_file.png"'),
    'format': js.replace('"sprite": "res://art/bowman.png"', '"sprite": "res://icon.svg"'),
    'nofield': js.replace(', "sprite": "res://art/bowman.png"', ''),
}
for name, text in variants.items():
    assert text != js
    io.open('bench/v37_bad/unit_types_%s.json' % name, 'w', encoding='utf-8', newline='').write(text)
    assert src.count('"res://data/unit_types.json"') == 1
    io.open('bench/main_v37_bad_%s.gd' % name, 'w', encoding='utf-8', newline='').write(
        src.replace('"res://data/unit_types.json"', '"res://bench/v37_bad/unit_types_%s.json"' % name))
s, n = re.subn(r'^const UNIT_COUNT := 700 ', 'const UNIT_COUNT := 3000 ', src, flags=re.M)
assert n == 1
io.open('bench/main_v37_3000.gd', 'w', encoding='utf-8', newline='').write(s)
print('ok')
