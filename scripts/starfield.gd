extends ParallaxBackground
class_name Starfield
## 2-layer parallax starfield background.
##
## Two `ParallaxLayer` children scroll at different speeds to create a
## sense of depth. The two layers are wired in code (not .tscn) so a
## test can construct a starfield from scratch and assert on the
## layer count, motion_scale, and motion_mirroring values without
## depending on the visual .tscn.
##
## The layers themselves are populated with a programmatic dot pattern
## (ColorRects in a grid) since we have no dedicated star sprite -- the
## existing `starfield.png` is the design-doc background, not a tile.
##
## API:
##   layer_count() -> int           # 2
##   layer_speed(layer_idx) -> float  # motion_scale of the layer
##   scroll(delta) -> void          # advance the layers by delta seconds
##   get_layer_offset(layer_idx) -> Vector2  # current scroll offset of the layer
##
## The .tscn variant just adds this script to a ParallaxBackground and
## `_ready` builds the two layers. Tests can construct one with
## `Starfield.new() + add_child(starfield)` and call the same API.

## Number of layers (the design doc calls for 2: a slow far layer and a
## faster near layer).
const LAYER_COUNT := 2
## Pixel size of each generated star dot. 2x2 is enough to be visible
## at the default zoom without dominating the viewport.
const STAR_SIZE := 2
## Tile size for the procedural star pattern. 96px gives ~120 dots in
## each layer for a 1152-wide viewport, which feels "starry" without
## being noisy.
const TILE_SIZE := 96
## How many dots per tile (on average). ~6 dots in a 96x96 tile keeps
## the pattern sparse enough that the two layers read as separate
## parallax planes.
const DOTS_PER_TILE := 6

## Far layer (slow, smaller dots, lower alpha).
const FAR_SCALE := 0.2
const FAR_COLOR := Color(0.70, 0.78, 0.95, 0.55)

## Near layer (faster, larger dots, full alpha).
const NEAR_SCALE := 0.5
const NEAR_COLOR := Color(0.92, 0.96, 1.0, 0.95)

## Layers (ParallaxLayer nodes) constructed in _ready.
var _layers: Array = []
## Seeded RNG used for the procedural star positions so two starfields
## built back-to-back have the same layout. Tests that assert on
## specific node counts use deterministic children only, so the RNG is
## safe to share.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234567
	_build_layer(0, FAR_SCALE, FAR_COLOR)
	_build_layer(1, NEAR_SCALE, NEAR_COLOR)


## Build a single parallax layer with a procedural dot grid. `scale`
## is the motion_scale (smaller = appears farther / scrolls slower).
func _build_layer(idx: int, scale: float, color: Color) -> void:
	var layer := ParallaxLayer.new()
	layer.name = "StarLayer_%d" % idx
	layer.motion_scale = Vector2(scale, scale)
	# Enable motion mirroring so the layer tiles seamlessly when it
	# scrolls past the viewport edge. The mirror rect is sized for the
	# default 1152x648 viewport; a 64x64 headless test fixture will
	# only render a portion of the layer (which is fine -- the layer
	# itself still has the expected children).
	var mirror_w: float = float(TILE_SIZE * 4)
	var mirror_h: float = float(TILE_SIZE * 4)
	layer.motion_mirroring = Vector2(mirror_w, mirror_h)
	add_child(layer)
	# Fill the layer with a grid of stars. We use a deterministic seed
	# so the layout is reproducible across runs / tests.
	for x in range(0, int(mirror_w), TILE_SIZE):
		for y in range(0, int(mirror_h), TILE_SIZE):
			for _i in range(DOTS_PER_TILE):
				var dot := ColorRect.new()
				dot.size = Vector2(STAR_SIZE, STAR_SIZE)
				dot.position = Vector2(
					x + _rng.randf_range(0, float(TILE_SIZE - STAR_SIZE)),
					y + _rng.randf_range(0, float(TILE_SIZE - STAR_SIZE)),
				)
				dot.color = color
				layer.add_child(dot)
	_layers.append(layer)


## Manually advance the parallax scroll. We bypass ParallaxBackground's
## built-in `scroll_base_offset` (which only follows the camera) and
## drive each layer's `motion_offset` directly. This is what gives the
## "always scrolling, no camera needed" feel.
func scroll(delta: float) -> void:
	# The far layer scrolls slowly; the near layer twice as fast. The
	# downward direction matches the game (player flies up, stars move
	# down).
	var speeds := [FAR_SCALE, NEAR_SCALE]
	for i in range(_layers.size()):
		var layer: ParallaxLayer = _layers[i]
		if layer == null:
			continue
		var sp: float = speeds[i] if i < speeds.size() else 0.3
		layer.motion_offset.y += delta * 60.0 * sp


## Override _process to auto-scroll. Tests can disable auto-scroll by
## setting `process_mode = PROCESS_MODE_MANUAL` and calling `scroll(dt)`
## themselves.
func _process(delta: float) -> void:
	# `Node.PROCESS_MODE_DISABLED` (= 4) and skip auto-scroll, letting
	# tests drive the parallax by calling `scroll(dt)` themselves.
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	scroll(delta)


## Public: number of parallax layers (always 2 by design).
func layer_count() -> int:
	return _layers.size()


## Public: motion_scale of the layer at `idx`. -1 if the index is out
## of range.
func layer_speed(idx: int) -> float:
	if idx < 0 or idx >= _layers.size():
		return -1.0
	var layer: ParallaxLayer = _layers[idx]
	if layer == null:
		return -1.0
	return float(layer.motion_scale.x)


## Public: the layer's current motion_offset (the cumulative scroll
## position). Tests assert on this to verify the layer actually moved
## after `scroll(dt)`.
func get_layer_offset(idx: int) -> Vector2:
	if idx < 0 or idx >= _layers.size():
		return Vector2.ZERO
	var layer: ParallaxLayer = _layers[idx]
	if layer == null:
		return Vector2.ZERO
	return layer.motion_offset
