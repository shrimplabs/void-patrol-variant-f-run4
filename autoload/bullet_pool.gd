extends Node
## BulletPool -- autoload that hands out pre-allocated Bullets to avoid
## per-shot allocation spikes during play. The same `bullet.tscn` is used
## for both player and enemy factions; the pool tags each acquired bullet
## with the right faction via `setup()`.
##
## API:
##   acquire(faction: String, spawn_position: Vector2,
##           parent: Node, speed_override: float = -1.0) -> Bullet
##       Returns a Bullet added to `parent`, with faction/direction/colour
##       already configured. If no free bullet is available, instantiates
##       a new one from `bullet_scene` (lazy-loaded on _ready).
##   release(bullet: Bullet) -> void
##       Removes the bullet from the scene tree and pushes it onto the
##       per-faction free-list so the next acquire reuses it.
##   get_stats() -> Dictionary
##       Returns per-faction {alive, free, total} counts for QA / tests.
##
## The autoload exposes itself as `BulletPool` (no `class_name` to avoid
## colliding with the autoload identifier).

const DEFAULT_BULLET_SCENE := "res://scenes/bullet.tscn"

@export var bullet_scene: PackedScene

var _free: Dictionary = {"player": [], "enemy": []}
var _stats: Dictionary = {
	"player": {"alive": 0, "free": 0, "total": 0},
	"enemy": {"alive": 0, "free": 0, "total": 0},
}


func _ready() -> void:
	if bullet_scene == null:
		bullet_scene = load(DEFAULT_BULLET_SCENE)


# Cleanup hook. When the autoload is torn down at process exit, the
# `_free` array still references the pooled Bullet Nodes (we detach
# them from the scene tree on `release()` so a recycled bullet isn't
# parented to its previous shooter). The bullets themselves are still
# real Node instances with RIDs and ObjectDB slots -- without this
# hook they would leak past process exit. We free them explicitly in
# `_exit_tree()` (the autoload's last hook before its own Node is
# destroyed). We don't have to worry about double-freeing because
# `_free` is the only place that holds detached bullets.
func _exit_tree() -> void:
	for faction_name in _free.keys():
		var free_list: Array = _free[faction_name]
		for b: Node in free_list:
			if is_instance_valid(b):
				b.free()
		free_list.clear()


func acquire(
	faction: String,
	spawn_position: Vector2,
	parent: Node,
	speed_override: float = -1.0,
) -> Node:
	if parent == null:
		push_warning("BulletPool.acquire: parent is null; cannot add bullet")
		return null
	if not _free.has(faction):
		_free[faction] = []
	var free_list: Array = _free[faction]
	var bullet: Node = null
	# Pop until we find a still-valid bullet, or the list is empty. The free
	# list can contain stale references if a bullet was queue_freed externally
	# (e.g. its parent was queue_freed in a test before the bullet was
	# released back to the pool). Those must be discarded.
	# NOTE: keep `candidate` UNTYPED. `free_list.pop_back()` returns a Variant;
	# if the underlying Node has been freed, assigning to `var candidate: Node`
	# throws "Trying to assign invalid previously freed instance" before the
	# `is_instance_valid` check below can run. The untyped local lets the
	# check work as intended.
	while not free_list.is_empty():
		var candidate = free_list.pop_back()
		if is_instance_valid(candidate):
			bullet = candidate
			break
	if bullet == null:
		bullet = _instantiate_bullet()
		if bullet == null:
			return null
	parent.add_child(bullet)
	if bullet.has_method("setup"):
		bullet.setup(faction, spawn_position, speed_override)
	else:
		# Fallback for any non-Bullet script that still uses speed/direction.
		bullet.faction = faction
		bullet.global_position = spawn_position
	if "pool" in bullet:
		bullet.pool = self
	_stats[faction]["alive"] = int(_stats[faction]["alive"]) + 1
	_refresh_stats(faction, free_list)
	return bullet


func release(bullet: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	var faction_name: String = "player"
	if "faction" in bullet:
		faction_name = str(bullet.faction)
	if not _free.has(faction_name):
		_free[faction_name] = []
	var free_list: Array = _free[faction_name]
	var parent := bullet.get_parent()
	if parent:
		parent.remove_child(bullet)
	free_list.append(bullet)
	_stats[faction_name]["alive"] = max(0, int(_stats[faction_name]["alive"]) - 1)
	_refresh_stats(faction_name, free_list)


## Total bullets ever allocated for `faction` (alive + free). Useful in QA
## assertions to confirm a "no allocation" pool reuse path.
func get_total(faction: String) -> int:
	return int(_stats.get(faction, {}).get("total", 0))


## Per-faction alive/free/total snapshot for the StateServer / tests.
func get_stats() -> Dictionary:
	return _stats.duplicate(true)


func _instantiate_bullet() -> Node:
	if bullet_scene == null:
		bullet_scene = load(DEFAULT_BULLET_SCENE)
	if bullet_scene == null:
		push_warning("BulletPool: bullet scene failed to load; cannot spawn")
		return null
	return bullet_scene.instantiate()


func _refresh_stats(faction: String, free_list: Array) -> void:
	_stats[faction]["free"] = free_list.size()
	_stats[faction]["total"] = int(_stats[faction]["alive"]) + free_list.size()
