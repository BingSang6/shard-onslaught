class_name GameConfig
## 全局数值配置（单一事实来源）
## 对齐 PRD「原型数值表」与「2.2 技能列表」，调数值只改这里。

# ---- 对局 ----
const RUN_TIME := 180.0                     # 单局倒计时（秒），存活到 0 即通关
const ARENA_SIZE := Vector2(1000, 1800)     # 晶洞场地尺寸（世界坐标）
const MAX_MONSTERS := 60                    # 同屏怪物上限（WebGL 性能保护）
const MAX_MONSTERS_ELITE := 45              # 精英关同屏上限（V0.8 B3：密度硬兜底防满屏）
const MAX_CHAIN := 8                        # 连锁爆炸最大层数（防无限递归卡死）
const SPAWN_MIN_DIST := 280.0               # 怪物生成点离玩家的最小距离（防出生贴脸）

# ---- 玩家 ----
const PLAYER := {
	"max_hp": 100.0,
	"speed": 270.0,
	"attack": 8.0,               # 晶刺基础伤害
	"fire_interval": 0.8,        # 晶刺发射间隔（秒）
	"projectile_speed": 350.0,   # 晶刺飞行速度（px/s）
	"target_range": 520.0,       # 自动索敌范围
	"pick_radius": 90.0,         # 晶粒磁吸半径
	"hit_iframe": 0.35,          # 受击无敌帧（秒）
}

# ---- 怪物（PRD 2.3 / 原型数值表）----
const MONSTERS := {
	"small": {
		"name": "小晶怪", "sides": 3, "radius": 16.0, "hp": 12.0, "speed": 70.0,
		"xp": 5.0, "contact_damage": 8.0, "color": Color("6fe8f5"), "glow": 1.35,
		"contact_cd": 0.9,
	},
	"big": {
		"name": "大晶兽", "sides": 5, "radius": 26.0, "hp": 40.0, "speed": 35.0,
		"xp": 20.0, "contact_damage": 14.0, "color": Color("8a6cf5"), "glow": 1.5,
		"contact_cd": 1.1,
	},
	"boss": {
		"name": "晶核BOSS", "sides": 6, "radius": 52.0, "hp": 200.0, "speed": 25.0,
		"xp": 100.0, "contact_damage": 25.0, "color": Color("7b3df0"), "glow": 1.8,
		"contact_cd": 1.4,
	},
}

# ---- 掉落（晶粒）----
const DROP := {
	"pickup_dist": 22.0,         # 判定拾取的距离
	"max_drops": 110,            # 场上晶粒上限，超出后最旧的自动飞向玩家回收
	"magnet_accel": 1500.0,      # 磁吸加速度
	"pop_speed": 130.0,          # 掉落弹出初速度
	"lifetime": 25.0,            # 晶粒最长存在时间
}

# ---- BOSS 刷新（SDS 3.7：120 秒固定触发；波次制下由 WAVE_TABLE 驱动，此值仅旧模式兜底）----
const BOSS_SPAWN_TIME := 120.0

