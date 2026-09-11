extends Node3D

static var ready_count := 0
static var exit_count := 0


func _ready() -> void:
	ready_count += 1


func _exit_tree() -> void:
	exit_count += 1
