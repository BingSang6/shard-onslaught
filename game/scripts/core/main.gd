extends Node2D
## 主场景编排 + 全局游戏管理器（对应 SDS 的 GameLogic.gd）

const Halo = preload("res://scripts/effects/halo.gd")
## 状态机（SDS 3.6）：MENU / PLAYING / UPGRADE_PANEL / SETTLE
## 职责：构建整棵节点树（全代码创建，无复杂 tscn）、倒计时、经验与升级流程、
## 结算与晶核发放、局外永久强化应用、局间世界清理。
##
## 节点树（对应 SDS 第2节架构）：
## Main
## ├─ Background   深色晶洞背景（几何装饰多边形 + 场地边框）
## ├─ Camera2D     跟随玩家（带屏幕震动注入 EffectManager）
## ├─ World
## │  ├─ PlayerLayer → Player（菱形晶体）
## │  ├─ MonsterLayer → MonsterSpawner → Monster×N
## │  ├─ ProjectileLayer → Projectile×N（晶刺）
## │  ├─ DropLayer → DropManager → CrystalDrop×N（晶粒）
## │  └─ EffectLayer → EffectManager（连锁爆炸/粒子/冲击波）
## ├─ SkillSystem → SkillManager（→ 晶域/晶盾/引力漩涡节点）
## └─ UI：FlashLayer / HUD / StartScreen / UpgradePanel / SettlePanel

enum State { MENU, PLAYING, UPGRADE_PANEL, SETTLE }

var state: int = State.MENU

# 局内数据（波次闯关制：倒计时由 WaveManager 的"本关时限"取代）
var kill_count := 0
var level := 1
var xp := 0.0
var pending_levelups := 0
var boss_killed := false
var boss_core_reward := 0          # BOSS 击破晶核奖励累计（BOSSES.reward.core）
var final_boss_killed := false     # 主宰击破 → 通关结算晶核翻倍

# 节点引用
var camera: Camera2D
var player: Player
var spawner: MonsterSpawner
var wave_manager: WaveManager
var drop_manager: DropManager
var effect_manager: EffectManager
var skills: SkillManager
var projectile_layer: Node2D
var drop_layer: Node2D
var flash_rect: ColorRect
var world_modulate: CanvasModulate
var hud: CanvasLayer
var start_screen: CanvasLayer
var upgrade_panel: CanvasLayer
var settle_panel: CanvasLayer
var upgrade_shop: CanvasLayer
var codex_panel: CanvasLayer


func _ready() -> void:
	randomize()
	add_to_group("game")
	_build_background()
	_build_world()
	_build_skills()
	_build_ui()
	_connect_signals()
	# 初始进入菜单态：玩家居中待机作为背景
	player.position = GameConfig.ARENA_SIZE / 2.0
	camera.position = player.position
	camera.make_current()


# ========================= 节点树构建 =========================

