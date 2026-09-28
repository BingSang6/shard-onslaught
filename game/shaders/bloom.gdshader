// 全屏 Bloom 泛光：亮部采样模糊后叠加回画面（gl_compatibility 可用，零外部资源）
// 挂在全屏 ColorRect 上（CanvasLayer 层级在 世界之上、UI 之下 → 只泛光世界不糊 UI）
shader_type canvas_item;
render_mode blend_add;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float intensity : hint_range(0.0, 3.0) = 0.95;   // 叠加强度
uniform float threshold : hint_range(0.0, 1.0) = 0.42;   // 亮部阈值（越低泛光越广）
uniform float radius_uv : hint_range(0.002, 0.05) = 0.014; // 模糊半径（屏幕高度占比）

void fragment() {
	vec2 ts = vec2(textureSize(screen_tex, 0));
	vec2 px = vec2(radius_uv * ts.y / max(ts.x, 1.0), radius_uv);
	// 双环 13 采样模糊（中心 + 6 邻近 + 6 外圈），足够柔和且开销低
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb;
	float w_sum = 1.0;
	for (int i = 0; i < 6; i++) {
		float a = 6.2831853 * float(i) / 6.0 + 0.26;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 uv1 = clamp(SCREEN_UV + dir * px, px, vec2(1.0) - px);
		vec2 uv2 = clamp(SCREEN_UV + dir * px * 2.15, px, vec2(1.0) - px);
		acc += texture(screen_tex, uv1).rgb;
		w_sum += 1.0;
		acc += texture(screen_tex, uv2).rgb * 0.65;
		w_sum += 0.65;
	}
	acc /= w_sum;
	// 亮部提取：亮度过阈值的部分才参与叠加
	float lum = dot(acc, vec3(0.299, 0.587, 0.114));
	float w = smoothstep(threshold, threshold + 0.38, lum);
	COLOR = vec4(acc * w * intensity, 1.0);
}
