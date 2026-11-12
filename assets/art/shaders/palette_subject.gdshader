shader_type canvas_item;

// 《桌面破坏神》木刻主体四通道着色器 (Art Bible v1.0 §03/§04.3 & Asset Pipeline v1.1 §1.2–§1.3)
// 兼容渲染后端: Godot 4.7+ Compatibility (gl_compatibility / OpenGL 3.3)
// 数据纹理四通道定义 (V-01 非 sRGB 线性字节读取):
//   R 通道: 骨白受光掩码 (0.0 = 墨黑 #0B0A0C, 1.0 = 骨白 #E8DCC0)
//   G 通道: 族群油墨点缀色 / 装备品质点缀色掩码 (面积 <= 6%~15%)
//   B 通道: 镀金财富母题掩码 (#C9A04E / #E9C46A, 面积 <= 12%)
//   A 通道: 主体不透明度

group_uniforms Palette;
uniform vec4 color_ink : source_color = vec4(0.043137, 0.039216, 0.047059, 1.0);         // #0B0A0C 墨黑
uniform vec4 color_bone : source_color = vec4(0.909804, 0.862745, 0.752941, 1.0);        // #E8DCC0 骨白
uniform vec4 color_family : source_color = vec4(0.690196, 0.552941, 0.341176, 1.0);      // #B08D57 默认旧金(运行时按族群/品质替换)
uniform vec4 color_gold : source_color = vec4(0.788235, 0.627451, 0.305882, 1.0);        // #C9A04E 镀金常态
uniform vec4 color_gold_bright : source_color = vec4(0.913725, 0.768627, 0.415686, 1.0); // #E9C46A 镀金亮部

group_uniforms CombatFeedback;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;                                    // 受击闪白 (60ms)
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;                              // 死亡/自动熔炼溶解进度
uniform float dissolve_edge_width : hint_range(0.0, 0.2) = 0.05;                         // 溶解刻刀余烬边缘宽度
uniform vec4 dissolve_edge_color : source_color = vec4(1.0, 0.352941, 0.121569, 1.0);    // #FF5A1F 余烬刻线色
uniform bool use_external_noise = false;                                                 // 默认使用内置程序化木刻刀痕阈值，零外部纹理依赖
uniform sampler2D dissolve_noise : hint_default_white, filter_linear, repeat_enable;

group_uniforms WealthDynamics;
// 净财富压力 Δh_wealth (Sim 输出 log10 血量增量: 负债最低约 -0.3979, 常态 0.0, 囤钱上限 +0.4771)
// > 0: 囤钱养肥，镀金向 #E9C46A 增亮并叠加缓慢流动的刻线微光
// = 0: 常态镀金 #C9A04E
// < 0: 负债侵蚀，仅对 B 通道按木刻刀痕噪声剥落，露出底下骨白 #E8DCC0
uniform float wealth_pressure : hint_range(-1.0, 1.0) = 0.0;

group_uniforms Outline;
uniform bool enable_outline = true;
uniform vec4 outline_color : source_color = vec4(0.909804, 0.862745, 0.752941, 0.4);     // #E8DCC0 骨白 40% 不透明度
uniform float outline_width : hint_range(0.0, 5.0) = 1.5;                                // 显示尺寸下 1.5px 外轮廓光边