func _build_background() -> void:
	var bg := Node2D.new()
	bg.name = "Background"
	add_child(bg)

	# 深色晶洞：随机散布的暗淡几何晶簇（固定种子，风格统一）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var palette := [Color("0ac8dd"), Color("9922dd"), Color("35e6ff")]
	for i in 60:
		var poly := Polygon2D.new()
		var r := rng.randf_range(26.0, 110.0)
		poly.polygon = GameConfig.regular_polygon_points(rng.randi_range(3, 6), r)
		poly.position = Vector2(
			rng.randf_range(30.0, GameConfig.ARENA_SIZE.x - 30.0),
			rng.randf_range(30.0, GameConfig.ARENA_SIZE.y - 30.0)
		)
		poly.rotation = rng.randf() * TAU
		var c: Color = palette[rng.randi() % palette.size()]
		c.a = rng.randf_range(0.16, 0.30)          # 提升可见度（原 0.03~0.09 近不可见）
		poly.color = c
		bg.add_child(poly)
		# 晶簇光晕：暗淡氛围辉光
		var halo := Halo.create(r * 2.4, Color(c, 0.9), 0.65)  # 视觉整改V3：晶簇光晕增强
		halo.position = poly.position
		bg.add_child(halo)

	# 大范围氛围光斑（画面深空霓虹感，挂在晶簇之下）
	for i in 5:
		var spot := Halo.create(rng.randf_range(180.0, 320.0),
			Color(palette[rng.randi() % palette.size()], 1.0), 0.50)
		spot.position = Vector2(
			rng.randf_range(150.0, GameConfig.ARENA_SIZE.x - 150.0),
			rng.randf_range(150.0, GameConfig.ARENA_SIZE.y - 150.0)
		)
		spot.z_index = -10
		bg.add_child(spot)

	# 浮动尘埃粒子层（缓慢漂浮的青/紫混合微光，增强晶洞氛围）
	var dust := GPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 150
	dust.lifetime = 9.0
	dust.local_coords = false
	var dmat := ParticleProcessMaterial.new()
	dmat.direction = Vector3(0, -1, 0)
	dmat.spread = 180.0
	dmat.gravity = Vector3(0, -3, 0)
	dmat.initial_velocity_min = 8.0
	dmat.initial_velocity_max = 30.0
	dmat.scale_min = 0.4
	dmat.scale_max = 1.5
	dmat.color = Color(1, 1, 1, 1)
	# 逐粒子颜色抖动：青 → 亮白 → 紫 渐变带随机取样（视觉规范的青紫双色氛围）
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.9, 1.0, 0.55))
	grad.add_point(0.5, Color(0.9, 0.95, 1.0, 0.62))
	grad.set_color(1, Color(0.72, 0.4, 1.0, 0.5))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	dmat.color_initial_ramp = grad_tex
	dust.process_material = dmat
	dust.texture = GameConfig.diamond_texture(9)
	dmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dmat.emission_box_extents = Vector3(GameConfig.ARENA_SIZE.x / 2.0, GameConfig.ARENA_SIZE.y / 2.0, 0)
	dust.position = GameConfig.ARENA_SIZE / 2.0
	bg.add_child(dust)

	# 场地边框：青蓝发光描边（双层，外圈淡光晕）
	var border := Line2D.new()
	var a := Vector2(6, 6)
	var b := GameConfig.ARENA_SIZE - Vector2(6, 6)
	border.points = PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a])
	border.width = 3.0
	border.default_color = Color(0.04, 0.78, 0.87, 0.45)
	bg.add_child(border)
	var border_glow := Line2D.new()
	border_glow.points = PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a])
	border_glow.width = 10.0
	border_glow.default_color = Color(0.04, 0.78, 0.87, 0.10)
	bg.add_child(border_glow)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameConfig.ARENA_SIZE.x)
	camera.limit_bottom = int(GameConfig.ARENA_SIZE.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)


func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	# 整屏色调调制（连锁爆炸瞬时的"提亮闪动"，EffectManager 驱动脉冲）
	var modulate := CanvasModulate.new()
	modulate.name = "WorldModulate"
	world.add_child(modulate)
	world_modulate = modulate

	var player_layer := Node2D.new()
	player_layer.name = "PlayerLayer"
	world.add_child(player_layer)

	player = Player.new()
	player.arena_rect = Rect2(Vector2.ZERO, GameConfig.ARENA_SIZE)
	player_layer.add_child(player)

	var monster_layer := Node2D.new()
	monster_layer.name = "MonsterLayer"
	monster_layer.add_to_group("monster_layer")   # BOSS 召唤/分裂体挂载点（boss_action 查组）
	world.add_child(monster_layer)
	spawner = MonsterSpawner.new()
	spawner.name = "Spawner"
	monster_layer.add_child(spawner)

	# 波次闯关管理器（10 关轮替 + BOSS 关；驱动 spawner 与关间空投）
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	monster_layer.add_child(wave_manager)

	projectile_layer = Node2D.new()
	projectile_layer.name = "ProjectileLayer"
	world.add_child(projectile_layer)

	# 敌方弹幕层（BOSS 招式弹幕；boss_action 按组查找）
	var enemy_proj_layer := Node2D.new()
	enemy_proj_layer.name = "EnemyProjectileLayer"
	enemy_proj_layer.add_to_group("enemy_projectile_layer")
	world.add_child(enemy_proj_layer)

	drop_layer = Node2D.new()
	drop_layer.name = "DropLayer"
	world.add_child(drop_layer)
	drop_manager = DropManager.new()
	drop_layer.add_child(drop_manager)

	var effect_layer := Node2D.new()
	effect_layer.name = "EffectLayer"
	world.add_child(effect_layer)
	effect_manager = EffectManager.new()
	effect_layer.add_child(effect_manager)


