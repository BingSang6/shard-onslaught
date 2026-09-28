class_name Halo
extends Polygon2D
## 外发光光晕节点：挂在晶体多边形下层，模拟霓虹辉光（零外部资源）。
## 用圆形网格 + 径向渐变 Shader（blend_add），比 draw_circle 更平滑。

## 创建光晕：radius 为发光范围（像素），color 发光色，intensity 强度
static func create(radius: float, color: Color, intensity := 1.2) -> Halo:
	var h := Halo.new()
	h.polygon = GameConfig.circle_points(radius, 40)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/halo.gdshader")
	mat.set_shader_parameter("halo_color", color)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("extent", radius)
	h.material = mat
	return h