# ================= 波次闯关制（《波次闯关制·BOSS设计任务书》）=================
# 10 关：普通波/精英波沿用刷怪导演曲线（mix 控制出怪比例），BOSS 关暂停常规刷怪单刷 BOSS
const WAVE_TABLE := [
	# min_interval=刷怪间隔下限（峰值兜底防满屏）；big_cap=大兽同屏上限（满额转小怪）
	{"wave": 1,  "type": "normal", "duration": 30.0, "mix": {"small": 1.0}, "min_interval": 0.55, "big_cap": 0},
	# V0.8 任务书 B2：真机反馈"满屏堵路"根因关 → 大兽 65%→40% 穿插 + 峰值兜底 0.50s + 大兽同屏 ≤8
	{"wave": 2,  "type": "elite",  "duration": 30.0, "mix": {"small": 0.60, "big": 0.40}, "min_interval": 0.50, "big_cap": 8},
	{"wave": 3,  "type": "boss",   "duration": 60.0, "boss_id": "boss1"},
	{"wave": 4,  "type": "elite",  "duration": 35.0, "mix": {"small": 0.5, "big": 0.5}, "min_interval": 0.45, "big_cap": 10, "airdrop": true},
	{"wave": 5,  "type": "boss",   "duration": 60.0, "boss_id": "boss2"},
	{"wave": 6,  "type": "elite",  "duration": 35.0, "mix": {"small": 0.45, "big": 0.55}, "min_interval": 0.42, "big_cap": 12, "airdrop": true},
	{"wave": 7,  "type": "boss",   "duration": 60.0, "boss_id": "boss3"},
	{"wave": 8,  "type": "elite",  "duration": 40.0, "mix": {"small": 0.35, "big": 0.65}, "min_interval": 0.40, "big_cap": 14, "airdrop": true},
	{"wave": 9,  "type": "boss",   "duration": 60.0, "boss_id": "boss4"},
	{"wave": 10, "type": "boss",   "duration": 90.0, "boss_id": "boss5"},
]
const WAVE_TRANSITION := 3.0   # 关间过渡秒数（补给空投窗口）
const WAVE_COUNT := 10         # 总关数（通关判定）

# ---- 关内周期空投（V0.8 任务书模块A：普通/精英关进行中按间隔投放；BOSS 关 1 次）----
const AIRDROP_TABLE := {
	"normal_interval": 20.0,        # 普通波空投间隔（秒）
	"elite_interval": 18.0,         # 精英波空投间隔（秒）
	"boss_count": 1,                # BOSS 关空投次数
	"boss_delay": 3.0,              # BOSS 关开场多久投放（秒）
	"drop_count": [1, 1, 2, 2],     # 关内每次空投数量池（60% 1 个 / 40% 2 个）
	"min_dist": 320.0,              # 关内落点距玩家（需走位获取，不贴脸白送）
	"max_dist": 420.0,
	"lifetime": 20.0,               # 空投补给存在秒数（与 SupplyDrop 默认一致，过期消失）
	"warn_time": 0.8,               # 落点光圈预警秒数（光圈结束后补给实体出现）
	"weights": {"heal": 0.35, "weapon": 0.35, "magnet": 0.20, "shield": 0.10},      # 关内空投池
	"transition_count": [2, 2, 3, 3],   # 关间过渡空投数量（2~3 个，喘息窗口给足补给感）
	"transition_weights": {"heal": 0.45, "weapon": 0.30, "magnet": 0.15, "shield": 0.10},
	"transition_min_dist": 140.0,   # 关间落点（过渡期无怪，贴脸方便拾取）
	"transition_max_dist": 280.0,
}

