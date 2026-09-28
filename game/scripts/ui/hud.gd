extends CanvasLayer
## 局内 HUD（CanvasLayer，PROCESS_MODE_ALWAYS，暂停时仍显示）
## 顶部：血条 + 倒计时 + 击杀数；底部：经验条 + 等级；右下：瞬闪按钮；
## 中部：连锁爆炸连击弹字。全部纯代码构建，无图片资源。

signal dash_pressed

var hp_bar: ProgressBar
var hp_label: Label
var wave_label: Label
var time_label: Label
var kill_label: Label
var core_label: Label
var xp_bar: ProgressBar
var level_label: Label
var combo_label: Label
var notice_label: Label
var dash_button: Button
var dash_cd_label: Label
var boss_name_label: Label
var boss_bar: ProgressBar

var _player: Node2D = null
var _boss: Monster = null                       # HUD 轮询 BOSS 血量（波次制血条）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- 顶部状态区 ----
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 14
	top.add_theme_constant_override("separation", 14)
	root.add_child(top)

	# 血条（左）
	var hp_box := VBoxContainer.new()
	hp_box.custom_minimum_size = Vector2(280, 30)
	hp_box.add_theme_constant_override("separation", 2)
	top.add_child(hp_box)
	hp_label = UIStyle.make_label("HP 100/100", 15)
	hp_box.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(280, 20)
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.show_percentage = false
	var hp_styles: Array = UIStyle.bar_styles(Color(0.05, 0.85, 0.8))
	hp_bar.add_theme_stylebox_override("background", hp_styles[0])
	hp_bar.add_theme_stylebox_override("fill", hp_styles[1])
	hp_box.add_child(hp_bar)

	# 倒计时（中，上带关卡进度"第 N/10 关"）
	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", 0)
	time_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(time_box)
	wave_label = UIStyle.make_label("第 1/10 关", 17, Color(0.85, 0.75, 1.0))
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_box.add_child(wave_label)
	time_label = UIStyle.make_label("00:30", 40)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_box.add_child(time_label)

	# 击杀（右，含晶核货币显示——PRD 2.5-2）
	var kill_box := VBoxContainer.new()
	kill_box.custom_minimum_size = Vector2(120, 60)
	kill_box.add_theme_constant_override("separation", 0)
	top.add_child(kill_box)
	kill_label = UIStyle.make_label("击杀 0", 20, Color(0.72, 0.95, 1.0))
	kill_box.add_child(kill_label)
	core_label = UIStyle.make_label("◆0", 16, Color(0.85, 0.7, 1.0))
	kill_box.add_child(core_label)

	# ---- 底部经验条 ----
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_bottom = -16
	bottom.offset_top = -52
	bottom.add_theme_constant_override("separation", 3)
	root.add_child(bottom)
	level_label = UIStyle.make_label("Lv.1", 17, Color(0.85, 0.75, 1.0))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bottom.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 12)
	xp_bar.min_value = 0
	xp_bar.max_value = 1
	xp_bar.show_percentage = false
	var xp_styles: Array = UIStyle.bar_styles(Color(0.6, 0.13, 0.87))
	xp_bar.add_theme_stylebox_override("background", xp_styles[0])
	xp_bar.add_theme_stylebox_override("fill", xp_styles[1])
	bottom.add_child(xp_bar)

	# ---- 连锁连击弹字（中上）----
	combo_label = UIStyle.make_label("", 40, Color(1.0, 0.95, 0.6))
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	combo_label.offset_top = 190
	combo_label.modulate.a = 0.0
	root.add_child(combo_label)

	# ---- 系统提示弹字（BOSS 增益等，中上偏下）----
	notice_label = UIStyle.make_label("", 26, Color(0.85, 1.0, 0.8))
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice_label.offset_top = 250
	notice_label.modulate.a = 0.0
	root.add_child(notice_label)

	# ---- BOSS 血条（顶部下方居中，仅 BOSS 关显示）----
	var boss_box := VBoxContainer.new()
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -300
	boss_box.offset_right = 300
	boss_box.offset_top = 108
	boss_box.add_theme_constant_override("separation", 2)
	boss_box.visible = false
	root.add_child(boss_box)
	boss_name_label = UIStyle.make_label("碎晶王", 19, Color(0.95, 0.75, 1.0))
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name_label)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(600, 14)
	boss_bar.min_value = 0
	boss_bar.max_value = 100
	boss_bar.show_percentage = false
	var boss_styles: Array = UIStyle.bar_styles(Color(0.78, 0.2, 0.95))
	boss_bar.add_theme_stylebox_override("background", boss_styles[0])
	boss_bar.add_theme_stylebox_override("fill", boss_styles[1])
	boss_box.add_child(boss_bar)

	# ---- 瞬闪按钮（右下）----
	dash_button = UIStyle.make_button("瞬 闪", 22, Vector2(104, 104))
	dash_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dash_button.offset_left = -136
	dash_button.offset_top = -170
	dash_button.offset_right = -28
	dash_button.offset_bottom = -62
	dash_button.visible = false
	dash_button.pressed.connect(func(): dash_pressed.emit())
	root.add_child(dash_button)
	dash_cd_label = UIStyle.make_label("", 20)
	dash_cd_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dash_cd_label.offset_left = -136
	dash_cd_label.offset_top = -110
	dash_cd_label.offset_right = -28
	dash_cd_label.offset_bottom = -78
	dash_cd_label.visible = false
	root.add_child(dash_cd_label)

	# 事件
	GameEvents.chain_triggered.connect(_on_chain)
	GameEvents.player_damaged.connect(_on_hp_changed)
	GameEvents.player_healed.connect(_on_hp_changed)


