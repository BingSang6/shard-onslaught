// 外发光光晕（Halo）：径向渐变，中心亮、边缘衰减。
// 配合 render_mode blend_add 叠加在晶体多边形下层，产生霓虹辉光质感。
// 用途：玩家 / 怪物 / 背景晶簇 / 爆炸光斑 共用。
shader_type canvas_item;
render_mode blend_add;
uniform vec4 halo_color : source_color = vec4(0.04, 0.78, 0.87, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.2;
uniform float extent : hint_range(1.0, 1024.0) = 48.0; // 光晕外接半径（像素）

void fragment() {
	float d = clamp(length(VERTEX) / extent, 0.0, 1.0);
	float glow = pow(1.0 - d, 2.4);
	COLOR = vec4(halo_color.rgb * intensity, glow * 0.6);
}
