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
	box.offset_top = -470
	box.offset_bottom = 470
	box.add_theme_constant_override("separation", 10)
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


## 依据 GameData 当前状态重建强化行 + 皮肤分区（购买后刷新余额与按钮可用性）
func _rebuild() -> void:
	_balance_label.text = "◆ 晶核余额：%d" % GameData.crystal_core
	for child in _rows_box.get_children():
		child.queue_free()
	for key in GameConfig.PERM_UPGRADES.keys():
		_rows_box.add_child(_make_row(key))
	# V0.8.6 皮肤外观分区（同一晶核货币，纯外观无属性；购买即装备，可随时换回）
	var sec := UIStyle.make_label("皮 肤 外 观", 24, Color(0.7, 0.95, 1.0))
	sec.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_rows_box.add_child(sec)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_rows_box.add_child(grid)
	for id in GameConfig.SKINS.keys():
		grid.add_child(_make_skin_cell(id))


## 单行强化条目
func _make_row(key: String) -> Control:
	var cfg: Dictionary = GameConfig.PERM_UPGRADES[key]
	var lv: int = GameData.get_upgrade_lv(key)
	var max_lv: int = int(cfg["max_lv"])
	var cost: int = GameConfig.perm_upgrade_cost(key, lv)
	var maxed := lv >= max_lv
	var affordable := GameData.crystal_core >= cost

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(620, 80)
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
	icon_wrap.custom_minimum_size = Vector2(56, 56)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(28, 28)
	icon_wrap.add_child(icon)
	h.add_child(icon_wrap)

	# 名称 + 等级 + 效果说明
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
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


## V0.8.6 皮肤格子：晶体预览 + 名称 + 状态（使用中/装备/购买 N◆/晶核不足）
func _make_skin_cell(id: String) -> Control:
	var cfg: Dictionary = GameConfig.SKINS[id]
	var owned: bool = GameData.has_skin(id)
	var equipped: bool = GameData.equipped_skin == id
	var cost := int(cfg["cost"])

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(200, 124)
	# 装备中亮边（皮肤辉光色），其余统一暗板
	var edge: Color = cfg["glow"] if equipped else Color(0.25, 0.32, 0.42)
	cell.add_theme_stylebox_override("panel", UIStyle.panel_style(edge, 2, 10))
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(v)

	# 晶体预览（与强化图标同款发光多边形，本体用皮肤染色）
	var icon := Polygon2D.new()
	icon.polygon = GameConfig.regular_polygon_points(6, 20.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crystal_glow.gdshader")
	mat.set_shader_parameter("base_color", cfg["tint"])
	mat.set_shader_parameter("glow_strength", 1.5)
	mat.set_shader_parameter("extent", 20.0)
	icon.material = mat
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(36, 40)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(18, 20)
	icon_wrap.add_child(icon)
	v.add_child(icon_wrap)

	var name_lb := UIStyle.make_label(cfg["name"], 18)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lb)

	if equipped:
		var on_lb := UIStyle.make_label("使用中", 17, Color(1.0, 0.9, 0.4))
		on_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(on_lb)
	else:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 17)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_outline_color", Color(0.04, 0.55, 0.65, 0.9))
		btn.add_theme_constant_override("outline_size", 3)
		var sb := UIStyle.panel_style(cfg["glow"], 2, 10)
		var sb_off := UIStyle.panel_style(Color(0.3, 0.35, 0.45), 2, 10)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("disabled", sb_off)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if owned:
			btn.text = "装 备"
			btn.pressed.connect(func():
				if GameData.equip_skin(id):
					SoundManager.play("click")
					_rebuild())
		else:
			btn.text = "购买 %d◆" % cost
			btn.disabled = GameData.crystal_core < cost
			if not btn.disabled:
				UIStyle.bind_hover(btn)
				btn.pressed.connect(func():
					if GameData.try_buy_skin(id):
						SoundManager.play("buy")
						_rebuild())
		v.add_child(btn)
	return cell
