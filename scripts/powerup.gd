extends Area2D
class_name Powerup

## A power-up pickup. Drifts down from a defeated enemy. Auto-collects on
## contact with the player. Applies its effect via `main.apply_powerup()`.
##
## Six kinds:
##   DOUBLE_SHOT   yellow  15s   two parallel bullets per fire
##   TRIPLE_SPREAD orange  12s   three fans (center + 2 angled) per fire
##   LASER         red      8s   continuous fire, infinite pierce
##   SHIELD_BOOST  blue     0s   instant +50% shield
##   SPEED_BOOST   green   10s   ×1.4 move speed
##   BOMB          purple   0s   instant clear-all-bullets + 2 dmg to all enemies
##
## Drop chance: when a fighter or bomber dies, ~25% chance to drop one.
## Drones do not drop power-ups (drones are too easy).

signal collected(powerup: Node)
signal expired(powerup: Node)

enum Kind {
	DOUBLE_SHOT = 0,
	TRIPLE_SPREAD = 1,
	LASER = 2,
	SHIELD_BOOST = 3,
	SPEED_BOOST = 4,
	BOMB = 5,
}

## Drop chance from fighter/bomber kills.
const DROP_CHANCE := 0.25
## Drift speed (px/s) -- slow enough that the player can chase it.
const FALL_SPEED := 80.0
## Hard cap on how long a powerup may live (s) so off-screen powerups don't
## accumulate. Sized for "twice the viewport height" at fall speed.
const MAX_LIFETIME := 12.0

## Per-kind metadata. Indexed by Kind. Used by both the pickup (visual/
## duration) and the player (effect dispatch). Keep stable: tests assert
## specific colors / durations / names.
const TYPE_DATA := {
	Kind.DOUBLE_SHOT: {
		"color": Color(1.00, 0.92, 0.20, 1.0),
		"duration": 15.0,
		"name": "DOUBLE SHOT",
		"shot_type": "double",
		"is_shot_type": true,
	},
	Kind.TRIPLE_SPREAD: {
		"color": Color(1.00, 0.60, 0.15, 1.0),
		"duration": 12.0,
		"name": "TRIPLE SPREAD",
		"shot_type": "triple",
		"is_shot_type": true,
	},
	Kind.LASER: {
		"color": Color(1.00, 0.25, 0.25, 1.0),
		"duration": 8.0,
		"name": "LASER",
		"shot_type": "laser",
		"is_shot_type": true,
	},
	Kind.SHIELD_BOOST: {
		"color": Color(0.25, 0.55, 1.00, 1.0),
		"duration": 0.0,
		"name": "SHIELD BOOST",
		"shot_type": "",
		"is_shot_type": false,
	},
	Kind.SPEED_BOOST: {
		"color": Color(0.25, 0.95, 0.40, 1.0),
		"duration": 10.0,
		"name": "SPEED BOOST",
		"shot_type": "",
		"is_shot_type": false,
	},
	Kind.BOMB: {
		"color": Color(0.85, 0.35, 1.00, 1.0),
		"duration": 0.0,
		"name": "BOMB",
		"shot_type": "",
		"is_shot_type": false,
	},
}

@export var kind: int = Kind.DOUBLE_SHOT
## Drift speed in pixels/sec; exposed so tests can fast-forward without
## sleeping.
@export var fall_speed: float = FALL_SPEED
## Whether this pickup has a timed effect. Computed from kind in _ready,
## but exposed for tests that build the node directly.
@export var has_timed_effect: bool = false

var _lifetime: float = 0.0
var _collected: bool = false


func _ready() -> void:
	add_to_group("powerup")
	add_to_group("powerups")
	_apply_visual()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		# Make the notifier's rect explicit so screen_exited fires reliably
		# even when the spawned powerup is small / off-screen.
		notifier.rect = Rect2(-12, -12, 24, 24)
		notifier.screen_exited.connect(_on_screen_exited)


## Configure the powerup for a given kind. Called by the pool / spawner
## when handing out a powerup. Safe to call after _ready.
func setup(kind_value: int) -> void:
	kind = kind_value
	_apply_visual()


