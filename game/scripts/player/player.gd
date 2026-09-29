class_name Player
extends Area2D
## 玩家：发光菱形晶体（视觉规范 #0ac8dd）

const Halo = preload("res://scripts/effects/halo.gd")
## 职责：触屏拖动跟随移动（桌面兼容鼠标拖动/WASD）、自动发射晶刺、
## 血量与受击无敌帧、瞬闪冲刺（查询 SkillManager）、持有技能引用。
## 碰撞采用 Area2D + 手动位移（性能友好，怪物/投射物同方案）。

signal dash_state_changed(cd_left: float, cd_total: float)
signal died

const PLAYER_CFG := GameConfig.PLAYER

var skills: Node = null                     # SkillManager 引用（由 main 注入）
var projectile_layer: Node2D = null         # 晶刺挂载层（由 main 注入）
var arena_rect := Rect2()                   # 活动范围（由 main 注入）

var max_hp := 100.0
var hp := 100.0
var base_attack := 8.0
var base_fire_interval := 0.8
var pick_radius := 90.0

# ---- BOSS 击破临时增益（PRD 2.3：击杀大量经验 + 临时增益 buff）----
var _buff_attack := 0.0            # 临时攻击加成
var _buff_time := 0.0              # 增益剩余时间（秒）
var _fire_buff_mult := 1.0         # 临时射速倍率（引力魔核奖励：间隔×mult）
var _fire_buff_time := 0.0         # 射速增益剩余时间

# ---- 弹种系统（《战斗循环增强任务书》§3）----
var weapon_id := "default"         # 已习得弹种（弹种卡；default=单发晶刺）
var weapon_lv := 1                 # 已习得弹种等级（1~3，伤害系数 ×1.0/1.15/1.3）
var temp_weapon_id := ""           # 弹种道具临时弹种（8s，到期回落）
var temp_weapon_time := 0.0

# ---- 护盾碎片（掉落补给：挡 1 次伤害，上限 3 层）----
var shield_charges := 0

var _touch_target := Vector2.ZERO           # 触屏/鼠标拖动的目标点（世界坐标）
var _touching := false
var _fire_cd := 0.0
var _iframe := 0.0                          # 受击无敌帧剩余
var _hit_flash_t := 0.0

# ---- 瞬闪 ----
var _dash_cd := 0.0
var _dash_time := 0.0
var _dash_dir := Vector2.ZERO

var _poly: Sprite2D
var _idle_particles: GPUParticles2D
var _trail: GPUParticles2D                   # 移动拖尾光
var _prev_pos := Vector2.ZERO                # 上一物理帧位置（测速驱动拖尾）
var _kb_vel := Vector2.ZERO                 # 受击退速度（衰减）


func _ready() -> void:
	# 碰撞：第 1 层为玩家，检测怪物（第 2 层）
	collision_layer = 1
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0  # 视觉整改V2：贴图放大1.8x后碰撞同步上调(18→30)
	shape.shape = circle
	add_child(shape)

	# 外发光光晕（霓虹辉光质感，双层：内层亮核 + 外层大范围柔光，垫在晶体下层）
	var halo_wide := Halo.create(85.0, Color(0.04, 0.78, 0.87), 0.75)  # 视觉整改V2：光晕85配合放大后实体
	add_child(halo_wide)
	var halo := Halo.create(50.0, Color(0.04, 0.78, 0.87), 2.4)
	add_child(halo)

	# 晶体外观：设计稿透明 PNG（贴图自带辉光，Sprite2D 替代几何原型）
	_poly = Sprite2D.new()
	_poly.texture = preload("res://assets/player_crystal.png")
	_poly.scale = Vector2.ONE * GameConfig.sprite_scale(22.0, _poly.texture.get_width()) * 1.8  # 视觉整改V2：玩家贴图专项放大1.8x(主角突出)
	add_child(_poly)

	# 周身微光粒子（SDS：GPUParticles2D 微光）
	_idle_particles = GPUParticles2D.new()
	_idle_particles.amount = 10
	_idle_particles.lifetime = 1.2
	_idle_particles.local_coords = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 40.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 22.0
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(0.5, 0.9, 1.0, 0.5)
	_idle_particles.process_material = mat
	_idle_particles.texture = GameConfig.diamond_texture(11)
	add_child(_idle_particles)

	# 移动拖尾光：世界坐标粒子，只在移动/冲刺时发射（青色渐隐残迹）
	_trail = GPUParticles2D.new()
	_trail.amount = 36
	_trail.lifetime = 0.38
	_trail.local_coords = false
	_trail.emitting = false
	var tmat := ParticleProcessMaterial.new()
	tmat.direction = Vector3(0, 1, 0)
	tmat.spread = 180.0
	tmat.gravity = Vector3.ZERO
	tmat.initial_velocity_min = 4.0
	tmat.initial_velocity_max = 14.0
	tmat.scale_min = 0.25
	tmat.scale_max = 0.7
	tmat.color = Color(0.35, 0.85, 1.0, 0.55)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	tmat.scale_curve = shrink_tex
	_trail.process_material = tmat
	_trail.texture = GameConfig.diamond_texture(9)
	add_child(_trail)

	add_to_group("player")
	monitoring = false


