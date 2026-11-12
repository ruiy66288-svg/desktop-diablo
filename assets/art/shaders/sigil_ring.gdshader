shader_type canvas_item;
render_mode blend_add;

// 《桌面破坏神》地面符印环着色器 (依据《03_美术风格圣经_v1.0.md》§02.5 & §03)
// 暗金/太古掉落或暴击时使用的荧光刻线同心环，适配 gl_compatibility，零柔光团

uniform vec4 ring_color : source_color = vec4(1.0, 0.624, 0.102, 1.0); // 默认暗金 #FF9F1A
uniform float spin_speed : hint_range(-4.0, 4.0) = 1.1;
uniform float life_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float ring_thickness : hint_range(0.01, 0.12) = 0.045;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	// 透视压扁为地面椭圆
	vec2 ell = vec2(centered.x, centered.y * 1.45);
	float r = length(ell);
	float ang = atan(ell.y, ell.x) + TIME * spin_speed;

	float outer_ring = smoothstep(ring_thickness, 0.0, abs(r - 0.82));
	float inner_ring = smoothstep(ring_thickness * 0.8, 0.0, abs(r - 0.54));

	// 6 道克制楔形刻痕分割符印环
	float tick_mask = step(0.18, abs(sin(ang * 3.0)));
	float combined = max(outer_ring, inner_ring * tick_mask * 0.85);
	float bounds = 1.0 - smoothstep(0.92, 1.0, r);

	float alpha = combined * bounds * life_alpha;
	vec3 col = mix(ring_color.rgb, vec3(1.0), outer_ring * 0.35);
	COLOR = vec4(col * alpha, clamp(alpha * ring_color.a, 0.0, 1.0));
}
