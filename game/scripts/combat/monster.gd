class_name Monster
extends Area2D
## 怪物基类：几何多边形晶体（三角小晶怪 / 五边形大晶兽 / 5 BOSS 波次制）
## 职责：追踪玩家移动、接触伤害（带冷却）、受击伤害+击退+闪白、
## 死亡时发出 monster_killed 事件（携带 chain_level 死因，供连锁爆炸递进）。
## BOSS 扩展（任务书《波次闯关制》）：按 BOSSES 配置初始化（贴图/数值/招式）；
## 晶甲巨兽护甲壳（减伤+破碎脆弱期）；晶洞主宰三阶段；猎手/主宰分裂；
## 大晶兽精英头顶血条。

const Halo = preload("res://scripts/effects/halo.gd")

var monster_id := "small"
var display_name := "小晶怪"
var max_hp := 12.0
var hp := 12.0
var speed := 70.0
var xp_value := 5.0
var contact_damage := 8.0
var contact_cd := 0.9
var alive := true

# ---- BOSS 波次制扩展 ----
var is_boss := false                   # 本体 BOSS（BOSSES 配置驱动）
var is_split_child := false            # 分裂小体（不触发 BOSS 奖励/结算）
var invulnerable := false              # 分裂期间本体无敌
var dash_vel := Vector2.ZERO           # 冲刺斩速度（boss_action 注入）
var armor_hp := 0.0                    # 护甲壳余量（晶甲巨兽；>0 = 有甲）
var armor_reduction := 0.0             # 有甲减伤率（0.6 = 承伤 40%）
var fragile_left := 0.0                # 破甲脆弱期剩余（无减伤）
var phase_index := 0                   # 阶段（晶洞主宰 0/1/2；其余恒 0）
var boss_action: Node = null           # 招式组件（仅 BOSS 本体）

var player: Node2D = null              # 追踪目标（由 main 注入）
var _contact_timer := 0.0              # 接触伤害冷却
var _kb_vel := Vector2.ZERO            # 击退速度
var _flash := 0.0
var _poly: Sprite2D
var _radius := 16.0
var _spin := 0.0                       # 缓慢自转（视觉生命感）
var _hp_bar: ProgressBar               # 精英头顶血条（仅 big，受击时短暂显示）
var _hp_show_time := 0.0               # 头顶血条剩余显示秒数（受击刷新 3s，归零隐藏——避免满屏小条）


func _ready() -> void:
	collision_layer = 2                    # 第 2 层：怪物
	collision_mask = 1                     # 检测玩家（接触伤害）
	add_to_group("monsters")


## 按类型初始化（普通怪：GameConfig.MONSTERS；BOSS：GameConfig.BOSSES）
func setup(p_player: Node2D, p_monster_id: String, pos: Vector2) -> void:
	player = p_player
	monster_id = p_monster_id
	position = pos

	var cfg: Dictionary
	var tex_path: String
	if GameConfig.BOSSES.has(p_monster_id):
		is_boss = true
		cfg = GameConfig.BOSSES[p_monster_id]
		tex_path = String(cfg["tex"])
	else:
		cfg = GameConfig.MONSTERS[p_monster_id]
		tex_path = {
			"small": "res://assets/monster_small.png",
			"big":   "res://assets/monster_big.png",
			"boss":  "res://assets/monster_boss.png",
		}.get(p_monster_id, "res://assets/monster_small.png")

	display_name = String(cfg["name"])
	max_hp = float(cfg["hp"])
	hp = max_hp
	speed = float(cfg["speed"])
	xp_value = float(cfg["xp"])
	contact_damage = float(cfg["contact_damage"])
	contact_cd = float(cfg["contact_cd"])
	_radius = float(cfg["radius"])
	_spin = randf_range(-1.2, 1.2) if not is_boss else randf_range(-0.5, 0.5)

	# 护甲壳（晶甲巨兽）：armor 招式提供初始甲量/减伤/脆弱期
	for act in cfg.get("actions", []):
		if String(act.get("id", "")) == "armor":
			armor_hp = float(act.get("armor_hp", 0.0))
			armor_reduction = float(act.get("reduction", 0.0))
			fragile_left = 0.0

	# 碰撞形状
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _radius
	shape.shape = circle
	add_child(shape)

	# 外发光光晕（霓虹辉光质感，垫在晶体下层；范围/强度随类型上浮增强光溢出）
	var halo := Halo.create(_radius * 2.2, cfg["color"], 1.0 + float(cfg["glow"]) * 0.45)
	add_child(halo)

	# 外观：按类型使用设计稿透明 PNG（Sprite2D 替代几何原型，自转/受击反馈保留）
	_poly = Sprite2D.new()
	_poly.texture = load(tex_path)
	_poly.scale = Vector2.ONE * GameConfig.sprite_scale(_radius)
	add_child(_poly)

	# 精英头顶血条（大晶兽；BOSS 用 HUD 大血条，小晶怪无血条保持割草速度感）
	# 真机可读性：放大 150x11 + 亮描边，受击时显示 3s 后隐藏（原 120x8 恒显小条手机上看不清）
	if p_monster_id == "big":
		_hp_bar = ProgressBar.new()
		_hp_bar.custom_minimum_size = Vector2(150, 11)
		_hp_bar.min_value = 0
		_hp_bar.max_value = max_hp
		_hp_bar.show_percentage = false
		_hp_bar.size = Vector2(150, 11)
		_hp_bar.position = Vector2(-75, -_radius - 30.0)
		_hp_bar.visible = false
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.08, 0.12, 0.80)
		bg.border_color = Color(0.85, 0.75, 1.0, 0.85)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(3)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.72, 0.5, 1.0)
		fill.set_corner_radius_all(3)
		_hp_bar.add_theme_stylebox_override("background", bg)
		_hp_bar.add_theme_stylebox_override("fill", fill)
		add_child(_hp_bar)

	# BOSS 招式组件（仅本体；分裂小体由 make_split_child 创建后不挂招式）
	if is_boss and not is_split_child:
		var action_script := preload("res://scripts/combat/boss_action.gd")
		boss_action = Node2D.new()
		boss_action.set_script(action_script)
		add_child(boss_action)
		boss_action.setup(self)


