extends Node
## 程序化音频管理器（Autoload 单例，阶段4）
## 启动时用 GDScript 合成全部音效/BGM 为 AudioStreamWAV（零外部音频文件，延续项目风格）。
## 接线方式：监听 GameEvents 信号（战斗/流程音）；开火/命中/BOSS/按钮在源头 emit。
## 总线：SFX（12 路播放池）+ Music（BGM 循环）；静音开关持久化到 GameData。

const MIX_RATE := 44100
const SFX_POOL_SIZE := 12

# 音效样本表（id -> AudioStreamWAV），_ready 时合成填充
var _samples := {}
# SFX 播放池
var _pool: Array[AudioStreamPlayer] = []
# BGM 播放器
var _bgm_player: AudioStreamPlayer
# 节流表（id -> 上次播放的毫秒时间戳）
var _last_play := {}
# 兜底动态创建的总线名（布局文件提供的总线不在此列，退出时不清理）
var _dynamic_buses: Array[String] = []
# 节流间隔（毫秒）：高频音效防刷屏
const THROTTLE := {"shot": 45, "hit": 60, "xp": 60, "click": 40, "kill": 25}


func _ready() -> void:
	_build_buses()
	_build_samples()
	_build_pool()
	_connect_events()
	_apply_mute(GameData.muted)
	# BGM 合成量大（~130 万样本），延迟一帧执行避免拖启动
	_start_bgm_deferred.call_deferred()
	# V0.8.4 Web 无声根因修复：升级/结算面板会 get_tree().paused = true（main.gd），
	# 本单例原先随树暂停 → 引擎给所有播放器下 stream_paused；Web 导出上 Sample 播放
	# 的暂停是 AudioBufferSourceNode.stop()，恢复路径损坏（实测节点永久 isPaused=true，
	# 手动 _unpause 后立即恢复发声），首次弹面板后全局静音——桌面原生路径不受影响。
	# PROCESS_MODE_ALWAYS 让播放器不随树暂停：面板期间 BGM/按钮音继续播（本就是惯例），
	# 同时彻底绕开该引擎 bug。
	process_mode = Node.PROCESS_MODE_ALWAYS


# 看门狗帧计数（每 30 帧查一次播放器 stream_paused，防引擎/平台路径再度挂起）
var _wd_frames := 0


func _process(_delta: float) -> void:
	# V0.8.4 兜底：Web 上 Sample 播放的恢复路径若再被其它路径弄断（节点卡 isPaused），
	# 引擎侧对应 AudioStreamPlayer.stream_paused 会停在 true——每半秒巡检一次，
	# 树未暂停时强制拉回 false，保证不再出现"游戏在跑却全场静音"。
	_wd_frames += 1
	if _wd_frames % 30 != 0:
		return
	if get_tree().paused:
		return
	if _bgm_player != null and _bgm_player.stream_paused:
		_bgm_player.stream_paused = false
	for p in _pool:
		if p.stream_paused:
			p.stream_paused = false


func _exit_tree() -> void:
	# 退出时停播、断开 stream 引用并移除动态总线，避免 ObjectDB 泄漏警告
	for p in _pool:
		p.stop()
		p.stream = null
	if _bgm_player != null:
		_bgm_player.stop()
		_bgm_player.stream = null
	_samples.clear()
	# V0.8.4：只移除兜底动态创建的总线；布局文件的总线生命周期归引擎管
	for bus_name in _dynamic_buses:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.remove_bus(idx)
	_dynamic_buses.clear()


# ================= 总线与播放器 =================

func _build_buses() -> void:
	# V0.8.4：总线优先由 default_bus_layout.tres 预定义（随包加载、语义与桌面一致）；
	# 此处仅兜底：布局未加载（如裸跑测试场景）时才动态创建，
	# 并记录进 _dynamic_buses 以便退出清理。
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
		_dynamic_buses.append(bus_name)


