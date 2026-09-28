// 引力漩涡 Shader（视觉规范：紫色螺旋渐变，由外向内吸附，脉动发光）
shader_type canvas_item;
render_mode blend_add;
uniform vec4 vortex_color : source_color = vec4(0.6, 0.13, 0.87, 1.0);
uniform float extent : hint_range(8.0, 1024.0) = 128.0; // 漩涡半径（像素）
uniform float spin_speed : hint_range(0.0, 12.0) = 5.0;

void fragment() {
	vec2 p = VERTEX / extent;
	float r = clamp(length(p), 0.0, 1.0);
	float ang = atan(p.y, p.x);
	float spiral = 0.5 + 0.5 * sin(ang * 3.0 + r * 16.0 - TIME * spin_speed);
	float pulse = 0.8 + 0.2 * sin(TIME * 6.0);
	float alpha = (1.0 - r) * (0.30 + 0.62 * spiral) * pulse;
	COLOR = vec4(vortex_color.rgb * (1.5 + spiral * 0.8), alpha);
}
