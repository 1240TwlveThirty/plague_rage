# Копии для тестов v39 (этап 1: пауза, деление, стрелки): python bench/make_v39.py (из корня проекта).
#   main_v39_before.gd, main_v39_before_3000.gd — scripts/main.gd коммита 5a26a30 (до правок) и он же с UNIT_COUNT = 3000
#   main_v39_nopause.gd — рабочий main с PAUSE_ENABLED = false;  main_v39_3000.gd — рабочий main, UNIT_COUNT = 3000
import io
import re
import subprocess

src = io.open('scripts/main.gd', encoding='utf-8', newline='').read()
old = subprocess.run(['git', 'show', '5a26a30:scripts/main.gd'], capture_output=True, check=True).stdout.decode('utf-8')
# прежний main читает дневник прежней структуры: ему — копия прежнего story.json
STORY = 'const STORY_PATH := "res://data/story.json"'
assert old.count(STORY) == 1
old = old.replace(STORY, 'const STORY_PATH := "res://bench/fixtures_story/story_old.json"')


# Лечение между волнами с задачи 6b (heal_base в data/waves.json вместо полного): копия до правок лечит так же, как рабочий main,
# иначе сравнение «до и после» расходится на первом переходе между волнами (сравнивается пауза / мышь, а не лечение).
HEAL_OLD = "			hp[i] = type_hp[unit_type[i]]   # бесплатное лечение армии"
HEAL_NEW = ("			hp[i] = type_hp[unit_type[i]] if wave_cfg.heal_base >= 1.0 else hp[i] + (type_hp[unit_type[i]] - hp[i]) * wave_cfg.heal_base"
            "   # лечение между волнами, как в рабочем main (6b)")


def heal(s):
    assert s.count(HEAL_OLD) == 1
    return s.replace(HEAL_OLD, HEAL_NEW)

def big(s):
    s, n = re.subn(r'^const UNIT_COUNT := 700 ', 'const UNIT_COUNT := 3000 ', s, flags=re.M)
    assert n == 1
    return s


def put(name, s):
    io.open('bench/%s.gd' % name, 'w', encoding='utf-8', newline='').write(s)


put('main_v39_before', heal(old))
put('main_v39_before_3000', big(heal(old)))
put('main_v39_3000', big(src))
s, n = re.subn(r'^const PAUSE_ENABLED := true', 'const PAUSE_ENABLED := false', src, flags=re.M)
assert n == 1
put('main_v39_nopause', s)
print('ok')
