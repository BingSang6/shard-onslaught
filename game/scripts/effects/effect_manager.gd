class_name EffectManager
extends Node2D
## 特效管理器 + 连锁爆炸执行器（阶段2核心）
##
## 连锁爆炸（PRD 3.4 伪代码的队列化实现）：
##   1. 拥有「碎裂引爆」技能时，任意怪物死亡 → 入队一次爆炸（层级 = 凶手连锁层 + 1）
##   2. 每帧预算内逐个处理爆炸：粒子+冲击波 → 范围内怪物受伤
##   3. 被炸死的怪物再次入队（层级 +1），直到 MAX_CHAIN=8 截断
##   ★ 全程队列迭代而非递归调用，且每帧爆炸数有上限 → 双保险防死循环/性能尖峰
##
## 其他职责：死亡碎裂粒子、屏幕震动、连锁连击数统计、BOSS 击破特效。

const COMBO_WINDOW := 2.2                  # 连锁连击滚动窗口（秒）
const MAX_EXPLOSIONS_PER_FRAME := 16       # 每帧爆炸处理预算（性能保护）

var camera: Camera2D = null                # 由 main 注入（屏幕震动）
var flash_rect: Control = null             # 由 main 注入（UI 层全屏闪光）
var world_modulate: CanvasModulate = null  # 由 main 注入（整屏色调脉冲）
var skills: Node = null                    # SkillManager 引用

# 连锁统计
var combo_count := 0                       # 当前滚动连击数
var max_combo := 0                         # 本局最高连锁连击
var last_chain_level := 0                  # 最近一次爆炸的连锁层级（测试观测用）

var _combo_timer := 0.0
var _queue: Array[Dictionary] = []         # 待处理爆炸队列
var _shake_amp := 0.0
var _mod_pulse := 0.0                      # 整屏提亮脉冲强度（0~1）
var _burst_pool: Array[GPUParticles2D] = []
var _ring_pool: Array[RingFX] = []
var _flash_pool: Array[FlashFX] = []


# 冲击波光环：_draw 绘制的扩散圆环
class RingFX extends Node2D:
	var radius := 10.0
	var target_radius := 100.0
	var color := Color(0.7, 0.95, 1.0)
	var life := 0.0
	var duration := 0.35
	var active := false

	func _process(delta: float) -> void:
		if not active:
			return
		life += delta
		var t := clampf(life / duration, 0.0, 1.0)
		radius = lerpf(target_radius * 0.15, target_radius, t)
		if t >= 1.0:
			active = false
			visible = false
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var t := clampf(life / duration, 0.0, 1.0)
		var width := lerpf(14.0, 2.5, t)
		var col := Color(color, lerpf(0.95, 0.0, t))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, col, width, true)
		draw_arc(Vector2.ZERO, radius * 0.7, 0.0, TAU, 40, Color(col, col.a * 0.5), width * 0.5, true)


# 爆发光斑：短促的径向闪光圆（爆炸瞬间的"白闪"感）
class FlashFX extends Node2D:
	var radius := 10.0
	var target_radius := 100.0
	var color := Color(1.0, 1.0, 1.0)
	var life := 0.0
	var duration := 0.22
	var active := false

	func _process(delta: float) -> void:
		if not active:
			return
		life += delta
		var t := clampf(life / duration, 0.0, 1.0)
		radius = lerpf(target_radius * 0.2, target_radius, t)
		if t >= 1.0:
			active = false
			visible = false
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var t := clampf(life / duration, 0.0, 1.0)
		var a := 0.66 * (1.0 - t)  # 视觉整改V3：白闪强度+20%
		draw_circle(Vector2.ZERO, radius, Color(color, a))
		draw_circle(Vector2.ZERO, radius * 0.55, Color(color, a * 0.85))


func _ready() -> void:
	GameEvents.monster_killed.connect(_on_monster_killed)
	# 加法混合材质：_draw 的圆/弧以"叠光"方式输出（霓虹光溢出感的关键）
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 预生成粒子与冲击波对象池
	for i in 14:
		var p := _make_burst()
		p.visible = false
		add_child(p)
		_burst_pool.append(p)
	for i in 12:
		var r := RingFX.new()
		r.material = add_mat
		r.visible = false
		add_child(r)
		_ring_pool.append(r)
	for i in 10:
		var f := FlashFX.new()
		f.material = add_mat
		f.visible = false
		add_child(f)
		_flash_pool.append(f)


func reset() -> void:
	_queue.clear()
	combo_count = 0
	max_combo = 0
	last_chain_level = 0
	_combo_timer = 0.0
	_shake_amp = 0.0
	_mod_pulse = 0.0
	if world_modulate != null:
		world_modulate.color = Color.WHITE


# ---------------- 怪物死亡入口 ----------------

func _on_monster_killed(monster: Monster) -> void:
	if GameConfig.BOSSES.has(monster.monster_id) or monster.monster_id == "boss":
		configure_burst(monster.position, 160.0, Color(0.85, 0.65, 1.0), 90)
		_show_ring(monster.position, 240.0, Color(0.8, 0.5, 1.0))
		_show_flash(monster.position, 230.0, Color(0.9, 0.8, 1.0))
		add_shake(16.0)
		_mod_pulse = 1.0
		GameEvents.boss_defeated.emit()
	else:
		# 常规死亡碎裂小爆花（无论是否学技能都给反馈）
		configure_burst(monster.position, 38.0, Color(0.75, 0.95, 1.0), 18)
		_show_flash(monster.position, 34.0, Color(0.85, 0.97, 1.0))

	# 碎裂引爆：拥有技能才产生范围爆炸（SDS 3.2 第3条）
	if skills != null and skills.get_level("shatter_blast") > 0:
		var killer_chain: int = int(monster.get_meta("chain_level", 0))
		var level := killer_chain + 1
		if level <= GameConfig.MAX_CHAIN:
			var p := GameConfig.skill_params("shatter_blast", skills.get_level("shatter_blast"))
			_queue.append({
				"pos": monster.position,
				"radius": float(p["radius"]),
				"damage": float(p["damage"]) * level_scale(level),
				"level": level,
			})