func _build_skills() -> void:
	var skill_system := Node2D.new()
	skill_system.name = "SkillSystem"
	add_child(skill_system)
	skills = SkillManager.new()
	skill_system.add_child(skills)


func _build_ui() -> void:
	# 全屏 Bloom 泛光层（后处理：亮部模糊提亮叠加）
	# 层级 1：世界(基础画布 0) 之上、所有 UI 之下 → 只泛光世界，不糊 UI 文字
	var bloom_layer := CanvasLayer.new()
	bloom_layer.name = "BloomLayer"
	bloom_layer.layer = 1
	add_child(bloom_layer)
	var bloom_rect := ColorRect.new()
	var bloom_mat := ShaderMaterial.new()
	bloom_mat.shader = load("res://shaders/bloom.gdshader")
	bloom_mat.set_shader_parameter("intensity", GameConfig.BLOOM["intensity"])
	bloom_mat.set_shader_parameter("threshold", GameConfig.BLOOM["threshold"])
	bloom_mat.set_shader_parameter("radius_uv", GameConfig.BLOOM["radius_uv"])
	bloom_rect.material = bloom_mat
	bloom_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bloom_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom_layer.add_child(bloom_rect)

	# 全屏闪光层（连锁爆炸高光）
	var flash_layer := CanvasLayer.new()
	flash_layer.name = "FlashLayer"
	flash_layer.layer = 5
	flash_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(flash_layer)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.85, 1.0, 1.0, 1.0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.modulate.a = 0.0
	flash_layer.add_child(flash_rect)

	# 局内 HUD（各面板在自身 _ready 中设定层级：Bloom1 < 闪光5 < HUD10 < 弹窗20 < 局外面板21）
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.visible = false            # 菜单态不显示局内 HUD
	add_child(hud)

	# 升级 3 选 1 弹窗
	upgrade_panel = preload("res://scripts/ui/upgrade_panel.gd").new()
	add_child(upgrade_panel)

	# 结算面板
	settle_panel = preload("res://scripts/ui/settle_panel.gd").new()
	add_child(settle_panel)

	# 局外面板（阶段3）：永久强化 / 晶体图鉴（挂在主菜单之上）
	upgrade_shop = preload("res://scripts/ui/upgrade_shop.gd").new()
	add_child(upgrade_shop)
	codex_panel = preload("res://scripts/ui/codex_panel.gd").new()
	add_child(codex_panel)

	# 开始界面（主菜单）
	start_screen = preload("res://scripts/ui/start_screen.gd").new()
	add_child(start_screen)


func _connect_signals() -> void:
	GameEvents.xp_gained.connect(_on_xp_gained)
	GameEvents.monster_killed.connect(_on_monster_killed)
	GameEvents.boss_defeated.connect(_on_boss_defeated)
	GameEvents.skill_chosen.connect(_on_skill_applied)
	player.died.connect(func(): _finish_run(false))
	start_screen.start_pressed.connect(start_run)
	upgrade_panel.chosen.connect(_on_upgrade_chosen)
	settle_panel.restart_pressed.connect(start_run)
	settle_panel.menu_pressed.connect(_back_to_menu)
	hud.dash_pressed.connect(func(): player.try_dash())
	player.dash_state_changed.connect(hud._on_dash_changed)
	# 局外面板（阶段3）：主菜单三入口开合
	start_screen.shop_pressed.connect(func():
		upgrade_shop.open())
	start_screen.codex_pressed.connect(func():
		codex_panel.open())
	upgrade_shop.closed.connect(func():
		upgrade_shop.close()
		start_screen.refresh())
	codex_panel.closed.connect(func():
		codex_panel.close()
		start_screen.refresh())

	# 波次闯关制：关卡推进 / BOSS 血条 / 关间过渡提示 / 通关
	wave_manager.all_waves_cleared.connect(func(): _finish_run(true))
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.transition_started.connect(func(next_wave: int, _dur: float):
		hud.show_notice("补给空投！第 %d 关来袭" % next_wave))