# ---- 5 BOSS（数值严格按任务书第二节；TTK 校准信号：<15s 血量×1.3，>50s ×0.75）----
# 招式 id 语义（boss_action.gd 消费）：fan=扇形晶刺 / pulse=扩散冲击环 / summon=召唤 /
# dash_charge=冲刺斩 / split=分裂合并 / armor=护甲壳 / quake=震地波+飞溅 /
# vortex_drop=敌方引力漩涡 / spiral=旋臂扫射 / rain=全屏晶雨 / phases=阶段表(主宰)
const BOSSES := {
	"boss1": {
		"name": "碎晶王", "tex": "res://assets/boss/boss1_crystal_king.png",
		"radius": 80.0, "hp": 400.0, "speed": 60.0, "contact_damage": 12.0,
		"xp": 150.0, "color": Color("7b3df0"), "glow": 2.0, "contact_cd": 1.4,
		"reward": {"core": 15, "heal": 30.0, "buff_attack": 6.0, "buff_time": 20.0},
		"actions": [
			{"id": "fan", "cooldown": 3.5, "count": 5, "spread_deg": 50.0, "proj_speed": 320.0, "damage": 12.0},
			{"id": "pulse", "cooldown": 7.0, "radius": 300.0, "damage": 12.0},
			{"id": "summon", "cooldown": 15.0, "count": 3, "monster": "small"},
		],
	},
	"boss2": {
		"name": "晶刺猎手", "tex": "res://assets/boss/boss2_blade_hunter.png",
		"radius": 72.0, "hp": 800.0, "speed": 220.0, "contact_damage": 18.0,
		"xp": 200.0, "color": Color("35e6ff"), "glow": 2.1, "contact_cd": 1.0,
		"reward": {"core": 20, "buff_attack": 8.0, "buff_time": 20.0},
		"actions": [
			{"id": "dash_charge", "cooldown": 4.0, "dash_speed": 350.0, "trail_damage": 5.0},
			{"id": "split", "trigger_hp": 0.5, "child_ratio": 0.25, "merge_time": 8.0, "merge_heal": 0.4},
		],
	},
	"boss3": {
		"name": "晶甲巨兽", "tex": "res://assets/boss/boss3_armor_behemoth.png",
		"radius": 95.0, "hp": 1600.0, "speed": 45.0, "contact_damage": 22.0,
		"xp": 300.0, "color": Color("8a6cf5"), "glow": 2.0, "contact_cd": 1.5,
		"reward": {"core": 30, "max_hp": 20.0},
		"actions": [
			{"id": "armor", "armor_hp": 300.0, "reduction": 0.6, "fragile_time": 10.0},
			{"id": "quake", "cooldown": 6.0, "count": 8, "proj_speed": 260.0, "damage": 15.0},
		],
	},
	"boss4": {
		"name": "引力魔核", "tex": "res://assets/boss/boss4_vortex_core.png",
		"radius": 85.0, "hp": 2600.0, "speed": 80.0, "contact_damage": 15.0,
		"xp": 400.0, "color": Color("b56cff"), "glow": 2.2, "contact_cd": 1.2,
		"reward": {"core": 40, "fire_buff": 0.15, "buff_time": 30.0},
		"actions": [
			{"id": "vortex_drop", "cooldown": 8.0, "count": 2, "radius": 120.0, "pull": 180.0, "duration": 4.0},
			{"id": "spiral", "cooldown": 5.0, "count": 12, "proj_speed": 300.0, "damage": 15.0},
		],
	},
	"boss5": {
		"name": "晶洞主宰", "tex": "res://assets/boss/boss5_dominator.png",
		"radius": 105.0, "hp": 4200.0, "speed": 50.0, "contact_damage": 28.0,
		"xp": 800.0, "color": Color("d24df5"), "glow": 2.4, "contact_cd": 1.5,
		"reward": {"core": 80, "double_core": true},
		"actions": [
			# 三阶段由 phase_hp_ratios 驱动：各阶段启用对应招式（phases 内 cooldown 覆盖 actions 默认）
			{"id": "fan", "cooldown": 4.0, "count": 6, "spread_deg": 60.0, "proj_speed": 320.0, "damage": 18.0},
			{"id": "summon", "cooldown": 12.0, "count": 2, "monster": "small"},
			{"id": "vortex_drop", "cooldown": 8.0, "count": 1, "radius": 120.0, "pull": 180.0, "duration": 5.0},
			{"id": "quake", "cooldown": 8.0, "count": 8, "proj_speed": 260.0, "damage": 20.0},
			{"id": "rain", "cooldown": 6.0, "count": 12, "waves": 2, "wave_interval": 0.8, "proj_speed": 300.0, "damage": 20.0},
			{"id": "split", "trigger_hp": 0.33, "child_ratio": 0.3, "merge_time": 8.0, "merge_heal": 0.0},
		],
		"phase_hp_ratios": [1.0, 0.66, 0.33],   # 阶段1：fan+summon；阶段2：+vortex+quake；阶段3：+rain+split
	},
}
# 主宰各阶段启用的招式 id（其余 BOSS 为空 = 全程启用全部招式）
const BOSS5_PHASE_ACTIONS := [
	["fan", "summon"],
	["fan", "summon", "vortex_drop", "quake"],
	["rain", "split", "summon"],
]

