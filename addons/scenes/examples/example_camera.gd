extends Camera3D
## Runtime-only navigation; scene geometry remains authored and editable.
@export var focus := Vector3.ZERO
@export var example_title := ""
var initial_transform: Transform3D
var initial_focus: Vector3

func _ready() -> void:
	look_at(focus)
	initial_transform = transform
	initial_focus = focus
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(20, 16)
	label.text = example_title + "\nRMB: orbit  |  Wheel: zoom  |  WASD: pan  |  Shift: faster  |  R: reset"
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var offset := position - focus
		offset = offset.rotated(Vector3.UP, -event.relative.x * 0.005)
		var pitch := asin(offset.normalized().y)
		var next_pitch := clampf(pitch + event.relative.y * 0.005, 0.12, 1.48)
		offset = offset.rotated(basis.x, pitch - next_pitch)
		position = focus + offset
		look_at(focus)
	if event is InputEventMouseButton and event.pressed:
		var factor := 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			factor = 0.88
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			factor = 1.12
		position = focus + (position - focus).normalized() * clampf(position.distance_to(focus) * factor, 8.0, 1200.0)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		transform = initial_transform
		focus = initial_focus

func _process(delta: float) -> void:
	var move := Vector3.ZERO
	var forward := -basis.z
	forward.y = 0
	forward = forward.normalized()
	if Input.is_physical_key_pressed(KEY_W):
		move += forward
	if Input.is_physical_key_pressed(KEY_S):
		move -= forward
	if Input.is_physical_key_pressed(KEY_D):
		move += basis.x
	if Input.is_physical_key_pressed(KEY_A):
		move -= basis.x
	var speed := position.distance_to(focus) * 0.45
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 3.0
	var displacement := move * speed * delta
	position += displacement
	focus += displacement
