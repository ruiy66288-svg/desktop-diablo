shader_type canvas_item;

// 自动熔炼溶解 (03 号文件 §02.5): 图标由下往上溶解成余烬细线, 400ms
// dissolve: 0 (完整图标) -> 1 (全部化为余烬并消散); 纯程序化

uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ember_color : source_color = vec4(0.784, 0.341, 0.122, 1.0);
uniform vec4 ember_core : source_color = vec4(1.0, 0.957, 0.839, 1.0);
uniform float streaks : hint_range(8.0, 64.0) = 28.0;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float col_id = floor(UV.x * streaks);
	float jitter = hash11(col_id) * 0.28;
	float h_bottom = 1.0 - UV.y;
	float front = dissolve * 1.45 - 0.12;
	float local = h_bottom - jitter;
	float band = 0.16;

	// 前沿上方: 原图; 前沿带: 余烬刻线; 前沿下方: 已飞散
	float above = step(front + band, local);
	float in_band = step(front, local) * (1.0 - above);
	float streak_mask = step(0.35, fract(UV.x * streaks));
	float tail = clamp(1.0 - (front - local) * 3.2, 0.0, 1.0);
	float below = (1.0 - step(front, local)) * tail * streak_mask * 0.55;

	vec3 ember = mix(ember_color.rgb, ember_core.rgb, clamp(1.0 - (local - front) / band, 0.0, 1.0));
	vec3 rgb = tex.rgb * above + ember * (in_band + below);
	float a = tex.a * above + tex.a * in_band * streak_mask + below * 0.7 * step(0.02, tex.a + 0.0);
	COLOR = vec4(rgb, clamp(a, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, dissolve)));
}
