extends Node2D
class_name Explosion
## Particle explosion used when enemies / the player / powerups are
## destroyed. Two visual variants:
##
##   SIZE_SMALL  -- drones / bullets / generic small impacts. ~16
##                  particles, short lifetime, single orange/yellow tint.
##   SIZE_LARGE  -- bombers, boss, victory. ~48 particles, longer
##                  lifetime, mixed orange/red/white tints.
##
## The node owns a `CPUParticles2D` child built in code (so a test can
## construct an Explosion with `Explosion.new() + setup(...)` and
## assert on the particle config without depending on the .tscn).
##
## Lifecycle: after `setup(size)`, particles emit for ~0.6-0.9s. We
## set `emitting = false` after one shot via `one_shot = true` and
## queue_free once all particles have died. A hard cap (5s) acts as a
## safety net for the case where `finished` signal never fires
## (e.g. CPUParticles2D is not visually emitting under headless mode).
##
## API:
##   setup(size: int) -> void  # SIZE_SMALL (0) or SIZE_LARGE (1)
##   particle_count() -> int
##   is_emitting() -> bool
##   is_finished() -> bool

## Particle-count variants.
const SIZE_SMALL := 0
const SIZE_LARGE := 1

## Default lifetime cap (safety net for headless / non-emitting runs).
const LIFETIME_CAP := 5.0

## Visual config per size. Kept as constants so tests can pin them.
const SMALL_PARTICLE_COUNT := 16
const SMALL_LIFETIME := 0.6
const SMALL_INITIAL_VELOCITY_MIN := 60.0
const SMALL_INITIAL_VELOCITY_MAX := 160.0
const SMALL_COLOR := Color(1.0, 0.65, 0.20, 1.0)

const LARGE_PARTICLE_COUNT := 48
const LARGE_LIFETIME := 0.9
const LARGE_INITIAL_VELOCITY_MIN := 80.0
const LARGE_INITIAL_VELOCITY_MAX := 280.0
const LARGE_COLOR := Color(1.0, 0.45, 0.18, 1.0)

## The size this explosion was set up with. -1 = not yet configured.
var size: int = -1
## CPUParticles2D child. Created in _ready so the .tscn can also use
## the same script (the .tscn doesn't pre-create the particles).
var _particles: CPUParticles2D = null
## Hard lifetime cap. Once exceeded, the explosion queue_frees itself
## even if the `finished` signal hasn't fired.
var _age: float = 0.0
## Cached scale at which this explosion was set up, for the get_state()
## snapshot.
var _scale_factor: float = 1.0


func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.name = "Particles"
	_particles.emitting = false
	_particles.one_shot = true
	# Auto-free on the `finished` signal so a normal play session
	# doesn't leave explosions lingering in the tree.
	_particles.finished.connect(_on_particles_finished)
	add_child(_particles)
	# If the caller set `size` before adding to the tree (the common
	# pattern in main.spawn_explosion), apply the config now.
	if size >= 0:
		_apply_size(size)
		_start_emitting()


## Configure this explosion for the given size. Must be called before
## the node is added to the tree OR after _ready fires. Either way,
## particles are emitted for the configured lifetime and the node
## queue_frees itself when they finish.
func setup(size_value: int) -> void:
	size = size_value
	if _particles != null:
		_apply_size(size)
		_start_emitting()


## Set the visual scale of the entire explosion (e.g. boss is 1.5x
## larger than a bomber). Default 1.0.
func set_explosion_scale(value: float) -> void:
	_scale_factor = max(0.1, value)
	if _particles != null:
		_particles.scale_amount_min = _scale_factor
		_particles.scale_amount_max = _scale_factor


## Public: number of particles this explosion will spawn. Returns 0
## before setup() is called.
func particle_count() -> int:
	if _particles == null:
		return 0
	return int(_particles.amount)


## Public: are particles currently being emitted?
func is_emitting() -> bool:
	if _particles == null:
		return false
	return bool(_particles.emitting)


## Public: have all particles finished AND the safety timer elapsed?
## Used by tests to wait for the explosion to be ready to free.
func is_finished() -> bool:
	if _particles == null:
		return true
	return not bool(_particles.emitting) and _age >= LIFETIME_CAP * 0.5


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME_CAP:
		queue_free()


## Configure the particle system for the given size. Idempotent -- safe
## to call multiple times (a test might re-setup an explosion in
## different test cases).
func _apply_size(size_value: int) -> void:
	if _particles == null:
		return
	if size_value == SIZE_LARGE:
		_particles.amount = LARGE_PARTICLE_COUNT
		_particles.lifetime = LARGE_LIFETIME
		_particles.initial_velocity_min = LARGE_INITIAL_VELOCITY_MIN
		_particles.initial_velocity_max = LARGE_INITIAL_VELOCITY_MAX
		_particles.color = LARGE_COLOR
		_particles.scale_amount_min = _scale_factor * 1.0
		_particles.scale_amount_max = _scale_factor * 1.0
		_particles.explosiveness = 0.95
	else:
		_particles.amount = SMALL_PARTICLE_COUNT
		_particles.lifetime = SMALL_LIFETIME
		_particles.initial_velocity_min = SMALL_INITIAL_VELOCITY_MIN
		_particles.initial_velocity_max = SMALL_INITIAL_VELOCITY_MAX
		_particles.color = SMALL_COLOR
		_particles.scale_amount_min = _scale_factor * 0.6
		_particles.scale_amount_max = _scale_factor * 0.6
		_particles.explosiveness = 0.85


## Kick the emission off. `restart()` clears any prior state and
## re-fires the one_shot burst, so it's safe to call after a
## late `setup()`.
func _start_emitting() -> void:
	if _particles == null:
		return
	_particles.emitting = false
	_particles.restart()
	_particles.emitting = true


## `finished` fires when a one_shot emission has played all its
## particles. Queue_free here so a normal play session doesn't leave
## the explosion lingering in the tree.
func _on_particles_finished() -> void:
	queue_free()


## Snapshot for the StateServer / tests.
func get_state() -> Dictionary:
	return {
		"size": size,
		"particle_count": particle_count(),
		"emitting": is_emitting(),
		"age": _age,
		"scale": _scale_factor,
	}
