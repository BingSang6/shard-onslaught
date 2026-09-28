extends Node2D
## 技能：晶盾（主动·生存）
## 周期性生成护盾抵挡一次伤害（Player.take_damage → SkillManager.consume_shield → 这里）。
## 视觉：玩家周身青白色光环，有盾时可见；被击破时闪爆消散。

var skills: Node = null                     # SkillManager 引用（由其注入）

var _has_charge := false
var _cd_timer := 0.0
var _pop_t := 0.0                           # 队伍被击破后的闪光倒计时


func _physics_process(delta: float) -> void:
	if skills == null or skills.player == null:
		return
	var lv: int = skills.get_level("shield")
	if lv <= 0:
		return
	position = skills.player.position

	if not _has_charge:
		_cd_timer -= delta
		if _cd_timer <= 0.0:
			_has_charge = true
	_pop_t = maxf(0.0, _pop_t - delta * 3.0)
	queue_redraw()


## 消耗一次护盾；无盾返回 false（伤害照常结算）
func consume() -> bool:
	if not _has_charge:
		return false
	_has_charge = false
	var lv: int = maxi(1, skills.get_level("shield"))
	_cd_timer = GameConfig.skill_params("shield", lv)["cooldown"]
	_pop_t = 1.0
	return true


func _draw() -> void:
	if skills == null or skills.player == null or skills.get_level("shield") <= 0:
		return
	if _has_charge:
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.7 + 0.3 * sin(t * 4.0)
		var r := 34.0 + 2.0 * sin(t * 4.0)
		var col := Color(0.55, 0.95, 1.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col, 0.25 * pulse), 8.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col, 0.8 * pulse), 2.5, true)
	elif _pop_t > 0.0:
		# 护盾击破闪光：快速扩散消散
		var t := 1.0 - _pop_t
		var col := Color(0.85, 1.0, 1.0)
		draw_arc(Vector2.ZERO, 34.0 + t * 26.0, 0.0, TAU, 40, Color(col, _pop_t * 0.9), 5.0 * _pop_t, true)
