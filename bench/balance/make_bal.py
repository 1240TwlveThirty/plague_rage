# Копии scripts/main.gd для ботов баланса: python bench/balance/make_bal.py (из корня проекта).
#   main_bal.gd (sweep_worker.gd) и main_bal_curves.gd (curves_worker.gd): текущий main, пути к JSON — переменные,
#   рекорд пишется в user://record_bench.json. Перегенерировать после каждой правки scripts/main.gd.
import io
import re
import subprocess

src = io.open('scripts/main.gd', encoding='utf-8', newline='').read()
rev = subprocess.run(['git', 'log', '-1', '--format=%h', '--', 'scripts/main.gd'], capture_output=True, check=True).stdout.decode().strip()
for name in ['WAVES_PATH', 'SHOP_PATH', 'UNIT_TYPES_PATH', 'CASTLE_PATH']:
    src, n = re.subn(r'^const %s := ' % name, 'var %s := ' % name, src, flags=re.M)
    assert n == 1, name
src, n = re.subn(r'^const RECORD_PATH := "user://record.json"', 'const RECORD_PATH := "user://record_bench.json"', src, flags=re.M)
assert n == 1
for out, what in [('main_bal', 'свипа баланса'), ('main_bal_curves', 'замера кривых роста')]:
    head = '# БЕНЧ-копия scripts/main.gd (коммит %s) для %s: пути к JSON — переменные. Собирается bench/balance/make_bal.py.\n' % (rev, what)
    io.open('bench/balance/%s.gd' % out, 'w', encoding='utf-8', newline='').write(head + src)
print('ok', rev)
