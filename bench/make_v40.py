# Копии для тестов v40 (этап 2: выбор мышью, ПКМ-приказы): python bench/make_v40.py (из корня проекта).
#   main_v40_before.gd — scripts/main.gd коммита этапа 1 (c58f9c1), до правок этапа 2
import io
import subprocess

old = subprocess.run(['git', 'show', 'c58f9c1:scripts/main.gd'], capture_output=True, check=True).stdout.decode('utf-8')
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

io.open('bench/main_v40_before.gd', 'w', encoding='utf-8', newline='').write(heal(old))
print('ok')