func bind_player(p_player: Node2D) -> void:
	## 每局调用：只刷新绑定状态（信号连接在 main._connect_signals 中一次性建立）
	_player = p_player
	dash_button.visible = _player.skills.get_level("dash") > 0
	dash_cd_label.visible = dash_button.visible


# ---------------- 数据更新 ----------------

func set_hp(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "HP %d/%d" % [roundi(hp), roundi(max_hp)]


func _on_hp_changed(hp: float, max_hp: float) -> void:
	set_hp(hp, max_hp)


func set_time(seconds_left: float) -> void:
	var s := maxf(0.0, seconds_left)
	time_label.text = "%02d:%02d" % [int(s / 60.0), int(s) % 60]
	if s <= 15.0:
		time_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		time_label.add_theme_color_override("font_color", Color.WHITE)


## 波次进度显示（"第 N/10 关"）
func set_wave(wave: int, total: int) -> void:
	wave_label.text = "第 %d/%d 关" % [wave, total]


## BOSS 血条：绑定 BOSS 实例（每帧轮询 hp；BOSS 死/关切换时 clear）
func bind_boss(boss: Monster, boss_name: String) -> void:
	_boss = boss
	boss_name_label.text = boss_name
	boss_name_label.get_parent().visible = true
	if boss != null:
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp


func clear_boss() -> void:
	_boss = null
	boss_name_label.get_parent().visible = false


func set_kills(count: int) -> void:
	kill_label.text = "击杀 %d" % count


## 晶核货币显示（开局=存档余额；结算入账后刷新）
func set_cores(count: int) -> void:
	core_label.text = "◆%d" % count


## 系统提示弹字（自动淡出）
func show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	notice_label.scale = Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(notice_label, "scale", Vector2.ONE, 0.2)
	tw.parallel().tween_property(notice_label, "modulate:a", 0.0, 2.2).set_delay(0.8)


func set_xp(level: int, xp: float, xp_next: float) -> void:
	level_label.text = "Lv.%d" % level
	xp_bar.max_value = xp_next
	xp_bar.value = xp


func _on_chain(combo: int) -> void:
	if combo < 2:
		return
	combo_label.text = "连锁爆炸 x%d!" % combo
	combo_label.scale = Vector2(1.4, 1.4)
	combo_label.modulate.a = 1.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 用真实时间，暂停时也自然衰减
	tw.tween_property(combo_label, "scale", Vector2.ONE, 0.18)
	tw.parallel().tween_property(combo_label, "modulate:a", 0.0, 1.2).set_delay(0.25)


func _on_dash_changed(cd_left: float, cd_total: float) -> void:
	_update_dash(cd_left, cd_total)


func _process(_delta: float) -> void:
	# BOSS 血条轮询（BOSS 关）
	if _boss != null:
		if is_instance_valid(_boss):
			boss_bar.max_value = max(_boss.max_hp, 1.0)
			boss_bar.value = maxf(0.0, _boss.hp)
		else:
			clear_boss()

	# 每帧刷新瞬闪按钮冷却显示
	if _player == null or not dash_button.visible:
		return
	var info: Vector2 = _player.dash_cd_info()
	if info == Vector2.ZERO:
		return
	_update_dash(info.x, info.y)


func _update_dash(cd_left: float, cd_total: float) -> void:
	if cd_left <= 0.0:
		dash_button.modulate = Color.WHITE
		dash_cd_label.text = "就绪"
	else:
		dash_button.modulate = Color(1, 1, 1, 0.45)
		dash_cd_label.text = "%.1f" % cd_left


func show_dash_button(visible_: bool) -> void:
	dash_button.visible = visible_
	dash_cd_label.visible = visible_