# ========================= 对局生命周期 =========================

## 开始一局：清场 → 应用永久强化 → 重置各系统 → 进入 PLAYING
func start_run() -> void:
	_clear_world()
	get_tree().paused = false
	state = State.PLAYING
	kill_count = 0
	level = 1
	xp = 0.0
	pending_levelups = 0
	boss_killed = false
	boss_core_reward = 0
	final_boss_killed = false

	player.position = GameConfig.ARENA_SIZE / 2.0
	camera.position = player.position
	camera.make_current()

	skills.reset(player)
	effect_manager.reset()
	effect_manager.skills = skills
	effect_manager.camera = camera
	effect_manager.flash_rect = flash_rect
	effect_manager.world_modulate = world_modulate
	drop_manager.player = player

	# 局外永久强化（PRD 2.4）
	var perm: Dictionary = GameData.perm_bonuses()
	player.setup(skills, perm, projectile_layer)
	wave_manager.reset(player, spawner, drop_manager)   # 进入第 1 关（spawner 由其接管）

	# 永久强化：开局获得 1 级随机技能
	if perm.get("start_skill", false):
		var ids: Array = GameConfig.SKILLS.keys()
		var pick: String = ids[randi() % ids.size()]
		skills.acquire(pick)
		player.sync_weapon_from_skills()   # 开局随机到弹种卡时同步弹种
		if pick == "dash":
			hud.show_dash_button(true)

	# UI 复位
	start_screen.hide_screen()
	settle_panel.close()
	upgrade_panel.close()
	hud.visible = true
	hud.bind_player(player)
	hud.show_dash_button(skills.get_level("dash") > 0)
	hud.set_hp(player.hp, player.max_hp)
	hud.set_time(wave_manager.wave_time_left)
	hud.set_kills(0)
	hud.set_cores(GameData.crystal_core)
	hud.set_xp(level, xp, GameConfig.xp_to_next(level))
	GameEvents.run_started.emit()


## 返回主菜单（阶段3 将扩展为完整主菜单）
func _back_to_menu() -> void:
	_clear_world()
	get_tree().paused = false
	state = State.MENU
	settle_panel.close()
	hud.visible = false              # 菜单态隐藏局内 HUD
	player.position = GameConfig.ARENA_SIZE / 2.0
	camera.position = player.position
	start_screen.show_screen()


## 清空局内实体（怪物/晶刺/晶粒/技能节点/爆炸队列）
func _clear_world() -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		m.alive = false
		m.queue_free()
	for d in get_tree().get_nodes_in_group("drops"):
		d.queue_free()
	for p in projectile_layer.get_children():
		p.queue_free()
	for ep in get_tree().get_nodes_in_group("enemy_projectiles"):
		ep.queue_free()
	effect_manager.reset()
	skills.reset(player)


# ========================= 帧驱动 =========================

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	camera.position = camera.position.lerp(player.position, minf(1.0, delta * 8.0))

	# 波次推进（SDS 3.6：升级/结算暂停时不走这里，因树已 paused）
	wave_manager.update(delta)
	hud.set_time(maxf(0.0, wave_manager.wave_time_left))


# ---- 波次事件：HUD 关卡显示 / BOSS 血条 ----

