extends "res://addons/scenes/examples/example_camera.gd"
## Road inspection at driver height, without a vehicle or suspension simulation.
@export var route_path: NodePath
var distance := 0.0
var touring := false
var route: Path3D
var status: Label

func _ready() -> void:
	super._ready()
	route = get_node(route_path)
	distance = 180.0
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(20, 112)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(status)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			touring = not touring
			return
		if event.keycode == KEY_1 or event.keycode == KEY_2:
			touring = false
			distance = route.curve.get_baked_length() - 70 if event.keycode == KEY_1 else 100.0
			focus = route.to_global(route.curve.sample_baked(distance))
			position = focus + Vector3(-70, 65, 80)
			look_at(focus)
			return
		if event.keycode == KEY_R:
			touring = false
			distance = 180.0
	if not touring:
		super._unhandled_input(event)

func _process(delta: float) -> void:
	if not is_instance_valid(route):
		return
	if touring:
		var speed := 13.89 # 50 km/h camera preview; not a driving physics model.
		if Input.is_physical_key_pressed(KEY_SHIFT):
			speed *= 3.0
		if Input.is_physical_key_pressed(KEY_S):
			speed = -speed
		distance = clampf(distance - speed * delta, 4.0, route.curve.get_baked_length() - 4.0)
		var point := route.to_global(route.curve.sample_baked(distance))
		var ahead := route.to_global(route.curve.sample_baked(maxf(0, distance - 12.0)))
		var forward := (ahead - point).normalized()
		var right := forward.cross(Vector3.UP).normalized()
		position = point + right * 1.55 + Vector3.UP * 1.65
		focus = ahead + right * 1.55 + Vector3.UP * 1.65
		look_at(focus)
		if distance <= 4.0:
			touring = false
	else:
		super._process(delta)
	status.text = "1: Poiana  |  2: Brasov centru  |  P: tur/pauza  |  S in tur: inapoi\nDistanta ramasa spre centru: %.2f km" % (distance / 1000.0)