float hash21(vec2 p) {
	vec2 q = fract(p * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}

// 内置程序化木刻刀痕阈值场 (沿左上 45° 主光排刀方向，返回值严格在 [0.02, 0.98])
float woodcut_gouge_threshold(vec2 uv) {
	vec2 chiseled = vec2(
		floor((uv.x + uv.y) * 36.0),
		floor((uv.y - uv.x) * 14.0)
	);
	float coarse_block = hash21(floor(uv * 16.0));
	float gouge_strip = hash21(chiseled);
	float fine_nick = hash21(floor(uv * 48.0 + vec2(7.1, 3.7)));
	float combined = coarse_block * 0.45 + gouge_strip * 0.40 + fine_nick * 0.15;
	return mix(0.02, 0.98, clamp(combined, 0.0, 1.0));
}

float sample_threshold(vec2 uv) {
	if (use_external_noise) {
		return mix(0.02, 0.98, clamp(texture(dissolve_noise, uv).r, 0.0, 1.0));
	}
	return woodcut_gouge_threshold(uv);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float r = clamp(tex.r, 0.0, 1.0);
	float g = clamp(tex.g, 0.0, 1.0);
	float b = clamp(tex.b, 0.0, 1.0);
	float a = clamp(tex.a, 0.0, 1.0);

	// 1. 基础墨黑 / 骨白双色版画还原 (R 通道)
	vec3 base_col = mix(color_ink.rgb, color_bone.rgb, r);

	// 2. 族群油墨色 / 品质点缀色叠加 (G 通道)
	base_col = mix(base_col, color_family.rgb, g);

	// 3. 镀金层与净财富压力动态响应 (B 通道)
	vec3 gold_col = color_gold.rgb;
	float effective_b = b;

	if (wealth_pressure > 0.0005) {
		// Δh_wealth > 0 (囤钱): 镀金提亮至 #E9C46A + 缓慢流动的刻线光泽
		float wp = clamp(wealth_pressure / 0.477121, 0.0, 1.0);
		gold_col = mix(color_gold.rgb, color_gold_bright.rgb, wp);
		float etch_phase = fract((UV.x * 14.0 - UV.y * 10.0) - TIME * 0.55);
		float etch_line = smoothstep(0.08, 0.0, abs(etch_phase - 0.5));
		gold_col = mix(gold_col, vec3(1.0, 0.96, 0.84), etch_line * 0.45 * wp);
	} else if (wealth_pressure < -0.0005) {
		// Δh_wealth < 0 (负债): 镀金按刀痕噪声逐步剥落，露出底下骨白
		float debt_ratio = clamp(-wealth_pressure / 0.397940, 0.0, 1.0);
		float flake_val = sample_threshold(UV * 1.35 + vec2(0.31, 0.67));
		float peeled = step(flake_val, debt_ratio * 0.88);
		effective_b = b * (1.0 - peeled);
		base_col = mix(base_col, color_bone.rgb, b * peeled);
	}

	vec3 subject_col = mix(base_col, gold_col, effective_b);

	// 4. 受击闪白
	subject_col = mix(subject_col, vec3(1.0), clamp(hit_flash, 0.0, 1.0));

	// 5. 死亡 / 自动熔炼溶解 (从下往上偏置 + 木刻刀痕阈值 + 刻刀余烬边)
	float sprite_alpha = a;
	if (dissolve_amount > 0.0001) {
		if (dissolve_amount >= 0.9999) {
			sprite_alpha = 0.0;
		} else {
			float vertical_bias = (1.0 - UV.y) * 0.12;
			float d_val = clamp(sample_threshold(UV) * 0.88 + vertical_bias, 0.01, 0.99);
			if (d_val < dissolve_amount) {
				sprite_alpha = 0.0;
			} else if (d_val < dissolve_amount + dissolve_edge_width) {
				float edge_t = 1.0 - (d_val - dissolve_amount) / max(dissolve_edge_width, 0.0001);
				subject_col = mix(subject_col, dissolve_edge_color.rgb, clamp(edge_t, 0.0, 1.0));
			}
		}
	}

	// 6. 外轮廓光边 (Silhouette Rim: 采样 8 邻域 alpha，骨白 40% 不透明度)
	vec3 out_rgb = subject_col;
	float out_alpha = sprite_alpha;

	if (enable_outline && outline_width > 0.01 && dissolve_amount < 0.98) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		vec2 diag = px * 0.707107;
		float max_nb = 0.0;
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(-diag.x, -diag.y)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(diag.x, -diag.y)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(-diag.x, diag.y)).a);
		max_nb = max(max_nb, texture(TEXTURE, UV + vec2(diag.x, diag.y)).a);

		float rim_fade = 1.0 - smoothstep(0.55, 0.98, dissolve_amount);
		float rim_mask = smoothstep(0.15, 0.65, max_nb) * (1.0 - sprite_alpha);
		float rim_alpha = outline_color.a * rim_mask * rim_fade;

		// Alpha over 合成: 主体覆盖在外轮廓光边之上，消除抗锯齿黑缝
		out_alpha = sprite_alpha + rim_alpha * (1.0 - sprite_alpha);
		if (out_alpha > 0.0001) {
			out_rgb = (subject_col * sprite_alpha + outline_color.rgb * rim_alpha * (1.0 - sprite_alpha)) / out_alpha;
		}
	}

	COLOR = vec4(out_rgb, out_alpha);
}