func _on_wave_started(wave: int, cfg: Dictionary) -> void:
	hud.set_wave(wave, GameConfig.WAVE_COUNT)
	if String(cfg.get("type", "normal")) == "boss":
		var boss_cfg: Dictionary = GameConfig.BOSSES[cfg.get("boss_id", "boss1")]
		hud.show_notice("BOSS · %s 来袭！" % boss_cfg["name"])
		hud.bind_boss(wave_manager.get_boss(), String(boss_cfg["name"]))


func _on_wave_cleared(_wave: int) -> void:
	hud.clear_boss()


# ========================= 经验 / 升级流程 =========================

func _on_xp_gained(amount: float) -> void:
	if state != State.PLAYING:
		return
	xp += amount
	var leveled := false
	while xp >= GameConfig.xp_to_next(level):
		xp -= GameConfig.xp_to_next(level)
		level += 1
		pending_levelups += 1
		leveled = true
	hud.set_xp(level, xp, GameConfig.xp_to_next(level))
	if leveled:
		GameEvents.level_up.emit(level)
		_open_upgrade_panel()


## 打开升级 3 选 1（连升合并：≥2 级只弹 1 次，选 1 个其余自动学推荐）
## 自动升级开关开启时不弹窗，全部自动学推荐（任务书 §5.3/§5.4）
func _open_upgrade_panel() -> void:
	if GameData.auto_upgrade:
		_auto_apply_levelups()
		return
	state = State.UPGRADE_PANEL
	get_tree().paused = true
	var choices: Array = skills.get_choices(3)
	upgrade_panel.open(choices, skills, _pick_recommended(choices), pending_levelups)


## 自动升级：全部等级学推荐项，HUD 弹字提示
func _auto_apply_levelups() -> void:
	while pending_levelups > 0:
		var choices: Array = skills.get_choices(3)
		var pick := _pick_recommended(choices)
		_apply_skill(pick)
		pending_levelups -= 1
		hud.show_notice("自动习得 %s" % _skill_display_name(pick))


## 应用一个技能（弹种卡同步玩家弹种状态）
func _apply_skill(skill_id: String) -> void:
	if skill_id == "heal":
		player.heal(40.0)
	else:
		skills.acquire(skill_id)
		player.sync_weapon_from_skills()
		if skill_id == "dash":
			hud.show_dash_button(true)
	GameEvents.skill_chosen.emit(skill_id)


## 选择技能后：应用 → 其余连升等级自动学推荐 → 恢复战斗（一次弹窗处理完）
func _on_upgrade_chosen(skill_id: String) -> void:
	_apply_skill(skill_id)
	pending_levelups -= 1
	while pending_levelups > 0:
		var rest: Array = skills.get_choices(3)
		var auto_pick := _pick_recommended(rest)
		_apply_skill(auto_pick)
		pending_levelups -= 1
	upgrade_panel.close()
	get_tree().paused = false
	state = State.PLAYING


## 推荐项规则（任务书 §5.2 按序）：①残血→heal ②已有弹种卡→强化 ③已学未满→升级 ④随机
func _pick_recommended(pool: Array) -> String:
	# ① HP<35% 且 heal 卡在池
	if player.hp < player.max_hp * 0.35 and pool.has("heal"):
		return "heal"
	# ② 已有弹种卡 → 对应弹种强化
	for wid in GameConfig.WEAPON_TYPES.keys():
		if wid == "default":
			continue
		if skills.get_level(wid) > 0 and pool.has(wid):
			return wid
	# ③ 已有技能未满级（池内随机，权重均等）
	var owned: Array = []
	for id in pool:
		if id != "heal" and skills.get_level(id) > 0 \
				and skills.get_level(id) < skills.skill_max_lv(id):
			owned.append(id)
	if not owned.is_empty():
		return owned[randi() % owned.size()]
	# ④ 默认随机
	return pool[randi() % pool.size()]


func _skill_display_name(skill_id: String) -> String:
	if skill_id == "heal":
		return "应急修复"
	return String(GameConfig.SKILLS.get(skill_id, {}).get("name", skill_id))


