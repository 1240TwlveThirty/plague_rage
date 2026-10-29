// Карточка экрана выбора (задача 25): шейдер CanvasGroup — содержимое карточки (рамка, иконка, текст) уже отрисовано группой
// в буфер, шейдер берёт его по SCREEN_UV. Поддельная перспектива: луч из глаза (perspective_px перед экраном) через пиксель
// экрана пересекает плоскость карточки, повёрнутую на tilt; точка на плоскости — пиксель карточки (ближайший сосед).
// Вне карточки — подсветка-рамка glow_px. Блик — пятно за курсором, растворение — по шуму клеток burn_cells.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 card_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);   // карточка без наклона в SCREEN_UV: xy — угол, zw — размер
uniform vec2 card_px = vec2(320.0, 480.0);              // размер карточки на экране, px
uniform vec2 tilt = vec2(0.0);                          // рад: x — вокруг горизонтальной оси, y — вокруг вертикальной
uniform float perspective_px = 1400.0;
uniform float hover = 0.0;                              // 0..1: подсветка-рамка
uniform vec4 glow_color : source_color = vec4(0.996, 0.682, 0.204, 1.0);
uniform float glow_px = 6.0;
uniform vec2 shine_pos = vec2(0.5);                     // блик: доли карточки
uniform float shine_alpha = 0.0;
uniform float shine_radius = 0.45;                      // доля ширины карточки
uniform float dim = 1.0;                                // множитель яркости (остальные карточки при наведении)
uniform float burn = 0.0;                               // 0..1: растворение
uniform float burn_edge = 0.12;
uniform vec4 edge_a : source_color = vec4(0.996, 0.906, 0.380, 1.0);
uniform vec4 edge_b : source_color = vec4(0.969, 0.463, 0.133, 1.0);
uniform vec2 burn_cells = vec2(32.0, 48.0);
uniform float burn_seed = 0.0;
uniform float alpha = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p + burn_seed, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = ((SCREEN_UV - card_uv_rect.xy) / card_uv_rect.zw - 0.5) * card_px;   // px от центра карточки, плоскость экрана
	float cx = cos(tilt.x);
	float sx = sin(tilt.x);
	float cy = cos(tilt.y);
	float sy = sin(tilt.y);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 r = ry * rx;
	vec3 n = r * vec3(0.0, 0.0, 1.0);
	vec3 eye = vec3(0.0, 0.0, -perspective_px);
	vec3 d = vec3(p, 0.0) - eye;
	float t = -dot(n, eye) / dot(n, d);
	vec2 q = (transpose(r) * (eye + t * d)).xy;
	vec2 uv = q / card_px + 0.5;
	vec4 c = vec4(0.0);
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		c = textureLod(screen_texture, card_uv_rect.xy + uv * card_uv_rect.zw, 0.0);
		if (c.a > 0.0001) {
			c.rgb /= c.a;
		}
		c.rgb *= dim;
		float aspect = card_px.y / card_px.x;
		float s = 1.0 - smoothstep(0.0, shine_radius, distance(uv * vec2(1.0, aspect), shine_pos * vec2(1.0, aspect)));
		c.rgb = min(c.rgb + vec3(shine_alpha * s), vec3(1.0));
		if (burn > 0.0) {
			float nz = hash(floor(uv * burn_cells));
			float th = burn * (1.0 + burn_edge);
			if (nz < th - burn_edge) {
				c.a = 0.0;
			} else if (nz < th && c.a > 0.0) {
				c = vec4(mix(edge_a.rgb, edge_b.rgb, (th - nz) / burn_edge), 1.0);
			}
		}
	} else if (hover > 0.0 && burn <= 0.0) {
		vec2 out_px = max(max(-uv, uv - 1.0), vec2(0.0)) * card_px;
		if (max(out_px.x, out_px.y) <= glow_px) {
			c = vec4(glow_color.rgb, glow_color.a * hover);
		}
	}
	COLOR = vec4(c.rgb, c.a * alpha);
}