# ================= 战斗循环增强（《战斗循环增强任务书》）=================
# ---- 掉落补给（计数伪随机 + 类型权重 + 残血保护 + 上限回收 + 稀有保底）----
const DROP_TABLE := {
	"small_chance": 0.05,          # 小怪击杀掉补给概率（2%~12%）
	"big_chance": 0.15,            # 大兽击杀掉补给概率（8%~25%）
	"rare_chance": 0.20,           # 稀有（弹种道具）单独判定（10%~30%）
	"max_drops": 8,                # 场上补给上限（4~16）
	"heal_amount": 20.0,           # 血包回复量（10~30）
	"magnet_duration": 6.0,        # 磁石全屏磁吸秒数（4~10）
	"pity_count": 30,              # 连续无稀有保底计数（20~45）
	"weapon_duration": 8.0,        # 弹种道具临时弹种秒数
	"shield_max": 3,               # 护盾碎片层数上限
	"weights": {"heal": 0.60, "magnet": 0.25, "shield": 0.15},  # 普通（非稀有）类型权重
	"low_hp_ratio": 0.30,          # 残血保护阈值（HP<30%）
	"low_hp_heal_mult": 3.0,       # 残血时血包权重倍率
}

# ---- 弹种系统（6 弹种；default = 现状单发，不改变无弹种行为）----
const WEAPON_TYPES := {
	"default": {"name": "单发晶刺", "damage_mult": 1.0, "count": 1, "spread_deg": 0.0,
		"speed": 350.0, "pierce": 0, "homing": 0.0, "blast_radius": 0.0, "color": Color("35e6ff")},
	"pierce":  {"name": "穿透晶刺", "damage_mult": 0.85, "count": 1, "spread_deg": 0.0,
		"speed": 400.0, "pierce": 2, "homing": 0.0, "blast_radius": 0.0, "color": Color("7dfff0")},
	"triple":  {"name": "三连发",   "damage_mult": 0.6, "count": 3, "spread_deg": 15.0,
		"speed": 320.0, "pierce": 0, "homing": 0.0, "blast_radius": 0.0, "color": Color("9fe8ff")},
	"spread":  {"name": "散射",     "damage_mult": 0.5, "count": 5, "spread_deg": 40.0,
		"speed": 300.0, "pierce": 0, "homing": 0.0, "blast_radius": 0.0, "color": Color("bffcff")},
	"homing":  {"name": "追踪",     "damage_mult": 0.8, "count": 1, "spread_deg": 0.0,
		"speed": 280.0, "pierce": 0, "homing": 3.0, "blast_radius": 0.0, "color": Color("ff9fe8")},
	"heavy":   {"name": "巨型晶刺", "damage_mult": 2.2, "count": 1, "spread_deg": 0.0,
		"speed": 260.0, "pierce": 0, "homing": 0.0, "blast_radius": 24.0, "color": Color("d24df5")},
}
# 弹种卡等级 → 伤害系数倍率（Lv1=1.0 / Lv2=1.15 / Lv3=1.3）
static func weapon_lv_mult(lv: int) -> float:
	return 1.0 + 0.15 * (lv - 1.0)

# ---- PNG 素材（素材替换指南：主体直径约占画布 900/2048，含半透明辉光；画布可为任意分辨率）----
const ASSET_SRC_DIAMETER := 2048.0  # 素材原始画布边长（sprite_scale 换算基准）
const ASSET_BODY_DIAMETER := 900.0  # 画布内主体直径。视觉整改V2：1430→900 放大1.59x（原主体35-55px细节丢失）

## 按碰撞半径换算 Sprite2D 缩放（Sprite2D 默认 1px = 1 世界单位；
## 若实机视觉偏大/偏小，微调 ASSET_BODY_DIAMETER，碰撞半径不改）
## tex_size=素材实际边长：显示尺寸与素材分辨率无关（缩图/换图不改变屏上大小）
static func sprite_scale(radius: float, tex_size := ASSET_SRC_DIAMETER) -> float:
	return radius * 2.0 / (ASSET_BODY_DIAMETER * tex_size / ASSET_SRC_DIAMETER)

