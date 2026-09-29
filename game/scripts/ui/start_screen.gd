extends CanvasLayer
## 主菜单（阶段3 完整版，PRD 2.5-1）：开始游戏 / 永久强化面板 / 图鉴面板
## 标题 + 三入口按钮 + 操作提示 + 存档晶核展示（refresh() 在强化购买后刷新）。

signal start_pressed
signal shop_pressed
signal codex_pressed

var _core_label: Label
var _wave_label: Label
var _auto_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# 静音开关（阶段4）：右上角小按钮，状态持久化存档
	var mute_btn := UIStyle.make_button("", 20, Vector2(150, 48))
	mute_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mute_btn.offset_left = -170
	mute_btn.offset_right = -20
	mute_btn.offset_top = 16
	mute_btn.pressed.connect(func():
		var muted_now: bool = SoundManager.toggle_mute()
		mute_btn.text = "音效 关" if muted_now else "音效 开")
	root.add_child(mute_btn)
	mute_btn.text = "音效 关" if GameData.muted else "音效 开"

	# 自动升级开关（任务书 §5.4）：左上角，开启后升级不弹窗自动学推荐
	_auto_btn = UIStyle.make_button("", 19, Vector2(190, 48))
	_auto_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_auto_btn.offset_left = 20
	_auto_btn.offset_right = 210
	_auto_btn.offset_top = 16
	_auto_btn.pressed.connect(func():
		GameData.auto_upgrade = not GameData.auto_upgrade
		GameData.save_game()
		refresh())
	root.add_child(_auto_btn)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -360
	box.offset_bottom = 360
	box.add_theme_constant_override("separation", 22)
	root.add_child(box)

	# 标题：大号发光 + 装饰菱形
	var deco := Polygon2D.new()
	deco.polygon = GameConfig.regular_polygon_points(4, 26.0)
	var dmat := ShaderMaterial.new()
	dmat.shader = load("res://shaders/crystal_glow.gdshader")
	dmat.set_shader_parameter("base_color", Color(0.04, 0.78, 0.87, 1.0))
	dmat.set_shader_parameter("glow_strength", 1.8)
	dmat.set_shader_parameter("extent", 26.0)
	deco.material = dmat
	var deco_wrap := Control.new()
	deco_wrap.custom_minimum_size = Vector2(0, 64)
	deco.position = Vector2(0, 20)
	deco_wrap.add_child(deco)
	box.add_child(deco_wrap)

	var title := UIStyle.make_label("碎晶突围", 62, Color(0.55, 0.95, 1.0))
	box.add_child(title)
	var subtitle := UIStyle.make_label("晶洞割草 · 连锁爆炸", 23, Color(0.8, 0.8, 1.0))
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 22)
	box.add_child(spacer)

	# 三入口（PRD 2.5-1）：开始 / 永久强化 / 图鉴
	var start_btn := UIStyle.make_button("开 始 突 围", 32, Vector2(340, 88))
	start_btn.pressed.connect(func(): start_pressed.emit())
	box.add_child(start_btn)

	var shop_btn := UIStyle.make_button("永 久 强 化", 24, Vector2(340, 66))
	shop_btn.pressed.connect(func(): shop_pressed.emit())
	box.add_child(shop_btn)

	var codex_btn := UIStyle.make_button("晶 体 图 鉴", 24, Vector2(340, 66))
	codex_btn.pressed.connect(func(): codex_pressed.emit())
	box.add_child(codex_btn)

	var hint := UIStyle.make_label("拖动屏幕移动 · 自动攻击\n升级时 3 选 1 强化技能", 18, Color(0.7, 0.8, 0.9))
	box.add_child(hint)

	_core_label = UIStyle.make_label("", 21, Color(0.85, 0.7, 1.0))
	box.add_child(_core_label)

	# 波次制进度：历史最高关卡 + 通关标识（存档 max_wave）
	_wave_label = UIStyle.make_label("", 19, Color(0.7, 0.95, 1.0))
	box.add_child(_wave_label)
	refresh()


## 刷新晶核储备/最高关卡/自动升级开关显示（强化面板购买后由 main 调用）
func refresh() -> void:
	_core_label.text = "◆ 晶核储备：%d" % GameData.crystal_core
	if GameData.max_wave > 0:
		var cleared := " ★已通关★" if GameData.cleared_all else ""
		_wave_label.text = "最高到达：第 %d / %d 关%s" % [
			GameData.max_wave, GameConfig.WAVE_COUNT, cleared]
	else:
		_wave_label.text = "尚无闯关记录（共 %d 关）" % GameConfig.WAVE_COUNT
	if _auto_btn != null:
		_auto_btn.text = "自动升级 开" if GameData.auto_upgrade else "自动升级 关"


func show_screen() -> void:
	refresh()
	visible = true


func hide_screen() -> void:
	visible = false