## 分裂小体初始化（boss_action 生成：按本体比例缩血量/体型/经验，无招式无奖励）
func make_split_child(owner_hp_ratio: float) -> void:
	is_split_child = true
	is_boss = false
	max_hp *= owner_hp_ratio
	hp = max_hp
	xp_value = maxf(5.0, xp_value * 0.15)
	_radius *= 0.72
	contact_damage *= 0.6
	_poly.scale = Vector2.ONE * GameConfig.sprite_scale(_radius)
	# 碰撞半径与光环不动（重生成成本高，视觉以贴图缩小为准）


func _physics_process(delta: float) -> void:
	if not alive or player == null:
		return
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	# 受击闪白：贴图模式用 modulate 提亮衰减（替代原 shader flash 参数）
	var f := _flash
	var tint := Color(1.0 + 2.2 * f, 1.0 + 2.2 * f, 1.0 + 2.2 * f)
	if invulnerable:
		# 分裂期本体：半透明无敌态
		tint = Color(tint.r * 0.7, tint.g * 0.7, tint.b, 0.45)
	elif armor_hp > 0.0 and armor_reduction > 0.0:
		# 有甲期：冷蓝色调（破甲后恢复本色 → 脆弱期可辨识）
		tint = Color(tint.r * 0.72, tint.g * 0.85, tint.b * 1.15)
	_poly.modulate = tint
	_kb_vel = _kb_vel.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
	_poly.rotation += _spin * delta

	# 破甲脆弱期计时：到期护甲恢复
	if armor_reduction > 0.0 and armor_hp <= 0.0 and fragile_left > 0.0:
		fragile_left -= delta
		if fragile_left <= 0.0:
			armor_hp = _armor_max()

	# 精英头顶血条显示窗口递减（受击 3s 后隐藏）
	if _hp_show_time > 0.0:
		_hp_show_time -= delta
		if _hp_show_time <= 0.0 and _hp_bar != null:
			_hp_bar.visible = false

	# 自动寻路：向玩家移动（SDS 3.2）+ 冲刺斩速度
	var dir := (player.position - position).normalized()
	position += (dir * speed + _kb_vel + dash_vel) * delta

	# 接触伤害：持续重叠期间按冷却周期扣血
	if _contact_timer <= 0.0:
		for area in get_overlapping_areas():
			if area.is_in_group("player"):
				area.take_damage(contact_damage)
				_contact_timer = contact_cd
				break


## 护甲壳满额（恢复用）
func _armor_max() -> float:
	for act in GameConfig.BOSSES.get(monster_id, {}).get("actions", []):
		if String(act.get("id", "")) == "armor":
			return float(act.get("armor_hp", 0.0))
	return 0.0


## 受伤：damage 伤害量；kdir/kforce 击退方向与力度；chain_level 死因连锁层数（爆炸击杀时 >0）
func take_damage(damage: float, kdir := Vector2.ZERO, kforce := 0.0, chain_level := 0) -> void:
	if not alive or invulnerable:
		return
	_flash = 1.0
	if kdir != Vector2.ZERO:
		_kb_vel = kdir * kforce

	# 护甲壳（晶甲巨兽）：有甲期本体承伤 40%，甲池承受全额；破甲后脆弱期全额承伤
	if armor_reduction > 0.0:
		if armor_hp > 0.0:
			armor_hp -= damage
			hp -= damage * (1.0 - armor_reduction)
			if armor_hp <= 0.0:
				armor_hp = 0.0
				fragile_left = _fragile_time()
				_flash = 1.5
		else:
			hp -= damage
	else:
		hp -= damage

	if _hp_bar != null and hp < max_hp:
		_hp_show_time = 3.0            # 受击刷新显示窗口
		_hp_bar.visible = true
		_hp_bar.value = maxf(0.0, hp)
	if hp <= 0.0:
		die(chain_level)


func _fragile_time() -> float:
	for act in GameConfig.BOSSES.get(monster_id, {}).get("actions", []):
		if String(act.get("id", "")) == "armor":
			return float(act.get("fragile_time", 10.0))
	return 0.0


## 死亡：发事件（EffectManager 负责碎裂引爆连锁，DropManager 负责掉落），并解锁图鉴
func die(chain_level := 0) -> void:
	if not alive:
		return
	alive = false
	# chain_level 随事件传递：爆炸链中死亡的怪物会以更高层级再次爆炸（先写 meta 再发事件）
	set_meta("chain_level", chain_level)
	# 立即关闭碰撞，防止本帧后续伤害继续命中
	collision_layer = 0
	collision_mask = 0
	set_deferred("monitoring", false)
	GameData.unlock_monster(monster_id)
	GameEvents.monster_killed.emit(self)
	queue_free()