func _build_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	add_child(_bgm_player)


# ================= 事件接线（战斗/流程音全走 GameEvents） =================

func _connect_events() -> void:
	GameEvents.monster_killed.connect(_on_monster_killed)
	GameEvents.xp_gained.connect(func(_a): play("xp"))
	GameEvents.chain_triggered.connect(func(combo): play("chain", 0.0, 1.0 + 0.055 * mini(int(combo), 16)))
	GameEvents.player_damaged.connect(func(_hp, _m): play("hurt"))
	GameEvents.player_healed.connect(func(_hp, _m): play("heal"))
	GameEvents.boss_defeated.connect(func(): play("boss_kill"))
	GameEvents.boss_spawned.connect(func(): play("boss_spawn"))
	GameEvents.shot_fired.connect(func(): play("shot"))
	GameEvents.projectile_hit.connect(func(): play("hit"))
	GameEvents.run_started.connect(func(): play("start"))
	GameEvents.level_up.connect(func(_lv): play("levelup"))
	GameEvents.skill_chosen.connect(func(_id): play("choose"))
	GameEvents.run_finished.connect(func(won, _s): play("win" if won else "lose"))


func _on_monster_killed(m: Node) -> void:
	# 连锁层级越深音调越高（连击爽感反馈）
	var lv := int(m.get_meta("chain_level", 0))
	play("kill", 0.0, 1.0 + 0.06 * lv)


# ================= 播放接口 =================

## 播放音效：池内取空闲播放器复用；带节流配置的高频音效在间隔内忽略。
## vol_db 为相对样本默认响度的增减；pitch 变速变调（连锁连击音高递增用）。
func play(sfx_id: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _samples.has(sfx_id):
		return
	var now := Time.get_ticks_msec()
	if THROTTLE.has(sfx_id) and _last_play.has(sfx_id):
		if now - int(_last_play[sfx_id]) < int(THROTTLE[sfx_id]):
			return
	_last_play[sfx_id] = now
	var p := _acquire_player()
	if p == null:
		return
	p.stream = _samples[sfx_id]
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.1, pitch + randf_range(-0.03, 0.03))
	p.play()


func _acquire_player() -> AudioStreamPlayer:
	# 优先空闲；全忙则偷最早开始的那路（短音效覆盖无感知损失）
	var victim: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			return p
		if victim == null or p.get_playback_position() > victim.get_playback_position():
			victim = p
	return victim


func _start_bgm_deferred() -> void:
	_samples["bgm"] = _build_bgm()
	_bgm_player.stream = _samples["bgm"]
	_bgm_player.volume_db = -6.0
	_bgm_player.play()


## 静音切换（主菜单按钮调用）：总线 mute + 存档。返回切换后的状态。
func toggle_mute() -> bool:
	GameData.muted = not GameData.muted
	GameData.save_game()
	_apply_mute(GameData.muted)
	return GameData.muted


func _apply_mute(muted: bool) -> void:
	var idx_sfx := AudioServer.get_bus_index("SFX")
	var idx_music := AudioServer.get_bus_index("Music")
	if idx_sfx >= 0:
		AudioServer.set_bus_mute(idx_sfx, muted)
	if idx_music >= 0:
		AudioServer.set_bus_mute(idx_music, muted)


# ================= 样本合成（合成函数返回 PackedFloat32Array，统一 _to_wav 封装） =================

