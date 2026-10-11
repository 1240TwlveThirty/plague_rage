# Конвертация story.json из прежней структуры (entries [{wave, text}]) в новую (entries [{id, siege, wave, text}], victories).
#   python bench/convert_story.py [источник] [результат]   (из корня проекта)
# Источник по умолчанию — data/story.json последнего коммита, где он ещё в прежней структуре (5b9a93b); результат — data/story.json.
# Тексты переносятся дословно. Запись на прежней волне, которой нет в таблице, — ошибка.
import io
import json
import subprocess
import sys

OLD_COMMIT = '5b9a93b'
# прежняя волна -> (осада, волна)
WAVE_MAP = {1: (1, 1), 2: (1, 2), 3: (1, 3), 5: (1, 5), 6: (1, 6), 8: (1, 8), 10: (1, 10),
            13: (2, 3), 15: (2, 5), 18: (2, 7), 20: (2, 10),
            22: (3, 3), 25: (3, 6), 30: (3, 10)}
END_WAVES = [0, 4, 7, 10]   # пороги четырёх концовок по порядку прежних min_wave
VICTORIES = [
    'День десятый. Последний из них упал у ворот, и боль короля стихла. Я записал это, как записываю всё. Это не конец: Благодать умеет возвращаться.',
    'Снова десять дней, и снова ворота стоят. Свет над лесом стал ярче. Он красивый. Я перестал отводить глаза.',
    'Ворота стоят, но я больше не держу их. Благодать вошла не как захватчик, а как та, кого я ждал. Мира спит рядом. Я принимаю.',
]

if len(sys.argv) > 1:
    old = json.loads(io.open(sys.argv[1], encoding='utf-8').read())
else:
    old = json.loads(subprocess.run(['git', 'show', OLD_COMMIT + ':data/story.json'], capture_output=True, check=True).stdout.decode('utf-8'))
out_path = sys.argv[2] if len(sys.argv) > 2 else 'data/story.json'

entries = []
for e in old['entries']:
    siege, wave = WAVE_MAP[int(e['wave'])]
    entries.append({'id': 's%dw%d' % (siege, wave), 'siege': siege, 'wave': wave, 'text': e['text']})
entries.sort(key=lambda e: (e['siege'], e['wave']))
ends = sorted(old['endings'], key=lambda e: e['min_wave'])
assert len(ends) == len(END_WAVES), 'ожидается %d концовок, в источнике %d' % (len(END_WAVES), len(ends))


def q(s):
    return json.dumps(s, ensure_ascii=False)


lines = ['{', '\t"intro": %s,' % q(old['intro']), '\t"entries": [']
lines += ['\t\t{"id": %s, "siege": %d, "wave": %d, "text": %s}%s' % (q(e['id']), e['siege'], e['wave'], q(e['text']), ',' if k < len(entries) - 1 else '')
          for k, e in enumerate(entries)]
lines += ['\t],', '\t"endings": [']
lines += ['\t\t{"min_wave": %d, "text": %s}%s' % (END_WAVES[k], q(e['text']), ',' if k < len(ends) - 1 else '') for k, e in enumerate(ends)]
lines += ['\t],', '\t"victories": [']
lines += ['\t\t{"siege": %d, "text": %s}%s' % (k + 1, q(t), ',' if k < len(VICTORIES) - 1 else '') for k, t in enumerate(VICTORIES)]
lines += ['\t]', '}']
io.open(out_path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('ok: записей %d, концовок %d, побед %d -> %s' % (len(entries), len(ends), len(VICTORIES), out_path))
