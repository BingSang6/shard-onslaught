extends CanvasLayer
## 结算面板（最简版；完整晶核经济/永久强化面板属阶段3）
## 展示胜负结果、击杀数、最高连锁连击、获得晶核；提供再来一局/返回主菜单。
## 晶核奖励即时写入存档（PRD：失败也发放晶核，降低挫败感）。

signal restart_pressed
signal menu_pressed


var _root: Control
var _title_label: Label
var _stats_label: Label
var _core_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	box.offset_top = -330
	box.offset_bottom = 330
	box.add_theme_constant_override("separation", 24)
	_root.add_child(box)

	_title_label = UIStyle.make_label("", 52)
	box.add_child(_title_label)

	_stats_label = UIStyle.make_label("", 24, Color(0.85, 0.9, 1.0))
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats_label)

	_core_label = UIStyle.make_label("", 28, Color(0.85, 0.7, 1.0))
	box.add_child(_core_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer)

	var restart_btn := UIStyle.make_button("再 来 一 局", 28, Vector2(320, 84))
	restart_btn.pressed.connect(func(): restart_pressed.emit())
	box.add_child(restart_btn)

	var menu_btn := UIStyle.make_button("返回主菜单", 22, Vector2(320, 64))
	menu_btn.pressed.connect(func(): menu_pressed.emit())
	box.add_child(menu_btn)


## 展示结算（stats: {kills, max_combo, survived, wave, wave_total, cores, breakdown}）
func open(won: bool, stats: Dictionary) -> void:
	_title_label.text = "突 围 成 功 !" if won else "晶 体 破 碎 ..."
	_title_label.add_theme_color_override(
		"font_color", Color(0.5, 1.0, 0.9) if won else Color(1.0, 0.5, 0.55)
	)
	var survived: float = stats.get("survived", 0.0)
	var wave: int = stats.get("wave", 0)
	var wave_total: int = stats.get("wave_total", GameConfig.WAVE_COUNT)
	# 波次制进度：胜利=通关第 N 关；失败=到达第 N 关（任务书：替代"存活 180s"目标感）
	_stats_label.text = "%s\n击杀怪物：%d\n最高连锁：x%d\n战斗时长：%02d:%02d" % [
		("★ 通关全部 %d 关 ★" % wave_total) if won else ("到达 第 %d / %d 关" % [wave, wave_total]),
		stats.get("kills", 0), stats.get("max_combo", 0),
		int(survived / 60.0), int(survived) % 60,
	]
	# 晶核奖励明细（阶段3：让玩家看懂钱从哪来）
	var bd: Dictionary = stats.get("breakdown", {})
	var cores: int = stats.get("cores", 0)
	if not bd.is_empty():
		_core_label.add_theme_font_size_override("font_size", 22)
		_core_label.text = "— 晶核明细 —\n击杀 %d ×1 = %d\n最高连锁 x%d ×2 = %d\n%s\n%s\n合计 +%d（已存档）" % [
			stats.get("kills", 0), int(bd.get("kills", 0)),
			stats.get("max_combo", 0), int(bd.get("combo", 0)),
			"BOSS 击破 +%d" % int(bd.get("boss", 0)) if int(bd.get("boss", 0)) > 0 else "BOSS 未击破 +0",
			("%s底薪 +%d" % ["胜利", int(bd.get("base", 0))]) if won else ("失败保底 +%d" % int(bd.get("base", 0))),
			cores,
		]
	else:
		_core_label.text = "获得晶核 +%d（已存档）" % cores
	_root.visible = true


func close() -> void:
	_root.visible = false