## 技能应用后的 HUD/系统刷新钩子（当前无需额外处理，保留扩展点）
func _on_skill_applied(_skill_id: String) -> void:
	pass


# ========================= 击杀 / BOSS / 结算 =========================

func _on_monster_killed(monster: Monster) -> void:
	if state != State.PLAYING and state != State.UPGRADE_PANEL:
		return
	kill_count += 1
	hud.set_kills(kill_count)
	if GameConfig.BOSSES.has(monster.monster_id):
		boss_killed = true
		_apply_boss_reward(monster.monster_id)


## BOSS 击破奖励（任务书第二节各 BOSS"击破奖励"行；晶核部分并入结算明细）
func _apply_boss_reward(boss_id: String) -> void:
	var reward: Dictionary = GameConfig.BOSSES[boss_id]["reward"]
	boss_core_reward += int(reward.get("core", 0))
	if reward.get("heal", 0.0) > 0.0:
		player.heal(float(reward["heal"]))
	if reward.get("buff_attack", 0.0) > 0.0:
		player.apply_attack_buff(float(reward["buff_attack"]), float(reward.get("buff_time", 20.0)))
		hud.show_notice("晶核过载！攻击 +%d（%d 秒）" % [int(reward["buff_attack"]), int(reward.get("buff_time", 20.0))])
	if reward.get("max_hp", 0.0) > 0.0:
		player.max_hp += float(reward["max_hp"])
		player.hp += float(reward["max_hp"])
		hud.set_hp(player.hp, player.max_hp)
		hud.show_notice("巨兽精粹！最大生命 +%d" % int(reward["max_hp"]))
	if reward.get("fire_buff", 0.0) > 0.0:
		player.apply_fire_buff(float(reward["fire_buff"]), float(reward.get("buff_time", 30.0)))
		hud.show_notice("魔核共鸣！射速 +15%%（%d 秒）" % int(reward.get("buff_time", 30.0)))
	if reward.get("double_core", false):
		final_boss_killed = true
		hud.show_notice("晶洞主宰陨落！通关晶核翻倍")


## BOSS 击破：回血 + 临时攻击增益（旧单 BOSS 逻辑；奖励明细已按 BOSSES.reward 拆分到
## _apply_boss_reward，本钩子保留给通用"BOSS 击破"事件消费方（音效等））
func _on_boss_defeated() -> void:
	pass


## 结束一局：胜利=通关第 10 关；失败=血量归零。结算并立即存档晶核（失败也发放）。
func _finish_run(won: bool) -> void:
	if state == State.SETTLE:
		return
	state = State.SETTLE
	wave_manager.stop()
	get_tree().paused = true

	# 到达关卡（波次制进度：失败=中途死亡时的关卡；胜利=10）
	var reached_wave: int = wave_manager.current_wave
	GameData.record_wave(reached_wave, won)

	# 晶核公式（阶段3 拆明细展示）：击杀 + 连锁高光 + BOSS + 胜负底薪（主宰击破翻倍）
	var kill_pay := kill_count
	var combo_pay := max_combo() * 2
	var boss_pay := boss_core_reward
	var base_pay := 30 if won else 10
	var cores: int = kill_pay + combo_pay + boss_pay + base_pay
	if final_boss_killed:
		cores *= 2                       # 主宰击破奖励：通关结算晶核翻倍
	GameData.add_core(cores)
	GameData.save_game()
	hud.set_cores(GameData.crystal_core)

	var stats := {
		"kills": kill_count,
		"max_combo": max_combo(),
		"survived": wave_manager.run_elapsed,
		"wave": reached_wave,
		"wave_total": GameConfig.WAVE_COUNT,
		"cores": cores,
		"breakdown": {"kills": kill_pay, "combo": combo_pay, "boss": boss_pay, "base": base_pay},
	}
	settle_panel.open(won, stats)
	GameEvents.run_finished.emit(won, stats)


func max_combo() -> int:
	return effect_manager.max_combo