func _build_samples() -> void:
	_samples["shot"] = _to_wav(_sweep(900.0, 300.0, 0.09, "sine", 0.55))
	_samples["hit"] = _to_wav(_hit_v2())
	_samples["kill"] = _to_wav(_shatter_v2())
	_samples["chain"] = _to_wav(_mix([_sweep(880.0, 1320.0, 0.07, "sine", 0.5),
			_sweep(1320.0, 1980.0, 0.06, "sine", 0.35)]))
	_samples["xp"] = _to_wav(_mix([_tone_at(2093.0, 0.06, 0.4, 0.0), _tone_at(4186.0, 0.05, 0.15, 0.0)]))
	_samples["hurt"] = _to_wav(_sweep(150.0, 75.0, 0.22, "square", 0.5))
	_samples["heal"] = _to_wav(_mix([_tone_at(523.25, 0.28, 0.3, 0.02), _tone_at(659.25, 0.28, 0.25, 0.02)]))
	_samples["dash"] = _to_wav(_sweep_noise(400.0, 3200.0, 0.14, 0.35))
	_samples["levelup"] = _to_wav(_arpeggio([440.0, 554.37, 659.25, 880.0], 0.09, 0.45))
	_samples["choose"] = _to_wav(_mix([_tone_at(1760.0, 0.07, 0.4, 0.0), _noise_burst(0.03, 0.2)]))
	_samples["start"] = _to_wav(_sweep(220.0, 880.0, 0.25, "triangle", 0.4))
	_samples["boss_spawn"] = _to_wav(_tremble(55.0, 0.7, 6.0, 0.55))
	_samples["boss_kill"] = _to_wav(_mix([_boom(0.55), _noise_burst(0.3, 0.4)]))
	_samples["win"] = _to_wav(_melody([[440.0, 0.14], [554.37, 0.14], [659.25, 0.14], [880.0, 0.4]], 0.45))
	_samples["lose"] = _to_wav(_melody([[329.63, 0.3], [246.94, 0.5]], 0.4))
	_samples["click"] = _to_wav(_tone_at(1200.0, 0.035, 0.35, 0.0))
	_samples["buy"] = _to_wav(_melody([[1318.5, 0.07], [1760.0, 0.1]], 0.45))


