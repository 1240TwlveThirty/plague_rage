# Эталон для регрессии: python bench/make_ref.py [коммит, по умолчанию HEAD] (из корня проекта).
#   bench/ref/main_ref.gd — scripts/main.gd указанного коммита (дневник читает из bench/ref/story_ref.json того же коммита); bench/ref/REF.txt — какой это коммит.
# Обновлять ПЕРЕД правкой scripts/main.gd (или указать коммит до правок); bench/regress.gd сравнивает рабочий main с эталоном.
import io
import subprocess
import sys

rev = sys.argv[1] if len(sys.argv) > 1 else 'HEAD'
full = subprocess.run(['git', 'log', '-1', '--format=%h %s', rev], capture_output=True, check=True).stdout.decode('utf-8').strip()
src = subprocess.run(['git', 'show', rev + ':scripts/main.gd'], capture_output=True, check=True).stdout.decode('utf-8')
# дневник того же коммита: эталон читает свой story.json (структура файла могла измениться)
story = subprocess.run(['git', 'show', rev + ':data/story.json'], capture_output=True, check=True).stdout.decode('utf-8')
# старые коммиты: тексты прямо в intro/text; нынешний общий загрузчик (game.gd) ждёт ключи intro_key/text_key —
# для симуляции содержимое не важно, переименовываются только поля
story = story.replace('"intro":', '"intro_key":').replace('"text":', '"text_key":')
io.open('bench/ref/story_ref.json', 'w', encoding='utf-8', newline='').write(story)
STORY = 'const STORY_PATH := "res://data/story.json"'
assert src.count(STORY) == 1
src = src.replace(STORY, 'const STORY_PATH := "res://bench/ref/story_ref.json"')
io.open('bench/ref/main_ref.gd', 'w', encoding='utf-8', newline='').write(src)
io.open('bench/ref/REF.txt', 'w', encoding='utf-8', newline='\n').write(full + '\n')
print('ok', full)