# ---- 后处理泛光（Bloom：亮部模糊提亮叠加；性能紧张时把 intensity 调 0 即关闭）----
const BLOOM := {
	"intensity": 0.95,        # 叠加强度
	"threshold": 0.34,        # 视觉整改V3：0.42→0.34 泛光晕染更宽        # 亮部阈值（越低泛光范围越大）
	"radius_uv": 0.014,       # 模糊半径（占屏幕高度比例）
}

# ---- 局外永久强化（PRD 2.4：4 项，消耗晶核升级，跨局生效）----
# 费用曲线：cost = base_cost + cost_step × 当前等级；满级后不可再升
const PERM_UPGRADES := {
	"hp": {
		"name": "初始血量", "desc": "每级 +5 初始生命值",
		"max_lv": 5, "base_cost": 30, "cost_step": 20, "bonus_per_lv": 5.0,
		"color": Color("7dffca"), "sides": 4,
	},
	"attack": {
		"name": "初始攻击", "desc": "每级 +2 晶刺基础伤害",
		"max_lv": 5, "base_cost": 40, "cost_step": 25, "bonus_per_lv": 2.0,
		"color": Color("ffb36b"), "sides": 3,
	},
	"pick_range": {
		"name": "拾取范围", "desc": "每级 +20 晶粒磁吸半径",
		"max_lv": 5, "base_cost": 25, "cost_step": 15, "bonus_per_lv": 20.0,
		"color": Color("9fe8ff"), "sides": 6,
	},
	"start_skill": {
		"name": "开局技能", "desc": "每局开始时获得 1 级随机技能（一次性解锁）",
		"max_lv": 1, "base_cost": 120, "cost_step": 0, "bonus_per_lv": 0.0,
		"color": Color("c79bff"), "sides": 5,
	},
	# V0.8 任务书模块C：弹速进化（绝对增量统一附加到所有弹种，保留弹种手感差异）
	"bullet_speed": {
		"name": "弹速进化", "desc": "每级 晶刺飞行速度 +40",
		"max_lv": 5, "base_cost": 35, "cost_step": 20, "bonus_per_lv": 40.0,
		"color": Color("35e6ff"), "sides": 4,
	},
}


## 永久强化升到 next_lv（= 当前等级 + 1）所需的晶核
static func perm_upgrade_cost(key: String, cur_lv: int) -> int:
	var cfg: Dictionary = PERM_UPGRADES.get(key, {})
	return int(cfg.get("base_cost", 0)) + int(cfg.get("cost_step", 0)) * cur_lv

# ---- 经验曲线（战斗循环增强：8+5→14+9 拉陡，弹窗打断约 -35%）----
static func xp_to_next(level: int) -> float:
	return 14.0 + float(level - 1) * 9.0


# ---- 技能（PRD 2.2：8 个技能，升级随机 3 选 1，可重复获取升级）----
const SKILL_MAX_LV := 5

