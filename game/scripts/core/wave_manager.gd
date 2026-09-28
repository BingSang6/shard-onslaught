class_name WaveManager
extends Node2D
## 波次闯关管理器（《波次闯关制·BOSS设计任务书》实现要点 2）
## 状态机：RUNNING（本关进行）→ CLEARED → TRANSITION（关间 3s + 补给空投）→ 下一关
##   - 普通/精英波：spawner 沿用刷怪曲线，按本关 mix 比例出怪，时限到 → 过关
##   - BOSS 关：暂停常规刷怪、单刷 BOSS，BOSS 被击破 → 过关（时限到 BOSS 逃脱，同样过关不卡流程）
##   - 第 10 关结束 = 通关（all_waves_cleared → main 走胜利结算）
## 注意：由 main._process 驱动 update()（升级/结算时树已 paused，自然停表）。

enum State { RUNNING, TRANSITION, DONE }

signal wave_started(wave: int, cfg: Dictionary)             # 一关开始（含第 1 关）
signal wave_cleared(wave: int)                              # 一关结束（时限到或 BOSS 击破）
signal transition_started(next_wave: int, duration: float)  # 关间过渡开始（HUD 倒数/空投提示）
signal all_waves_cleared                                    # 第 10 关过关 = 通关

var current_wave := 0          # 1~10（0 = 尚未开始）
var wave_time_left := 0.0      # 本关剩余时限
var state := State.DONE
var run_elapsed := 0.0         # 全局累计时长（结算"存活"展示用）

var spawner: MonsterSpawner = null
var drop_manager = null        # 补给空投钩子（《战斗循环增强任务书》掉落系统）
var player: Node2D = null

var _boss: Monster = null
var _transition_left := 0.0


## 开局重置并立即进入第 1 关
func reset(p_player: Node2D, p_spawner: MonsterSpawner, p_drop_manager = null) -> void:
	player = p_player
	spawner = p_spawner
	drop_manager = p_drop_manager
	current_wave = 0
	run_elapsed = 0.0
	_boss = null
	spawner.reset(p_player)
	_begin_wave(1)


## 停表（结算/调试）
func stop() -> void:
	state = State.DONE
	if spawner != null:
		spawner.stop()


## 每帧推进（由 main._process 调用）
func update(delta: float) -> void:
	match state:
		State.RUNNING:
			run_elapsed += delta
			wave_time_left -= delta
			if _is_boss_wave():
				if _boss_defeated():
					_clear_wave()
				elif wave_time_left <= 0.0:
					_despawn_boss()   # 时限到 BOSS 逃脱（无奖励），同样过关
					_clear_wave()
			elif wave_time_left <= 0.0:
				_clear_wave()
		State.TRANSITION:
			run_elapsed += delta
			_transition_left -= delta
			if _transition_left <= 0.0:
				_begin_wave(current_wave + 1)
		State.DONE:
			pass


## 当前关配置（WaveConfig）
func current_cfg() -> Dictionary:
	if current_wave < 1 or current_wave > GameConfig.WAVE_TABLE.size():
		return {}
	return GameConfig.WAVE_TABLE[current_wave - 1]


## 本关 BOSS 实例（HUD 血条轮询用；非 BOSS 关为 null）
func get_boss() -> Monster:
	return _boss


func _is_boss_wave() -> bool:
	return current_cfg().get("type", "normal") == "boss"


func _boss_defeated() -> bool:
	return _boss == null or not is_instance_valid(_boss) or not _boss.alive


func _begin_wave(wave: int) -> void:
	var cfg: Dictionary = GameConfig.WAVE_TABLE[wave - 1]
	current_wave = wave
	wave_time_left = float(cfg.get("duration", 30.0))
	state = State.RUNNING

	if cfg.get("type", "normal") == "boss":
		spawner.stop()                        # BOSS 关：暂停常规刷怪
		spawner.set_wave_mix({})
		_spawn_boss(String(cfg.get("boss_id", "boss1")))
	else:
		_boss = null
		spawner.set_wave_mix(cfg.get("mix", {}))
		spawner.enabled = true                # 普通波/精英波：沿用刷怪导演
	wave_started.emit(wave, cfg)


func _clear_wave() -> void:
	var wave := current_wave
	wave_time_left = 0.0
	if spawner != null:
		spawner.stop()                        # 过渡期停常规刷怪（喘息窗口）
	_boss = null
	wave_cleared.emit(wave)

	if wave >= GameConfig.WAVE_COUNT:
		state = State.DONE
		all_waves_cleared.emit()              # 第 10 关过关 = 通关
		return

	state = State.TRANSITION
	_transition_left = GameConfig.WAVE_TRANSITION
	# 补给空投：下一关带 airdrop 标记 → 过渡期掉落补给（任务书关 4/6/8 事件）
	var next_cfg: Dictionary = GameConfig.WAVE_TABLE[wave]
	if next_cfg.get("airdrop", false):
		_airdrop()
	transition_started.emit(wave + 1, GameConfig.WAVE_TRANSITION)


## BOSS 出场：生成点离玩家保持距离（防贴脸），沿 spawner 通用入口（monster.gd BOSSES 分支）
func _spawn_boss(boss_id: String) -> void:
	var pos := _pick_boss_pos()
	_boss = spawner.spawn_monster(boss_id, pos)
	GameEvents.boss_spawned.emit()


func _despawn_boss() -> void:
	if _boss != null and is_instance_valid(_boss) and _boss.alive:
		_boss.queue_free()                    # 逃脱：不发 monster_killed（无掉落/无奖励）
	_boss = null


func _airdrop() -> void:
	if drop_manager != null and drop_manager.has_method("airdrop"):
		drop_manager.airdrop()


## BOSS 出生点：场地内随机取离玩家 ≥380 的点，多次失败退化最远角
func _pick_boss_pos() -> Vector2:
	var arena := Rect2(Vector2.ZERO, GameConfig.ARENA_SIZE)
	for i in 10:
		var pos := Vector2(
			randf_range(120.0, arena.size.x - 120.0),
			randf_range(120.0, arena.size.y - 120.0)
		)
		if player.position.distance_to(pos) >= 380.0:
			return pos
	var corners := [arena.position, arena.end, Vector2(arena.end.x, 0), Vector2(0, arena.end.y)]
	var best: Vector2 = corners[0]
	for c in corners:
		if player.position.distance_to(c) > player.position.distance_to(best):
			best = c
	return best
