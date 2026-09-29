extends Node
## 全局事件总线（Autoload 单例）
## 各模块之间通过信号解耦：怪物/掉落/特效/技能/UI 互不持有引用，只收发事件。

# ---- 战斗 ----
signal monster_killed(monster)              # 怪物死亡（monster: Monster，含死因 chain_level）
signal xp_gained(amount)                    # 拾取晶粒获得经验
signal chain_triggered(combo)               # 连锁爆炸滚动连击数变化
signal player_damaged(hp, max_hp)           # 玩家受伤
signal player_healed(hp, max_hp)            # 玩家回复
signal boss_defeated                        # BOSS 被击败
signal shot_fired                           # 玩家发射晶刺（阶段4：音效）
signal projectile_hit                       # 晶刺命中怪物（阶段4：音效）
signal boss_spawned                         # BOSS 出场（阶段4：音效）
# ---- 补给（V0.8 任务书模块A）----
signal supply_picked(kind: String, value: float)   # 补给拾取（HUD 反馈：弹种进化条/回复/护盾/磁吸）
signal airdrop_arrived                      # 空投落点已生成（HUD 弹字"补给空投 已抵达"）

# ---- 流程 ----
signal run_started                          # 一局开始
signal level_up(level)                      # 玩家升级
signal skill_chosen(skill_id)               # 升级面板选择了技能
signal run_finished(won, stats)             # 一局结束（won: 是否通关，stats: 结算数据字典）
