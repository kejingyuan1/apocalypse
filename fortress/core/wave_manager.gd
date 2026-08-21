extends RefCounted
class_name WaveManager

# 波次调度（对齐《波次系统 GDD》§3.1）
# 波次规模公式：N(w) = round(8 * 1.12^(w-1))
static func count(w: int) -> int:
	return roundi(8 * pow(1.12, w - 1))

# 入侵周期（秒）：随堡垒等级缩短（Lv1 120s -> Lv6 60s）
static func interval(lv: int) -> float:
	var table = [120, 105, 90, 78, 68, 60]   # 对齐《波次系统 GDD》§3.1 入侵周期 Lv1–6
	return table[min(lv, table.size() - 1)]

# 固定 1s tick 驱动（对齐经济/能源/波次同源 tick，ADR-004 确定性）
static func tick_seconds() -> float:
	return 1.0
