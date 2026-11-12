shader_type canvas_item;
render_mode blend_add;

// 《桌面破坏神》落地即爆冲击环着色器 (依据《03_美术风格圣经_v1.0.md》§02.5 & §03)
// 适配 gl_compatibility，fragment() 内零 return；品质色扩张环 + 5 道楔形刀痕

uniform vec4 slam_color : source_color = vec4(1.0, 0.624, 0.102, 1.0); // 默认暗金 #FF9F1A
uniform float progress : hint_range(0.0, 1.0) = 0.45;
uniform float ring_thickness : hint_range(0.02, 0.16) = 0.065;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);

	float target_r = mix(0.18, 0.92, progress);
	float ring_band = smoothstep(ring_thickness, 0.0, abs(r - target_r));

	// 5 道克制楔形刀痕（03 §02.5: 4-6 道楔形刀痕，绝非密集刺线）
	float sector = abs(sin(ang * 2.5));
	float wedge_mask = step(0.86, sector) * step(0.20, r) * (1.0 - smoothstep(target_r, target_r + 0.12, r));

	float fade = (1.0 - progress) * (1.0 - smoothstep(0.90, 1.0, r));
	float alpha = clamp(max(ring_band, wedge_mask * 0.85) * fade, 0.0, 1.0);
	vec3 col = mix(slam_color.rgb, vec3(1.0), ring_band * 0.45);

	COLOR = vec4(col * alpha, alpha * slam_color.a);
}