func _apply_visual() -> void:
	if not TYPE_DATA.has(kind):
		return
	var data: Dictionary = TYPE_DATA[kind]
	has_timed_effect = float(data.get("duration", 0.0)) > 0.0
	var color: Color = data.get("color", Color(1, 1, 1, 1))
	var visual := get_node_or_null("Visual")
	if visual is CanvasItem:
		(visual as CanvasItem).modulate = color


func _physics_process(delta: float) -> void:
	if _collected:
		return
	position.y += fall_speed * delta
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_on_screen_exited()


func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body == null:
		return
	if not body.is_in_group("player"):
		return
	_collected = true
	# SFX: pickup chime. Fires only on player pickup (not screen-exit).
	# We resolve the AudioManager via the safe absolute-path lookup so
	# this script works in headless / no-autoload contexts.
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play"):
		am.call("play", "pickup")
	_apply_effect(body)
	collected.emit(self)
	# queue_free is unsafe here because body_entered is a physics callback:
	# Godot forbids removing a CollisionObject (this Area2D) while inside a
	# physics tick. Use call_deferred so the free happens after the tick
	# completes. Same fix applied to _on_screen_exited below.
	call_deferred("queue_free")


func _on_screen_exited() -> void:
	if _collected:
		return
	expired.emit(self)
	call_deferred("queue_free")


## Hand the effect off to the Main scene. The powerup itself does not
## implement the effect -- it just routes the kind to the right handler.
##
## We resolve "Main" by walking up to the SceneTree root and looking for a
## node with `apply_powerup()`. This avoids hard-coding a parent path so
## the powerup can be tested under any root.
func _apply_effect(player: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.root
	if root == null:
		return
	var main: Node = null
	# The Main scene is the first sibling of autoloads that implements
	# apply_powerup(). We check parents first (in case the powerup is
	# parented under a holder / test fixture that delegates upward) and
	# then fall back to a root scan.
	var p: Node = get_parent()
	while p != null:
		if p.has_method("apply_powerup"):
			main = p
			break
		p = p.get_parent()
	if main == null:
		for child in root.get_children():
			if child.has_method("apply_powerup"):
				main = child
				break
	if main != null and main.has_method("apply_powerup"):
		main.apply_powerup(kind, player, self)


## Public: type name for HUD/UI display.
func get_type_name() -> String:
	if not TYPE_DATA.has(kind):
		return "POWERUP"
	return str(TYPE_DATA[kind].get("name", "POWERUP"))


## Public: short shot-type token ("single"/"double"/"triple"/"laser") for
## the player to switch on. Empty for non-shot pickups.
func get_shot_type() -> String:
	if not TYPE_DATA.has(kind):
		return ""
	return str(TYPE_DATA[kind].get("shot_type", ""))


## Public: the duration in seconds. 0 means instant (no timer).
func get_duration() -> float:
	if not TYPE_DATA.has(kind):
		return 0.0
	return float(TYPE_DATA[kind].get("duration", 0.0))


## Public: whether this kind is a shot-type (mutually exclusive with other
## shot-types). Non-shot powerups can coexist with each other and with
## a shot-type powerup.
func is_shot_type() -> bool:
	if not TYPE_DATA.has(kind):
		return false
	return bool(TYPE_DATA[kind].get("is_shot_type", false))


## All six kinds, in stable order. Used by random-pick helpers and tests.
static func all_kinds() -> Array:
	return [
		Kind.DOUBLE_SHOT, Kind.TRIPLE_SPREAD, Kind.LASER,
		Kind.SHIELD_BOOST, Kind.SPEED_BOOST, Kind.BOMB,
	]


## Static helper: should this drop roll succeed?
## `roll` is expected in [0, 1). Tests can pass deterministic values to
## assert branch coverage without seeding the global RNG.
static func should_drop(roll: float) -> bool:
	return roll < DROP_CHANCE


## Snapshot for the StateServer / tests.
func get_state() -> Dictionary:
	return {
		"kind": kind,
		"type_name": get_type_name(),
		"duration": get_duration(),
		"is_shot_type": is_shot_type(),
		"position": [global_position.x, global_position.y],
		"collected": _collected,
	}
