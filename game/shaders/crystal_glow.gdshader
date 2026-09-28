// 晶体自发光 Shader（视觉规范：青蓝发光、边缘高亮、受击闪白）
// 基于 PRD 文档给的 Shader 扩展：VERTEX 距离场替代 UV（Polygon2D 的 UV 非归一化），
// 并增加 rim 边缘高亮与 flash 受击闪白。
shader_type canvas_item;
uniform vec4 base_color : source_color = vec4(0.04, 0.78, 0.87, 1.0);
uniform float glow_strength : hint_range(0.0, 3.0) = 1.2;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.9;
uniform float extent : hint_range(1.0, 1024.0) = 32.0; // 多边形外接半径（像素）
uniform float flash : hint_range(0.0, 1.0) = 0.0;      // 受击/高亮闪白

void fragment() {
	float d = clamp(length(VERTEX) / extent, 0.0, 1.0);
	float core = 1.0 - d;                 // 中心亮核
	float rim = smoothstep(0.55, 1.0, d); // 边缘高亮
	vec3 rgb = base_color.rgb * (glow_strength * core + rim_strength * rim);
	rgb = mix(rgb, vec3(1.0), flash);
	COLOR = vec4(rgb, base_color.a);
}
