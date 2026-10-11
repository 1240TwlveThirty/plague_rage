# Копии для тестов v40 (этап 2: выбор мышью, ПКМ-приказы): python bench/make_v40.py (из корня проекта).
#   main_v40_before.gd — scripts/main.gd коммита этапа 1 (c58f9c1), до правок этапа 2
import io
import subprocess

old = subprocess.run(['git', 'show', 'c58f9c1:scripts/main.gd'], capture_output=True, check=True).stdout.decode('utf-8')
# прежний main читает дневник прежней структуры: ему — копия прежнего story.json
STORY = 'const STORY_PATH := "res://data/story.json"'
assert old.count(STORY) == 1
old = old.replace(STORY, 'const STORY_PATH := "res://bench/fixtures_story/story_old.json"')
io.open('bench/main_v40_before.gd', 'w', encoding='utf-8', newline='').write(old)
print('ok')