## 连锁层级越深威力微增（连锁爽感：越炸越疼）
func level_scale(level: int) -> float:
	return 1.0 + 0.15 * float(level - 1)


# ---------------- 每帧处理爆炸队列 ----------------

func _process(delta: float) -> void:
	# 屏幕震动衰减
	if _shake_amp > 0.0 and camera != null:
		_shake_amp = maxf(0.0, _shake_amp - delta * 26.0)
		camera.offset = Vector2.from_angle(randf() * TAU) * _shake_amp
	elif camera != null:
		camera.offset = Vector2.ZERO

	# 全屏闪光衰减（UI 层 Control）
	if flash_rect != null and flash_rect.modulate.a > 0.0:
		flash_rect.modulate.a = maxf(0.0, flash_rect.modulate.a - delta * 3.5)

	# 整屏色调脉冲衰减（连锁爆炸瞬时提亮，偏青紫的高光闪动）
	if world_modulate != null:
		_mod_pulse = maxf(0.0, _mod_pulse - delta * 4.5)
		world_modulate.color = Color(
			1.0 + 0.32 * _mod_pulse, 1.0 + 0.25 * _mod_pulse, 1.0 + 0.42 * _mod_pulse
		)

	# 连击窗口
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_count = 0

	# 队列预算处理（核心：不递归、限帧量）
	var budget := MAX_EXPLOSIONS_PER_FRAME
	while not _queue.is_empty() and budget > 0:
		budget -= 1
		_process_explosion(_queue.pop_front())


func _process_explosion(exp: Dictionary) -> void:
	var pos: Vector2 = exp["pos"]
	var radius: float = exp["radius"]
	var damage: float = exp["damage"]
	var level: int = exp["level"]

	last_chain_level = level
	combo_count += 1
	_combo_timer = COMBO_WINDOW
	if combo_count > max_combo:
		max_combo = combo_count
	GameEvents.chain_triggered.emit(combo_count)

	# 视觉：白闪光斑 + 碎片粒子 + 冲击波 + 震动 + 整屏脉冲（层级越高越猛）
	var heat := float(level) / float(GameConfig.MAX_CHAIN)
	_show_flash(pos, radius * 1.3, Color(1.0, 1.0, 1.0))
	configure_burst(pos, radius, Color(1.0, 1.0, 1.0).lerp(Color(0.4, 0.95, 1.0), 1.0 - heat * 0.5), 26 + level * 6)
	_show_ring(pos, radius * 1.25, Color(0.55, 0.95, 1.0))
	add_shake(2.5 + 2.0 * level)
	_mod_pulse = minf(1.0, _mod_pulse + 0.30 + 0.07 * level)
	if combo_count >= 4 and flash_rect != null:
		flash_rect.modulate.a = minf(0.5, 0.18 + heat * 0.3)

	# 范围伤害：被炸死的怪在 die() → monster_killed → 再次入队（层级+1，受 MAX_CHAIN 截断）
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.alive:
			continue
		var d: float = pos.distance_to(m.position)
		if d <= radius + m._radius:
			var dir: Vector2 = (m.position - pos).normalized()
			m.take_damage(damage, dir, 90.0 + 30.0 * level, level)


# ---------------- 视觉：粒子池 / 冲击波 / 震动 ----------------

func add_shake(amount: float) -> void:
	_shake_amp = minf(18.0, _shake_amp + amount)


## 触发一次多边形碎片爆裂（对象池复用 GPUParticles2D）
func configure_burst(pos: Vector2, radius: float, color: Color, amount: int) -> void:
	var p: GPUParticles2D = null
	for candidate in _burst_pool:
		if not candidate.emitting:
			p = candidate
			break
	if p == null:
		p = _burst_pool[0]
	p.position = pos
	p.amount = clampi(amount, 4, 90)
	p.visible = true
	var mat := p.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = radius * 1.2
	mat.initial_velocity_max = radius * 2.6
	mat.color = color
	p.restart()


func _show_ring(pos: Vector2, target_radius: float, color: Color) -> void:
	for r in _ring_pool:
		if not r.active:
			r.position = pos
			r.target_radius = target_radius
			r.color = color
			r.life = 0.0
			r.radius = target_radius * 0.15
			r.active = true
			r.visible = true
			return


## 爆发光斑（对象池）：短促径向闪光
func _show_flash(pos: Vector2, target_radius: float, color: Color) -> void:
	for f in _flash_pool:
		if not f.active:
			f.position = pos
			f.target_radius = target_radius
			f.color = color
			f.life = 0.0
			f.radius = target_radius * 0.2
			f.active = true
			f.visible = true
			return


## 构建碎片爆裂粒子节点：多边形碎片 draw pass（菱形网格）+ 全向爆散
func _make_burst() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.5
	p.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0                       # 全向爆散
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 160.0
	mat.angular_velocity_min = -540.0
	mat.angular_velocity_max = 540.0
	mat.scale_min = 0.5
	mat.scale_max = 1.3
	mat.color = Color(0.75, 0.95, 1.0)
	p.process_material = mat
	# 多边形碎片外观（PRD 2.6）：程序生成的菱形贴图，零外部资源
	p.texture = GameConfig.diamond_texture(15)
	return p
