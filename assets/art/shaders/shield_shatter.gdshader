shader_type canvas_item;

// 护盾破碎 (03 号文件 §02.5): Voronoi 碎片沿法线飞散, 钢蓝玻璃 #A8C8E8 + 骨白边 #E8DCC0, 350ms
// progress: 0 (完整护盾) -> 1 (碎片飞散消失); 纯程序化, 零贴图

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shard_color : source_color = vec4(0.659, 0.784, 0.910, 1.0);
uniform vec4 edge_color : source_color = vec4(0.910, 0.863, 0.753, 1.0);
uniform float cells : hint_range(3.0, 12.0) = 6.0;
uniform float drift : hint_range(0.0, 0.8) = 0.34;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 返回 vec4(cell_id.xy, edge_dist, 0)
vec4 voronoi(vec2 g) {
	vec2 ig = floor(g);
	float best = 8.0;
	float second = 8.0;
	vec2 best_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = ig + vec2(float(x), float(y));
			vec2 pt = id + hash22(id);
			vec2 d = pt - g;
			float dd = dot(d, d);
			if (dd < best) {
				second = best;
				best = dd;
				best_id = id;
			} else if (dd < second) {
				second = dd;
			}
		}
	}
	return vec4(best_id, sqrt(second) - sqrt(best), 0.0);
}

void fragment() {
	vec2 g = UV * cells;
	vec4 v0 = voronoi(g);
	vec2 center = (v0.xy + hash22(v0.xy)) / cells - vec2(0.5);
	vec2 dir = normalize(center + vec2(0.0001));
	float ease_p = progress * progress * (3.0 - 2.0 * progress);

	// 被位移后的像素是否仍属于同一块碎片
	vec2 uv2 = UV - dir * ease_p * drift;
	vec4 v1 = voronoi(uv2 * cells);
	float same = (abs(v1.x - v0.x) + abs(v1.y - v0.y)) < 0.5 ? 1.0 : 0.0;

	// 护盾穹顶轮廓: 椭圆软边
	vec2 q = (UV - vec2(0.5)) * vec2(1.0, 1.15);
	float dome = 1.0 - smoothstep(0.40, 0.50, length(q));

	float edge_line = 1.0 - smoothstep(0.02, 0.07, v0.z);
	vec3 col = mix(shard_color.rgb, edge_color.rgb, edge_line * 0.9);

	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	float base_a = 0.34 + 0.36 * edge_line;
	float flash = (1.0 - smoothstep(0.0, 0.14, progress)) * 0.35;
	float a = dome * mix(1.0, same, step(0.001, progress)) * (base_a + flash) * fade;
	COLOR = vec4(col + vec3(flash), a);
}
