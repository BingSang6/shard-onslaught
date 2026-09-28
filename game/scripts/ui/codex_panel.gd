extends CanvasLayer
## 晶体图鉴（阶段3，PRD 2.5-1）：3 种怪物条目。
## 已遭遇：彩色几何形象 + 数值；未遭遇：暗色剪影 + ???（解锁数据来自 GameData.unlocked_monsters）。

signal closed

const _ORDER := ["small", "big", "boss"]
const _FLAVOR := {
	"small": "数量多、移动快——连锁爆炸的最佳燃料",
	"big": "血厚移慢，击杀奖励大量经验",
	"boss": "120 秒固定刷新，击破获得临时攻击增益",
}

var _root: Control
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
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -380
	box.offset_bottom = 380
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	var title := UIStyle.make_label("晶 体 图 鉴", 40, Color(0.8, 0.75, 1.0))
	box.add_child(title)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 14)
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


func _rebuild() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	for id in _ORDER:
		_rows_box.add_child(_make_entry(id))


## 单条怪物条目
func _make_entry(monster_id: String) -> Control:
	var cfg: Dictionary = GameConfig.MONSTERS[monster_id]
	var unlocked: bool = GameData.unlocked_monsters.has(monster_id)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(600, 132)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", UIStyle.panel_style(
		cfg["color"] if unlocked else Color(0.25, 0.28, 0.38), 2, 12))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	# 形象预览：已解锁=设计稿贴图原彩；未解锁=同贴图压暗剪影（保留轮廓悬念）
	var icon_tex: Texture2D = load({
		"small": "res://assets/monster_small.png",
		"big":   "res://assets/monster_big.png",
		"boss":  "res://assets/monster_boss.png",
	}[monster_id])
	var icon := TextureRect.new()
	icon.texture = icon_tex
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if unlocked else Color(0.18, 0.20, 0.30)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(84, 84)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(icon)
	h.add_child(icon_wrap)

	# 文本列
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	if unlocked:
		var name_lb := UIStyle.make_label("%s  ×已遭遇" % cfg["name"], 25)
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(name_lb)
		var stat_lb := UIStyle.make_label(
			"生命 %d · 速度 %d · 经验 %d" % [cfg["hp"], cfg["speed"], cfg["xp"]],
			18, Color(0.82, 0.9, 1.0))
		stat_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(stat_lb)
	else:
		var name_lb := UIStyle.make_label("???", 25, Color(0.55, 0.6, 0.72))
		name_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(name_lb)

	var flavor_lb := UIStyle.make_label(_FLAVOR[monster_id], 15, Color(0.66, 0.74, 0.86))
	flavor_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	flavor_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor_lb.custom_minimum_size = Vector2(360, 0)
	v.add_child(flavor_lb)
	return row
