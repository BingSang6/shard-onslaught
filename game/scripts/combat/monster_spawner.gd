class_name MonsterSpawner
extends Node2D
## 刷怪导演（SDS 3.7 + 波次闯关制）：
## - 刷怪速率随时间递增（全局累计曲线上强度，跨关不重置）
## - 出怪类型：波次制下由 wave_manager 按关表 mix 比例下发；无 mix 时回落到自带权重曲线
## - BOSS 刷新改由 wave_manager 驱动（BOSS 关 enabled=false，本类不再自行刷 BOSS）
## - 生成点离玩家保持最小距离（防出生贴脸秒杀）；同屏上限 MAX_MONSTERS

var player: Node2D = null
var enabled := false
var elapsed := 0.0
var wave_mix := {}                    # 波次出怪比例（如 {"small":0.5,"big":0.5}；空=自带曲线）

var _spawn_cd := 0.0


func reset(p_player: Node2D) -> void:
	player = p_player
	enabled = true
	elapsed = 0.0
	_spawn_cd = 0.8
	wave_mix = {}


func stop() -> void:
	enabled = false


## 设置本关出怪比例（wave_manager 每关下发；传空恢复自带曲线）
func set_wave_mix(mix: Dictionary) -> void:
	wave_mix = mix


func _physics_process(delta: float) -> void:
	if not enabled or player == null:
		return
	elapsed += delta

	if get_tree().get_nodes_in_group("monsters").size() >= GameConfig.MAX_MONSTERS:
		return  # 同屏上限保护

	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = _current_interval()
		# 批量：1 → 6（步进 30s，保证中段 60~120s 怪群密度足以支撑大连锁高光）
		var batch := 1 + int(elapsed / 30.0)
		for i in batch:
			if get_tree().get_nodes_in_group("monsters").size() >= GameConfig.MAX_MONSTERS:
				break
			spawn_monster(_roll_type(), _pick_spawn_pos())


## 刷怪间隔曲线：1.15s → 0.22s，幂曲线（指数 0.78）让中段更早收紧
func _current_interval() -> float:
	var t := clampf(elapsed / GameConfig.RUN_TIME, 0.0, 1.0)
	return lerpf(1.15, 0.22, pow(t, 0.78))


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
