extends CanvasLayer
## 永久强化面板（阶段3，PRD 2.4 / 2.5-5）：4 项属性消耗晶核升级，跨局永久生效。
## 行结构：几何图标 | 名称+等级+效果说明 | 升级按钮（费用随等级上浮，满级禁用）。
## 购买成功立即写存档；关闭时发 closed 信号（main 刷新主菜单晶核显示）。

signal closed

var _root: Control
var _balance_label: Label
var _rows_box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 21

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -310
	box.offset_right = 310
	box.offset_top = -400
	box.offset_bottom = 400
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	var title := UIStyle.make_label("永 久 强 化", 40, Color(0.7, 0.95, 1.0))
	box.add_child(title)

	_balance_label = UIStyle.make_label("", 24, Color(0.85, 0.7, 1.0))
	box.add_child(_balance_label)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 12)
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_rows_box)

	var back_btn := UIStyle.make_button("返 回", 22, Vector2(240, 62))
	back_btn.pressed.connect(func(): closed.emit())
	box.add_child(back_btn)


func open() -> void:
	_rebuild()
	_root.visible = true


func close() -> void:
	_root.visible = false


## 依据 GameData 当前状态重建 4 行（购买后刷新余额与按钮可用性）
func _rebuild() -> void:
	_balance_label.text = "◆ 晶核余额：%d" % GameData.crystal_core
	for child in _rows_box.get_children():
		child.queue_free()
	for key in GameConfig.PERM_UPGRADES.keys():
		_rows_box.add_child(_make_row(key))


## 单行强化条目
func _make_row(key: String) -> Control:
	var cfg: Dictionary = GameConfig.PERM_UPGRADES[key]
	var lv: int = GameData.get_upgrade_lv(key)
	var max_lv: int = int(cfg["max_lv"])
	var cost: int = GameConfig.perm_upgrade_cost(key, lv)
	var maxed := lv >= max_lv
	var affordable := GameData.crystal_core >= cost

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(620, 108)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", UIStyle.panel_style(cfg["color"], 2, 12))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	# 几何图标（晶体 Shader 发光）
	var icon := Polygon2D.new()
	icon.polygon = GameConfig.regular_polygon_points(int(cfg["sides"]), 26.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crystal_glow.gdshader")
	mat.set_shader_parameter("base_color", cfg["color"])
	mat.set_shader_parameter("glow_strength", 1.5)
	mat.set_shader_parameter("extent", 26.0)
	icon.material = mat
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(64, 64)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(32, 32)
	icon_wrap.add_child(icon)
	h.add_child(icon_wrap)

	# 名称 + 等级 + 效果说明
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_row)
	var name_lb := UIStyle.make_label(cfg["name"], 24)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_row.add_child(name_lb)
	var lv_lb := UIStyle.make_label("Lv.%d/%d" % [lv, max_lv], 19, Color(0.8, 0.95, 1.0))
	name_row.add_child(lv_lb)

	var desc_lb := UIStyle.make_label(cfg["desc"], 16, Color(0.8, 0.86, 0.95))
	desc_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(desc_lb)

	# 升级按钮：满级禁用 / 晶核不足禁用
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 70)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color(0.04, 0.55, 0.65, 0.9))
	btn.add_theme_constant_override("outline_size", 3)
	var sb := UIStyle.panel_style(cfg["color"], 2, 10)
	var sb_off := UIStyle.panel_style(Color(0.3, 0.35, 0.45), 2, 10)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb_off)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if maxed:
		btn.text = "已满级"
		btn.disabled = true
	else:
		btn.text = "升级 %d◆" % cost
		btn.disabled = not affordable
		UIStyle.bind_hover(btn)
		btn.pressed.connect(func():
			if GameData.try_upgrade(key):
				SoundManager.play("buy")  # 阶段4：购买成功音
				_rebuild())
	h.add_child(btn)
	return row
