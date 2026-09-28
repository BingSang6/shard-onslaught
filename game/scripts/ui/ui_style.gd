class_name UIStyle
## UI 风格助手（视觉规范：半透深色晶体面板 + 青蓝发光描边 + 白色粗体发光文字）
## 全部纯代码构建，不使用任何图片资源。

const PRIMARY := Color("0ac8dd")        # 主色：青蓝发光
const PURPLE := Color("9922dd")         # 辅助色：紫
const BG := Color("080818")             # 背景：深黑蓝
const TEXT := Color("ffffff")
const PANEL_BG := Color(0.04, 0.05, 0.10, 0.88)   # 半透深色晶体面板


## 半透深色面板样式（1~2px 青蓝发光描边）
static func panel_style(border_color := PRIMARY, border_width := 2, radius := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(14)
	return sb


## 带外发光的文字标签（outline + shadow 双层辉光）
static func make_label(text: String, size: int, color := TEXT, outline := true) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", color)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if outline:
		lb.add_theme_color_override("font_outline_color", Color(0.04, 0.55, 0.65, 0.9))
		lb.add_theme_constant_override("outline_size", maxi(2, size / 8))
		# 发光 shadow（Godot 4 的 Label 模糊阴影 = 辉光）
		lb.add_theme_color_override("font_shadow_color", Color(0.04, 0.78, 0.87, 0.55))
		lb.add_theme_constant_override("shadow_offset_x", 0)
		lb.add_theme_constant_override("shadow_offset_y", 0)
		lb.add_theme_constant_override("shadow_outline_size", maxi(6, size / 5))
	return lb


## 晶体按钮（hover 亮度提升）
static func make_button(text: String, font_size := 26, min_size := Vector2(240, 72)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_outline_color", Color(0.04, 0.55, 0.65, 0.9))
	btn.add_theme_constant_override("outline_size", 4)
	var normal := panel_style(PRIMARY, 2, 12)
	var hover := panel_style(PRIMARY, 2, 12)
	hover.bg_color = Color(0.06, 0.22, 0.26, 0.92)
	var pressed := panel_style(Color("7df3ff"), 2, 12)
	pressed.bg_color = Color(0.08, 0.30, 0.34, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(func(): SoundManager.play("click"))  # 阶段4：统一按钮点击音
	bind_hover(btn)
	return btn


## 悬浮光效（阶段3 D 项）：鼠标悬停时轻微提亮 + 放大，离开复原（视觉整改任务书 D-3）
static func bind_hover(ctrl: Control) -> void:
	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.resized.connect(func(): ctrl.pivot_offset = ctrl.size / 2.0)
	ctrl.mouse_entered.connect(func():
		var tw := ctrl.create_tween().set_parallel(true)
		tw.tween_property(ctrl, "modulate", Color(1.3, 1.3, 1.3), 0.10)
		tw.tween_property(ctrl, "scale", Vector2(1.05, 1.05), 0.10))
	ctrl.mouse_exited.connect(func():
		var tw := ctrl.create_tween().set_parallel(true)
		tw.tween_property(ctrl, "modulate", Color.WHITE, 0.16)
		tw.tween_property(ctrl, "scale", Vector2.ONE, 0.16))


## 进度条样式（晶体分段填充、发光边缘 → 用青/紫填充 + 深色底）
static func bar_styles(fill_color: Color) -> Array:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.04, 0.08, 0.85)
	bg.set_corner_radius_all(6)
	bg.border_color = Color(fill_color, 0.45)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(6)
	fill.border_color = Color(fill_color, 0.8).lightened(0.35)
	fill.set_border_width_all(1)
	return [bg, fill]