const SKILLS := {
	"ricochet":     {"name": "晶刺弹射", "desc": "晶刺击中怪物后弹射到下一只怪物", "color": Color("35e6ff"), "sides": 4, "active": false},
	"shatter_blast": {"name": "碎裂引爆", "desc": "怪物死亡时爆炸，碎片命中其他怪物引发连锁爆炸", "color": Color("bffcff"), "sides": 6, "active": false},
	"aura":         {"name": "晶域扩散", "desc": "环绕玩家的持续环形伤害场，切割靠近的怪物", "color": Color("22e6c0"), "sides": 8, "active": true},
	"shield":       {"name": "晶盾", "desc": "周期性生成护盾，抵挡一次伤害", "color": Color("7df3ff"), "sides": 6, "active": true},
	"dash":         {"name": "瞬闪位移", "desc": "向移动方向短距冲刺闪避，冲刺期间无敌", "color": Color("ffffff"), "sides": 3, "active": false},
	"fire_rate":    {"name": "高速结晶", "desc": "提升晶刺发射频率", "color": Color("9fe8ff"), "sides": 3, "active": false},
	"heavy_spike":  {"name": "晶刺增重", "desc": "提升晶刺伤害与击退效果", "color": Color("9922dd"), "sides": 4, "active": false},
	"vortex":       {"name": "引力漩涡", "desc": "周期性生成引力场，将怪物吸向中心聚集", "color": Color("b56cff"), "sides": 5, "active": true},
	# ---- 弹种卡（战斗循环增强：习得后切换弹种，Lv3 封顶；再学同卡=强化）----
	"pierce":       {"name": "穿透晶刺", "desc": "晶刺获得穿透，可洞穿 2 个目标", "color": Color("7dfff0"), "sides": 4, "active": false, "max_lv": 3, "weapon": "pierce"},
	"triple":       {"name": "三连发",   "desc": "一次发射 3 枚晶刺，扇形覆盖", "color": Color("9fe8ff"), "sides": 3, "active": false, "max_lv": 3, "weapon": "triple"},
	"spread":       {"name": "散射",     "desc": "一次发射 5 枚晶刺，大范围清群", "color": Color("bffcff"), "sides": 5, "active": false, "max_lv": 3, "weapon": "spread"},
	"homing":       {"name": "追踪晶刺", "desc": "晶刺自动追踪最近的怪物", "color": Color("ff9fe8"), "sides": 6, "active": false, "max_lv": 3, "weapon": "homing"},
	"heavy":        {"name": "巨型晶刺", "desc": "巨型晶刺，命中后范围爆炸", "color": Color("d24df5"), "sides": 8, "active": false, "max_lv": 3, "weapon": "heavy"},
}


## 各等级技能参数（供玩家/投射物/特效/技能节点查询）
static func skill_params(skill_id: String, lv: int) -> Dictionary:
	match skill_id:
		"ricochet":
			return {"bounces": mini(lv, 4), "bounce_range": 250.0 + 40.0 * lv, "falloff": 0.78}
		"shatter_blast":
			# 基础伤害 14 保证 Lv1 爆炸可击杀 12 血小晶怪，连锁能自续传播
			return {"radius": 80.0 + 14.0 * lv, "damage": 14.0 + 5.0 * lv}
		"aura":
			return {"radius": 85.0 + 18.0 * lv, "dps": 8.0 + 4.0 * lv, "tick": 0.25}
		"shield":
			return {"cooldown": maxf(6.5, 12.0 - 1.2 * lv)}
		"dash":
			return {"cooldown": maxf(2.2, 5.0 - 0.5 * lv), "distance": 150.0 + 35.0 * lv, "duration": 0.16, "iframe": 0.22}
		"fire_rate":
			return {"interval_mult": 1.0 / (1.0 + 0.15 * lv)}
		"heavy_spike":
			return {"damage_mult": 1.0 + 0.22 * lv, "knockback": 60.0 + 45.0 * lv}
		"vortex":
			return {"cooldown": 7.0, "duration": 3.0 + 0.25 * lv, "radius": 130.0 + 25.0 * lv, "pull": 180.0 + 60.0 * lv}
	# ---- 弹种卡参数：弹种 id + 等级伤害倍率（Lv1=1.0/Lv2=1.15/Lv3=1.3）----
	var weapon_ids := ["pierce", "triple", "spread", "homing", "heavy"]
	if weapon_ids.has(skill_id):
		return {"weapon": skill_id, "damage_mult_extra": weapon_lv_mult(lv)}
	return {}


## 生成正 N 边形顶点（半径 radius，起始朝上）
static func regular_polygon_points(sides: int, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## 生成圆形扇面顶点（中心在原点，供 Shader 做距离场）
static func circle_points(radius: float, segments := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


## 程序生成菱形碎片贴图（GPUParticles2D 的多边形碎片外观，零外部资源）
static func diamond_texture(size := 15) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size - 1) / 2.0
	for y in size:
		for x in size:
			# 曼哈顿距离菱形：边缘 1px 抗锯齿过渡
			var d := absf(float(x) - c) + absf(float(y) - c)
			var a := clampf(c + 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
