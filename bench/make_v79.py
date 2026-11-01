# Копии main для замера FPS задачи 29 (стрелы): python bench/make_v79.py [коммит «до»] (из корня проекта, по умолчанию 271529f).
#   bench/main_v79_<до|после>_<N>.gd — main коммита «до» и рабочий scripts/main.gd с UNIT_COUNT = N, MAX_UNITS = max(4000, N),
#   ARCHER_COUNT = N / 5 (лучников больше — больше стрел в полёте). Копии не в git (.gitignore).
import io
import re
import subprocess
import sys

before = sys.argv[1] if len(sys.argv) > 1 else '271529f'
src = {
    'after': io.open('scripts/main.gd', encoding='utf-8', newline='').read(),
    'before': subprocess.run(['git', 'show', before + ':scripts/main.gd'], capture_output=True, check=True).stdout.decode('utf-8'),
}


def sized(s, n):
    for name, val in (('UNIT_COUNT', n), ('MAX_UNITS', max(4000, n)), ('ARCHER_COUNT', n // 5)):
        s, k = re.subn(r'^const %s := \d+ ' % name, 'const %s := %d ' % (name, val), s, flags=re.M)
        assert k == 1, name
    return s


for tag, s in src.items():
    for n in (1000, 3000, 5000):
        io.open('bench/main_v79_%s_%d.gd' % (tag, n), 'w', encoding='utf-8', newline='').write(sized(s, n))
print('ok')
