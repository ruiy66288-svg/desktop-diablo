shader_type canvas_item;
render_mode blend_add;

// 《桌面破坏神》杀戮狂热残影着色器 (依据《02_系统架构与数值_v6.md》§6.2 & 《03_美术风格圣经_v1.0.md》§02.5)
// 适配 gl_compatibility，fragment() 内零 return；随叠层 (1..10) 拉长余烬红残影刻线

uniform vec4 frenzy_color : source_color = vec4(1.0, 0.353, 0.122, 1.0); // #FF5A1F 余烬橙红
uniform float frenzy_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float time_phase : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float dist_edge = max(abs(p.x), abs(p.y)) * 2.0;

	// 仅在卡牌外框及两侧拖尾区域生成木刻残影条纹，绝不遮挡中心 40% 躯干
	float border_band = smoothstep(0.68, 0.94, dist_edge) * (1.0 - smoothstep(0.95, 1.0, dist_edge));
	float streak_wave = step(0.45, fract(UV.x * 6.0 - time_phase * (1.5 + frenzy_ratio * 2.5)));
	float side_ghost_l = smoothstep(0.28, 0.04, abs(UV.x - 0.14)) * step(0.18, UV.y) * step(UV.y, 0.84);
	float side_ghost_r = smoothstep(0.28, 0.04, abs(UV.x - 0.86)) * step(0.18, UV.y) * step(UV.y, 0.84);

	float ghost_shape = max(border_band, max(side_ghost_l, side_ghost_r) * streak_wave * 0.75);
	float pulse = 0.75 + 0.25 * sin(time_phase * 8.0 + UV.y * 10.0);
	float alpha = clamp(ghost_shape * frenzy_ratio * pulse * 0.85, 0.0, 1.0);

	COLOR = vec4(frenzy_color.rgb * alpha, alpha);
}
