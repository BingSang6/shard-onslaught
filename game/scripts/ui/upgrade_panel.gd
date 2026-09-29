extends CanvasLayer
## 升级弹窗（PRD 2.5-3）：经验满触发，弹出 3 张技能卡片 3 选 1。
## 弹出时游戏世界暂停（get_tree().paused = true 由 main 控制），点击选择后恢复。
## 卡片：圆角晶体矩形 + 几何图形技能图标（原型阶段用几何图形代替图标）+ 名称/等级/描述。

signal chosen(skill_id: String)

## 推荐项描边色（任务书 §5.2：紫 #9922dd）
const RECOMMEND_COLOR := Color("9922dd")

## 技能 ID → 设计稿透明图标（素材替换指南步骤 5；弹种卡/heal 无贴图走几何兜底）
const SKILL_ICONS := {
	"ricochet":      preload("res://assets/skills/skill_ricochet.png"),
	"shatter_blast": preload("res://assets/skills/skill_shatter_blast.png"),
	"aura":          preload("res://assets/skills/skill_aura.png"),
	"shield":        preload("res://assets/skills/skill_shield.png"),
	"dash":          preload("res://assets/skills/skill_dash.png"),
	"fire_rate":     preload("res://assets/skills/skill_fire_rate.png"),
	"heavy_spike":   preload("res://assets/skills/skill_heavy_spike.png"),
	"vortex":        preload("res://assets/skills/skill_vortex.png"),
}

var _cards_box: VBoxContainer
var _root: Control
var _title_label: Label
var _recommended: String = ""            # 推荐项 skill_id（空 = 无推荐）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	# 半透明暗化背景
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -290
	box.offset_right = 290
	box.offset_top = -430
	box.offset_bottom = 430
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_title_label = UIStyle.make_label("★ 晶体升华 ★", 40, Color(0.6, 0.95, 1.0))
	box.add_child(_title_label)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 16)
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_cards_box)


## 展示 3 选 1（choices: Array[String]，含 "heal" 应急修复卡）
## recommended: 推荐项 id（高亮 + 空格快捷确认）；pending: 本次连升合并的级数（>1 显示"连升 N 级"）
func open(choices: Array, skills: Node, recommended: String = "", pending: int = 1) -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_recommended = recommended if choices.has(recommended) else ""
	for skill_id in choices:
		_cards_box.add_child(_make_card(skill_id, skills, skill_id == _recommended))
	_title_label.text = "★ 晶体升华 · 连升 %d 级 ★" % pending if pending > 1 else "★ 晶体升华 ★"
	_root.visible = true


func close() -> void:
	_root.visible = false
	_recommended = ""


## 空格 = 一键确认推荐项（任务书 §5.2：2 秒内回战斗）
func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or _recommended == "":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_on_card_pressed(_recommended)
		get_viewport().set_input_as_handled()


## 构建单张技能卡片
func _make_card(skill_id: String, skills: Node, is_recommended := false) -> Control:
	var is_heal := skill_id == "heal"
	var meta: Dictionary = GameConfig.SKILLS.get(skill_id, {})
	var name_text: String = "应急修复" if is_heal else meta["name"]
	var desc_text: String = "立即回复 40 点生命值" if is_heal else meta["desc"]
	var icon_color: Color = Color(0.5, 1.0, 0.7) if is_heal else meta["color"]
	var icon_sides := 4 if is_heal else int(meta["sides"])
	var cur_lv: int = 0 if is_heal else skills.get_level(skill_id)
	var next_lv: int = cur_lv + 1

	var card := Button.new()
	card.custom_minimum_size = Vector2(560, 190)
	card.focus_mode = Control.FOCUS_NONE
	var sb_normal := UIStyle.panel_style(icon_color, 2, 14)
	sb_normal.set_content_margin_all(16)
	var sb_hover := UIStyle.panel_style(Color(icon_color, 1.0).lightened(0.2), 3, 14)
	sb_hover.set_content_margin_all(16)
	sb_hover.bg_color = Color(0.08, 0.14, 0.2, 0.95)
	if is_recommended:
		# 推荐项：紫描边高亮（normal/hover 双态都保持描边可辨识）
		sb_normal.border_color = RECOMMEND_COLOR
		sb_normal.set_border_width_all(4)
		sb_hover.border_color = RECOMMEND_COLOR
		sb_hover.set_border_width_all(4)
	card.add_theme_stylebox_override("normal", sb_normal)
	card.add_theme_stylebox_override("hover", sb_hover)
	card.add_theme_stylebox_override("pressed", sb_hover)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(_on_card_pressed.bind(skill_id))

	# 卡片内容：HBox = 图标 | 文本列
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# 技能图标：设计稿透明 PNG（TextureRect 自适应 80x80）；heal 无贴图保留几何兜底
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(80, 80)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_tex: Texture2D = SKILL_ICONS.get(skill_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_wrap.add_child(icon)
	else:
		var icon := Polygon2D.new()
		icon.polygon = GameConfig.regular_polygon_points(icon_sides, 34.0)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/crystal_glow.gdshader")
		mat.set_shader_parameter("base_color", icon_color)
		mat.set_shader_parameter("glow_strength", 1.6)
		mat.set_shader_parameter("rim_strength", 1.0)
		mat.set_shader_parameter("extent", 34.0)
		icon.material = mat
		icon.position = Vector2(40, 40)   # 让多边形居中于 wrap
		icon_wrap.add_child(icon)
	h.add_child(icon_wrap)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_row)
	if is_recommended:
		var rec_lb: Label = UIStyle.make_label("★ 推荐", 19, RECOMMEND_COLOR.lightened(0.6))
		name_row.add_child(rec_lb)
	var name_lb := UIStyle.make_label(name_text, 28)
	name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_row.add_child(name_lb)
	var lv_lb: Label = UIStyle.make_label("Lv.%d → %d" % [cur_lv, next_lv] if cur_lv > 0 else "新技能!", 20, Color(0.8, 0.95, 1.0))
	name_row.add_child(lv_lb)

	var desc_lb := UIStyle.make_label(desc_text, 19, Color(0.85, 0.92, 0.98))
	desc_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lb.custom_minimum_size = Vector2(380, 0)
	v.add_child(desc_lb)
	return card


func _on_card_pressed(skill_id: String) -> void:
	chosen.emit(skill_id)
