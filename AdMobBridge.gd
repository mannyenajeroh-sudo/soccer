extends Node

# ============================================================
#  AdMobBridge.gd — STREET 3 ELITE Autoload
#  Stub: override with real AdMob plugin on Android.
# ============================================================

signal reward_earned(type: String, amount: int)

func is_ready() -> bool:
	return false

func show_rewarded_ad() -> void:
	# In real build: call AdMob plugin here
	await get_tree().create_timer(1.5).timeout
	reward_earned.emit("coins", 1)
