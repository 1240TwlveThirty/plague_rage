# Копии scripts/main.gd для тестов v36: python bench/make_v36.py (из корня проекта).
#   main_v36_rel1.gd   — SCALE_REL = SPEED_REL = 1.0, RENDER_JITTER = 0, старт и spawn_columns как в 155d844 (регрессия)
#   main_v36_A.gd      — SCALE_REL 1.5, SPEED_REL 1.5;  main_v36_B.gd — 1.5 и 1.0
#   main_v36_nojit.gd  — как scripts/main.gd, но RENDER_JITTER = 0
#   main_v36_3000.gd   — как scripts/main.gd, UNIT_COUNT = 3000
import io
import re

src = io.open('scripts/main.gd', encoding='utf-8', newline='').read()


def variant(name, scale=None, speed=None, jitter=None, units=None, old_start=False):
    s = src
    if scale is not None:
        s, n = re.subn(r'^const SCALE_REL := [\d.]+', 'const SCALE_REL := %s' % scale, s, flags=re.M)
        assert n == 1
    if speed is not None:
        s, n = re.subn(r'^const SPEED_REL := [\d.]+', 'const SPEED_REL := %s' % speed, s, flags=re.M)
        assert n == 1
    if jitter is not None:
        s, n = re.subn(r'^const RENDER_JITTER := [\d.]+', 'const RENDER_JITTER := %s' % jitter, s, flags=re.M)
        assert n == 1
    if units is not None:
        s, n = re.subn(r'^const UNIT_COUNT := 700 ', 'const UNIT_COUNT := %d ' % units, s, flags=re.M)
        assert n == 1
    if old_start:
        s, n = re.subn(r'^const PLAYER_START := Vector2\(1010, .*\n\t.*\n', 'const PLAYER_START := Vector2(1010, 605)\n', s, flags=re.M)
        assert n == 1
        assert s.count('"res://data/waves.json"') == 1
        s = s.replace('"res://data/waves.json"', '"res://bench/v36_before/waves.json"')
    io.open('bench/%s.gd' % name, 'w', encoding='utf-8', newline='').write(s)


variant('main_v36_rel1', '1.0', '1.0', '0.0', old_start=True)
variant('main_v36_A', '1.5', '1.5')
variant('main_v36_B', '1.5', '1.0')
variant('main_v36_nojit', jitter='0.0')
variant('main_v36_3000', units=3000)
print('ok')