## 应用局外永久强化（PRD 2.4）并重置状态
func setup(p_skills: Node, perm: Dictionary, p_projectile_layer: Node2D) -> void:
	skills = p_skills
	projectile_layer = p_projectile_layer
	max_hp = PLAYER_CFG["max_hp"] + perm.get("bonus_hp", 0.0)
	hp = max_hp
	base_attack = PLAYER_CFG["attack"] + perm.get("bonus_attack", 0.0)
	base_fire_interval = PLAYER_CFG["fire_interval"]
	pick_radius = PLAYER_CFG["pick_radius"] + perm.get("bonus_pick_radius", 0.0)
	_iframe = 0.0
	_dash_cd = 0.0
	_dash_time = 0.0
	_touching = false
	_buff_attack = 0.0
	_buff_time = 0.0
	_fire_buff_mult = 1.0
	_fire_buff_time = 0.0
	weapon_id = "default"
	weapon_lv = 1
	temp_weapon_id = ""
	temp_weapon_time = 0.0
	shield_charges = 0


func _physics_process(delta: float) -> void:
	_iframe = maxf(0.0, _iframe - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_hit_flash_t = maxf(0.0, _hit_flash_t - delta * 4.0)
	# 受击闪白：贴图模式用 modulate 提亮衰减（替代原 shader flash 参数）
	var hf := _hit_flash_t
	_poly.modulate = Color(1.0 + 2.0 * hf, 1.0 + 2.0 * hf, 1.0 + 2.0 * hf)
	_kb_vel = _kb_vel.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	# BOSS 增益计时（到期清零）
	if _buff_time > 0.0:
		_buff_time -= delta
		if _buff_time <= 0.0:
			_buff_attack = 0.0
			_buff_time = 0.0
	if _fire_buff_time > 0.0:
		_fire_buff_time -= delta
		if _fire_buff_time <= 0.0:
			_fire_buff_mult = 1.0
			_fire_buff_time = 0.0
	# 弹种道具临时弹种计时（到期回落到已习得弹种）
	if temp_weapon_time > 0.0:
		temp_weapon_time -= delta
		if temp_weapon_time <= 0.0:
			temp_weapon_id = ""
			temp_weapon_time = 0.0

	var move_dir := Vector2.ZERO
	if _dash_time > 0.0:
		# 瞬闪冲刺中
		_dash_time -= delta
		move_dir = _dash_dir
		position += move_dir * _dash_speed() * delta
	else:
		if _touching:
			# 触屏/鼠标：平滑跟随目标点（SDS 3.1）
			var to_target := _touch_target - position
			if to_target.length() > 12.0:
				move_dir = to_target.normalized()
				position += move_dir * PLAYER_CFG["speed"] * delta
		else:
			# 键盘（桌面调试）
			move_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			position += move_dir * PLAYER_CFG["speed"] * delta
		position += _kb_vel * delta

	# 场地边界
	position = position.clamp(arena_rect.position + Vector2(20, 20), arena_rect.end - Vector2(20, 20))

	# 晶体朝移动方向微转
	if move_dir.length() > 0.1:
		rotation = lerp_angle(rotation, move_dir.angle() + PI / 2.0, delta * 10.0)

	# 拖尾：实际位移速度超过阈值或冲刺中才发射
	var vel := (position - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = position
	_trail.emitting = vel.length() > 80.0 or _dash_time > 0.0

	# 自动攻击
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		var target := _nearest_monster(PLAYER_CFG["target_range"])
		if target != null:
			_fire(target)
			_fire_cd = _current_fire_interval()


## 当前发射间隔 = 基础间隔 × 高速结晶倍率 × BOSS 射速增益倍率
func _current_fire_interval() -> float:
	var mult := 1.0
	if skills != null and skills.get_level("fire_rate") > 0:
		mult = GameConfig.skill_params("fire_rate", skills.get_level("fire_rate"))["interval_mult"]
	return base_fire_interval * mult * _fire_buff_mult


## 当前晶刺伤害 = 基础攻击 × 晶刺增重倍率 + BOSS 临时增益
func _current_attack() -> float:
	var mult := 1.0
	if skills != null and skills.get_level("heavy_spike") > 0:
		mult = GameConfig.skill_params("heavy_spike", skills.get_level("heavy_spike"))["damage_mult"]
	return base_attack * mult + _buff_attack


func _current_knockback() -> float:
	if skills != null and skills.get_level("heavy_spike") > 0:
		return GameConfig.skill_params("heavy_spike", skills.get_level("heavy_spike"))["knockback"]
	return 60.0


## 自动索敌：范围内最近的存活怪物
func _nearest_monster(reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.alive:
			continue
		var d: float = position.distance_to(m.position)
		if d < best_d:
			best_d = d
			best = m
	return best


## 当前生效弹种 id：弹种道具临时弹种 > 已习得弹种 > default
func current_weapon() -> String:
	if temp_weapon_time > 0.0 and GameConfig.WEAPON_TYPES.has(temp_weapon_id):
		return temp_weapon_id
	return weapon_id


## 发射晶刺（弹种系统：按 WEAPON_TYPES 分支多枚/扇形/穿透/追踪/爆炸）
func _fire(target: Node2D) -> void:
	GameEvents.shot_fired.emit()  # 阶段4：发射音效
	var wid := current_weapon()
	var wcfg: Dictionary = GameConfig.WEAPON_TYPES.get(wid, GameConfig.WEAPON_TYPES["default"])
	var base_dir := (target.position - position).normalized()
	# 弹种伤害系数（临时弹种按 Lv1；已习得弹种按弹种卡等级 ×1.0/1.15/1.3）
	var w_lv := weapon_lv if wid == weapon_id else 1
	var dmg := _current_attack() * float(wcfg["damage_mult"]) * GameConfig.weapon_lv_mult(w_lv)

	var count := int(wcfg["count"])
	var spread := deg_to_rad(float(wcfg["spread_deg"]))
	for i in count:
		var dir := base_dir
		if count > 1:
			# 扇形均匀散布（如 3 发 15°：-7.5°/0°/+7.5°）
			var t := (float(i) / float(count - 1)) - 0.5 if count > 1 else 0.0
			dir = base_dir.rotated(t * spread)
		var p := Projectile.new()
		p.setup(position, dir * float(wcfg["speed"]), dmg, _current_knockback())
		p.set_weapon(int(wcfg["pierce"]), float(wcfg["homing"]), float(wcfg["blast_radius"]),
			wcfg["color"])
		var ricochet_lv := 0
		if skills != null:
			ricochet_lv = skills.get_level("ricochet")
		if ricochet_lv > 0 and int(wcfg["pierce"]) == 0:
			# 弹射对非穿透弹种生效（穿透+弹射链防叠加超模：穿透弹不弹射）
			var rp := GameConfig.skill_params("ricochet", ricochet_lv)
			p.set_ricochet(int(rp["bounces"]), rp["bounce_range"], rp["falloff"])
		projectile_layer.add_child(p)


## 弹种道具：临时切到随机弹种（不覆盖已习得弹种，到期回落）
func equip_temp_weapon(wid: String) -> void:
	if GameConfig.WEAPON_TYPES.has(wid):
		temp_weapon_id = wid
		temp_weapon_time = GameConfig.DROP_TABLE["weapon_duration"]


## 从 SkillManager 同步弹种状态：取等级最高的弹种卡（升级选卡/开局随机技能/
## 自动升级共用；弹种卡 acquire 之后调用）
func sync_weapon_from_skills() -> void:
	var best_id := "default"
	var best_lv := 0
	if skills != null:
		for id in GameConfig.WEAPON_TYPES.keys():
			if id == "default":
				continue
			var lv: int = skills.get_level(id)
			if lv > best_lv:
				best_lv = lv
				best_id = id
	if best_lv > 0:
		weapon_id = best_id
		weapon_lv = best_lv


# ---------------- 输入（触屏拖动 / 鼠标拖动）----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touching = true
			_touch_target = _screen_to_world(event.position)
		else:
			_touching = false
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_target = _screen_to_world(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touching = event.pressed
		if event.pressed:
			_touch_target = get_global_mouse_position()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touching:
		_touch_target = get_global_mouse_position()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dash"):
		try_dash()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


# ---------------- 伤害 / 瞬闪 ----------------

func take_damage(amount: float) -> void:
	if _iframe > 0.0 or _dash_time > 0.0:
		return
	# 护盾碎片（掉落补给）：先扣碎片层，挡 1 次伤害
	if shield_charges > 0:
		shield_charges -= 1
		_iframe = PLAYER_CFG["hit_iframe"]
		return
	# 晶盾抵挡（技能节点提供）
	if skills != null and skills.consume_shield():
		_iframe = PLAYER_CFG["hit_iframe"]
		return
	hp -= amount
	_iframe = PLAYER_CFG["hit_iframe"]
	_hit_flash_t = 1.0
	GameEvents.player_damaged.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	GameEvents.player_healed.emit(hp, max_hp)


## BOSS 击破临时增益：攻击 +bonus，持续 duration 秒（重复击破刷新时长）
func apply_attack_buff(bonus: float, duration: float) -> void:
	_buff_attack = bonus
	_buff_time = duration


## 引力魔核击破奖励：射速 +bonus（15% → 间隔 ÷1.15），持续 duration 秒
func apply_fire_buff(bonus: float, duration: float) -> void:
	_fire_buff_mult = 1.0 / (1.0 + bonus)
	_fire_buff_time = duration


## 增益是否生效（HUD 显示用）
func attack_buff_active() -> bool:
	return _buff_time > 0.0 and _buff_attack > 0.0


## 护盾碎片：+1 层（上限 3），返回是否成功
func add_shield_charge() -> bool:
	if shield_charges >= int(GameConfig.DROP_TABLE["shield_max"]):
		return false
	shield_charges += 1
	return true


## 瞬闪：向当前移动方向冲刺，冲刺期间无敌（HUD 按钮触发）
func try_dash() -> void:
	if skills == null or skills.get_level("dash") == 0 or _dash_cd > 0.0 or _dash_time > 0.0:
		return
	var dp := GameConfig.skill_params("dash", skills.get_level("dash"))
	var dir := Vector2.ZERO
	if _touching:
		dir = (_touch_target - position).normalized()
	if dir == Vector2.ZERO:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	_dash_dir = dir.normalized()
	_dash_time = dp["duration"]
	_iframe = maxf(_iframe, dp["iframe"])
	_dash_cd = dp["cooldown"]
	dash_state_changed.emit(0.0, dp["cooldown"])
	SoundManager.play("dash")  # 阶段4：瞬闪呼啸音效


func _dash_speed() -> float:
	var dp := GameConfig.skill_params("dash", skills.get_level("dash"))
	return float(dp["distance"]) / float(dp["duration"])


## 供 HUD 显示瞬闪冷却
func dash_cd_info() -> Vector2:
	if skills == null:
		return Vector2.ZERO
	var lv: int = skills.get_level("dash")
	if lv == 0:
		return Vector2.ZERO
	var total: float = GameConfig.skill_params("dash", lv)["cooldown"]
	return Vector2(_dash_cd, total)
