shader_type canvas_item;
// Брызги крови при смерти в массовом бою (задача 23): один квад на смерть, капли считает шейдер — CPU пишет инстанс один раз
// при смерти, покадрово меняется только uniform now. Квад — cells x cells пикселей мира (масштаб инстанса); клетка — 1 px мира,
// поэтому капли пиксельные. Клетка — капля, если её хэш меньше density (ближе к центру гуще); у капли своя дальность (reach),
// фронт разлёта 1 - (1 - t)^3 — быстро в начале, медленнее к концу; капля видна в полосе band позади фронта, к концу жизни гаснет.
// INSTANCE_CUSTOM: x — время появления (c), y — зерно (0..1), z — жизнь (c). Цвет — цвет инстанса (кровь или пыль).
uniform float now = 0.0;
uniform float cells = 24.0;
uniform float density = 0.22;
uniform float band = 0.22;
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
}

float hash(vec2 p, float s) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + s * 437.585) * 43758.5453);
}

void fragment() {
	float age = now - cd.x;
	float life = max(cd.z, 0.001);
	if (age < 0.0 || age > life) {
		discard;
	}
	float t = age / life;
	vec2 cell = floor(UV * cells);
	float r = length((cell + 0.5) / cells - 0.5) * 2.0;   // 0 в центре, 1 у края квада
	float hv = hash(cell, cd.y);
	float reach = 0.3 + 0.7 * hash(cell + 17.0, cd.y);
	float front = (1.0 - pow(1.0 - t, 3.0)) * reach;
	if (hv > density * (1.6 - r) || r > front || r < front - band) {
		discard;
	}
	COLOR = vec4(COLOR.rgb, COLOR.a * (1.0 - t * t));
}