## 单音：freq 恒定正弦，attack/指数衰减包络。delay 为起始偏移秒。
func _tone_at(freq: float, dur: float, vol: float, delay: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var start := int(delay * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n + start)
	var phase := 0.0
	var inc := TAU * freq / MIX_RATE
	for i in n:
		var t := float(i) / n
		var env := minf(float(i) / (0.005 * MIX_RATE), 1.0) * exp(-3.5 * t)
		out[start + i] = sin(phase) * vol * env
		phase += inc
	return out


## 扫频：freq_start → freq_end（指数插值），可选波形与衰减速率。
func _sweep(f0: float, f1: float, dur: float, wave: String, vol: float, decay := 2.8) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := f0 * pow(f1 / f0, t)
		phase += TAU * freq / MIX_RATE
		var env := minf(float(i) / (0.004 * MIX_RATE), 1.0) * exp(-decay * t)
		out[i] = _wave(phase, wave) * vol * env
	return out


## 白噪脉冲（打击/碎裂点缀）
func _noise_burst(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	for i in n:
		var t := float(i) / n
		out[i] = (rng.randf() * 2.0 - 1.0) * vol * exp(-6.0 * t)
	return out


## 带通扫频噪声（瞬闪呼啸）
func _sweep_noise(f0: float, f1: float, dur: float, vol: float) -> PackedFloat32Array:
	# 用单极点状态变量滤波近似带通：截止频率随时间上扫
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := f0 * pow(f1 / f0, t)
		var f := 2.0 * sin(PI * minf(cutoff, MIX_RATE * 0.45) / MIX_RATE)
		var input := rng.randf() * 2.0 - 1.0
		lp += f * bp
		bp += f * (input - lp - 1.2 * bp)
		out[i] = bp * vol * sin(PI * t) * 1.6  # 中段最响
	return out


## 高通白噪（一阶差分）：清脆的"嚓/渣"质感，区别于闷软的原噪
func _hp_noise(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		var x := rng.randf() * 2.0 - 1.0
		var hp := (x - prev) * 0.5  # 一阶差分 = 高通
		prev = x
		out[i] = hp * vol * exp(-14.0 * t)
	return out


## 打击音 V2.1：低频冲击体 + 中频"哒" + 高频瞬态（收紧高频，去刺耳）
func _hit_v2() -> PackedFloat32Array:
	var layers: Array[PackedFloat32Array] = []
	# 1) 低频冲击体（thump）：130→55Hz 下扫正弦，28ms，给冲击"重量"
	layers.append(_sweep(130.0, 55.0, 0.028, "sine", 0.65, 5.0))
	# 2) 中频"哒"：三角波 950→500Hz 下扫 40ms（比方波柔，保留形体）
	layers.append(_sweep(950.0, 500.0, 0.04, "triangle", 0.30, 9.0))
	# 3) 高频瞬态：高通噪 18ms，电平收敛（锐但不刺）
	layers.append(_hp_noise(0.018, 0.34))
	return _mix(layers)


## 玻璃碎裂 V2.1：破裂瞬态 + 钟声谐波碎片簇（柔化）+ 轻渣噪
func _shatter_v2() -> PackedFloat32Array:
	var layers: Array[PackedFloat32Array] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	# 1) 破裂瞬态：中低频冲击 + 宽频噪爆（"啪"，稍收敛）
	layers.append(_sweep(180.0, 60.0, 0.05, "sine", 0.5, 6.0))
	layers.append(_noise_burst(0.035, 0.45))
	# 2) 碎片"叮"簇：钟声谐波（无锯齿毛刺），频段下移、数量减密
	for k in 7:
		var f0 := 1300.0 + rng.randf() * 3000.0      # 1300~4300Hz
		var f1 := f0 * (0.74 + rng.randf() * 0.18)   # 下滑至 74~92%
		var d := 0.05 + rng.randf() * 0.05           # 50~100ms
		var delay := rng.randf() * 0.08              # 0~80ms 错落
		layers.append(_shard(f0, f1, d, 0.15 + rng.randf() * 0.10, delay))
	# 3) 玻璃渣洒落：高通噪（电平/时长收敛，柔收尾）
	layers.append(_hp_noise(0.12, 0.18))
	return _mix(layers)


## 单枚碎片：钟声谐波结构（基音+2/3 次泛音，圆润"叮"而非锯齿毛刺）
func _bell_wave(phase: float) -> float:
	return sin(phase) + 0.4 * sin(2.0 * phase) + 0.18 * sin(3.0 * phase)


## 单枚碎片：带起始延迟的下滑扫频、极快衰减 = 清脆"叮"
func _shard(f0: float, f1: float, dur: float, vol: float, delay: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var start := int(delay * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n + start)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := f0 * pow(f1 / f0, t)
		phase += TAU * freq / MIX_RATE
		out[start + i] = _bell_wave(phase) * vol * exp(-13.0 * t) / 1.58
	return out


## 低频颤音（BOSS 出场）：基频 + AM 调制
func _tremble(freq: float, dur: float, am_hz: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var inc := TAU * freq / MIX_RATE
	var am_inc := TAU * am_hz / MIX_RATE
	for i in n:
		var t := float(i) / n
		phase += inc
		var am := 0.6 + 0.4 * sin(am_inc * i)
		out[i] = _wave(phase, "saw") * vol * am * exp(-1.8 * t)
	return out


## 爆轰（BOSS 击杀）：低频下坠大衰减
func _boom(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := 90.0 * pow(0.4, t)  # 90 → 36Hz 下坠
		phase += TAU * freq / MIX_RATE
		var env := minf(float(i) / (0.003 * MIX_RATE), 1.0) * exp(-4.0 * t)
		out[i] = sin(phase) * 0.7 * env
	return out


## 琶音（升级）：逐音接力，每音独立衰减
func _arpeggio(freqs: Array, note_dur: float, vol: float) -> PackedFloat32Array:
	var layers: Array[PackedFloat32Array] = []
	for k in freqs.size():
		layers.append(_tone_at(float(freqs[k]), note_dur * 1.8, vol * (0.7 + 0.1 * k), k * note_dur))
	return _mix(layers)


## 旋律（胜负/购买）：[(freq, dur)] 逐音接力
func _melody(notes: Array, vol: float) -> PackedFloat32Array:
	var layers: Array[PackedFloat32Array] = []
	var at := 0.0
	for notev in notes:
		var f: float = notev[0]
		var d: float = notev[1]
		layers.append(_tone_at(f, d * 1.9, vol, at))
		at += d
	return _mix(layers)


func _wave(phase: float, kind: String) -> float:
	match kind:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw":
			return fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		"triangle":
			return 2.0 * absf(2.0 * fposmod(phase / TAU + 0.25, 1.0) - 1.0) - 1.0
		_:
			return sin(phase)


## 多层叠加：取最长长度求和
func _mix(layers: Array) -> PackedFloat32Array:
	var length := 0
	for layer in layers:
		length = maxi(length, (layer as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(length)
	for layer in layers:
		var l: PackedFloat32Array = layer
		for i in l.size():
			out[i] += l[i]
	return out


# ================= BGM 合成（8s 循环，Am→F→C→G） =================

func _build_bgm() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(dur * MIX_RATE)
	var layers: Array[PackedFloat32Array] = []
	# 和弦配置：[根音, 三音, 五音]（Am / F / C / G，各 2 秒）
	var chords := [
		[110.0, 130.81, 164.81],
		[87.31, 110.0, 130.81],
		[65.41, 82.41, 98.0],
		[98.0, 123.47, 146.83],
	]
	# 层1：pad 长音（三角波，柔和起音）
	for c in chords.size():
		for f in chords[c]:
			layers.append(_pad_tone(float(f), 2.0, float(c) * 2.0, 0.10))
	# 层2：琶音（8 分音符，每拍 2 音 × 8 拍）
	var arp := [220.0, 261.63, 329.63, 440.0, 329.63, 261.63]
	for beat in 16:
		var freq: float = arp[beat % arp.size()]
		if beat % 8 >= 6:
			freq *= 1.5  # 尾拍上八度点缀
		layers.append(_tone_at(freq, 0.22, 0.14, beat * 0.5))
	# 层3：节拍 —— 底鼓(每拍) + 反拍气声(很轻)
	for beat in 8:
		layers.append(_kick(float(beat)))
		layers.append(_noise_burst_at(0.05, 0.05, float(beat) + 0.5))
	var mixed := _mix(layers)
	for i in mixed.size():  # 整体压限
		mixed[i] = tanh(mixed[i] * 1.2) * 0.85
	var wav := _to_wav(mixed, 0.7)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _pad_tone(freq: float, dur: float, delay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var start := int(delay * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n + start)
	var phase := 0.0
	var inc := TAU * freq / MIX_RATE
	for i in n:
		var t := float(i) / n
		var env := minf(t / 0.25, 1.0) * minf((1.0 - t) / 0.3, 1.0)  # 梯形包络
		phase += inc
		out[start + i] = _wave(phase, "triangle") * vol * env
	return out


func _kick(at_beat: float) -> PackedFloat32Array:
	var dur := 0.12
	var n := int(dur * MIX_RATE)
	var start := int(at_beat * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n + start)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var freq := 120.0 * pow(0.35, t)
		phase += TAU * freq / MIX_RATE
		out[start + i] = sin(phase) * 0.5 * exp(-7.0 * t)
	return out


func _noise_burst_at(dur: float, vol: float, delay_sec: float) -> PackedFloat32Array:
	# 反拍气声：极轻噪点（delay_sec 为秒）
	var base := _noise_burst(dur, vol)
	var start := int(delay_sec * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(base.size() + start)
	for i in base.size():
		out[start + i] = base[i]
	return out


# ================= Float32 → AudioStreamWAV =================

func _to_wav(samples: PackedFloat32Array, gain := 1.0) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
