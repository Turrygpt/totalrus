extends RefCounted
static var totals := {}
static var enabled := "--time-scripts" in OS.get_cmdline_user_args()
static func add(key: String, started: int) -> void:
	totals[key] = totals.get(key,0)+Time.get_ticks_usec()-started
