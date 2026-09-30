class_name MonsterSpawner
extends Node2D
## 刷怪导演（SDS 3.7 + 波次闯关制 + V0.8 节奏修正）：
## - 刷怪速率按【本关进度】驱动（wave_local，每关重置——跨关不继承，防后期曲线压垮前中期关卡）
## - 峰值兜底：min_interval（关表下发）+ 每秒生成率上限（普通 2.2 / 精英 3.0）
## - 密度硬兜底：大兽同屏 big_cap 满额转小怪；精英关同屏总数 MAX_MONSTERS_ELITE
## - 出怪类型：波次制下由 wave_manager 按关表 mix 比例下发；无 mix 时回落到自带权重曲线
## - BOSS 刷新改由 wave_manager 驱动（BOSS 关 enabled=false，本类不再自行刷 BOSS）
## - 生成点离玩家保持最小距离（防出生贴脸秒杀）

var player: Node2D = null
var enabled := false
var elapsed := 0.0                    # 全局累计（结算统计/无 mix 兜底曲线用）
var wave_local := 0.0                 # 本关已过时间（每关重置——V0.8 B1 核心）
var wave_duration := 30.0             # 本关时长（wave_manager 下发）
var wave_min_interval := 0.85         # 本关刷怪间隔下限（峰值兜底，防满屏；wave_manager 每关下发）
var wave_big_cap := -1                # 大兽同屏上限（<0 = 不限制；满额转小怪）
var wave_rate_cap := 2.2              # 每秒生成率上限（普通 2.2 / 精英 3.0；兜底不常触发）
var max_monsters := 60                # 同屏总数上限（精英关由 wave_manager 下调为 MAX_MONSTERS_ELITE）
var wave_mix := {}                    # 波次出怪比例（如 {"small":0.5,"big":0.5}；空=自带曲线）

var _spawn_cd := 0.0


func reset(p_player: Node2D) -> void:
	player = p_player
	enabled = true
	elapsed = 0.0
	_spawn_cd = 0.8
	wave_mix = {}
	wave_local = 0.0
	max_monsters = GameConfig.MAX_MONSTERS


func stop() -> void:
	enabled = false


## 设置本关出怪比例（wave_manager 每关下发；传空恢复自带曲线）
func set_wave_mix(mix: Dictionary) -> void:
	wave_mix = mix


## 本关重置（V0.8 B1/B3：wave_manager 每关下发时长/峰值下限/大兽上限/生成率上限）
func reset_wave(p_duration: float, p_min_interval: float, p_big_cap := -1, p_rate_cap := 2.2) -> void:
	wave_local = 0.0
	wave_duration = maxf(1.0, p_duration)
	wave_min_interval = p_min_interval
	wave_big_cap = p_big_cap
	wave_rate_cap = p_rate_cap
	_spawn_cd = 1.0


func _physics_process(delta: float) -> void:
	if not enabled or player == null:
		return
	elapsed += delta
	wave_local += delta

	if get_tree().get_nodes_in_group("monsters").size() >= max_monsters:
		return  # 同屏上限保护

	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = _current_interval()
		# 批量：本关前 30s 单只，之后按本关进度批量（V0.8.1 实机反馈：20s 步进太快，30s 关几乎全程单只）
		var batch := 1 + int(wave_local / 30.0)
		for i in batch:
			if get_tree().get_nodes_in_group("monsters").size() >= max_monsters:
				break
			var kind := _roll_type()
			# 大兽同屏满额 → 本只转小怪（节奏不断，密度受控；V0.8 B3）
			if kind == "big" and wave_big_cap >= 0 and _count_big() >= wave_big_cap:
				kind = "small"
			spawn_monster(kind, _pick_spawn_pos())


## 刷怪间隔曲线：1.15s → 0.35s 按本关进度收紧（幂 0.78），min_interval 与生成率上限双兜底
## （V0.8.1：尾值 0.22→0.35，中期收紧更缓；实际峰值由关表 min_interval 决定）
func _current_interval() -> float:
	var t := clampf(wave_local / wave_duration, 0.0, 1.0)
	return maxf(maxf(lerpf(1.15, 0.35, pow(t, 0.78)), wave_min_interval), 1.0 / wave_rate_cap)


## 大兽同屏计数（big_cap 用）
func _count_big() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.monster_id == "big":
			n += 1
	return n


## 怪物类型：优先用波次 mix 权重（wave_manager 按关下发）；
## 无 mix 时回落自带曲线（小晶怪为主，大晶兽占比随时间 8% → 26%）
func _roll_type() -> String:
	if not wave_mix.is_empty():
		var total := 0.0
		for w in wave_mix.values():
			total += float(w)
		var roll := randf() * total
		for id in wave_mix:
			roll -= float(wave_mix[id])
			if roll <= 0.0:
				return String(id)
		return String(wave_mix.keys()[0])
	var big_chance := 0.08 + 0.18 * clampf((elapsed - 25.0) / 100.0, 0.0, 1.0)
	return "big" if randf() < big_chance else "small"


## 生成点：场地内随机，且离玩家不小于 SPAWN_MIN_DIST（多次尝试，失败退化为远角）
func _pick_spawn_pos() -> Vector2:
	var arena := Rect2(Vector2.ZERO, GameConfig.ARENA_SIZE)
	for i in 8:
		var pos := Vector2(
			randf_range(40.0, arena.size.x - 40.0),
			randf_range(40.0, arena.size.y - 40.0)
		)
		if player.position.distance_to(pos) >= GameConfig.SPAWN_MIN_DIST:
			return pos
	# 兜底：取离玩家最远的四个角之一
	var corners := [arena.position, arena.end, Vector2(arena.end.x, 0), Vector2(0, arena.end.y)]
	var best: Vector2 = corners[0]
	for c in corners:
		if player.position.distance_to(c) > player.position.distance_to(best):
			best = c
	return best


## 生成一只怪物（也供测试/调试直接调用）
func spawn_monster(monster_id: String, pos: Vector2) -> Monster:
	var m := Monster.new()
	add_child(m)
	m.setup(player, monster_id, pos)
	return m
