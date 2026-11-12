shader_type canvas_item;
render_mode blend_add;

// 《桌面破坏神》品质光柱着色器 (依据《03_美术风格圣经_v1.0.md》§02.5–§02.6 & §03)
// 纯加法混合，适配 gl_compatibility；底部 4–6 道克制楔形刻线 + 核心白热渐变

uniform vec4 beam_color : source_color = vec4(1.0, 0.624, 0.102, 1.0); // 默认暗金 #FF9F1A
uniform float intensity : hint_range(0.2, 3.0) = 1.25;
uniform float width_falloff : hint_range(1.0, 8.0) = 3.8;
uniform float speed : hint_range(0.1, 5.0) = 1.6;
uniform float life_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float dist_x = abs(UV.x - 0.5) * 2.0;
	float horiz_shape = pow(max(0.0, 1.0 - dist_x), width_falloff);

	// 底部 UV.y=1.0 最亮，顶部 UV.y=0.0 渐隐
	float vert_fade = pow(clamp(UV.y, 0.0, 1.0), 1.6);

	// 5 道垂直刻线纹（克制数量，绝非密集放射刺线）
	float etched_ribs = 0.85 + 0.15 * sin(UV.x * 31.4159 + UV.y * 12.0 - TIME * speed * 4.5);
	float core_white = pow(max(0.0, 1.0 - dist_x * 2.6), 6.0) * vert_fade * 0.65;

	float alpha = horiz_shape * vert_fade * etched_ribs * intensity * life_alpha;
	vec3 final_col = beam_color.rgb * alpha + vec3(core_white * life_alpha);
	COLOR = vec4(final_col, clamp(alpha * beam_color.a, 0.0, 1.0));
}
