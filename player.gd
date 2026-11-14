extends CharacterBody2D

signal action_finished(action: String)  # Se emite al terminar scan / collect / interact

@export var speed: float = 500.0
@export var sprite_scale: float = 0.25  # Tamaño de TODOS los sprites (1.0 = original)

# Teclas de las acciones (se registran solas si no existen en el Input Map)
const ACTION_KEYS: Dictionary = {
	"scan": KEY_Q,
	"collect": KEY_E,
	"interact": KEY_F,
}

var last_direction: String = "down"
var is_busy: bool = false          # true mientras se reproduce scan / collect / interact
var current_action: String = ""

var _action_id: int = 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.scale = Vector2.ONE * sprite_scale
	animated_sprite.animation_finished.connect(_on_animation_finished)
	_register_actions()


func _physics_process(_delta: float) -> void:
	# Mientras hace una acción, el personaje no se mueve ni inicia otra
	if is_busy:
		velocity = Vector2.ZERO
		return

	if _check_actions():
		return

	get_input()
	move_and_slide()


func get_input() -> void:
	var input_direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Sin entrada: detener y mantener la última dirección en idle
	if input_direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		update_animation("idle")
		return

	velocity = input_direction * speed

	# Priorizar el eje dominante para definir la dirección
	if absf(input_direction.x) > absf(input_direction.y):
		last_direction = "right" if input_direction.x > 0.0 else "left"
	else:
		last_direction = "down" if input_direction.y > 0.0 else "up"

	update_animation("run")


func update_animation(state: String) -> void:
	var animation_name: String = _resolve_animation(state)

	if animation_name == "":
		push_warning("No existe la animación '%s_%s' ni '%s'" % [state, last_direction, state])
		return

	if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
		animated_sprite.play(animation_name)


# ---------- Acciones: scan / collect / interact ----------

func _check_actions() -> bool:
	for action in ACTION_KEYS:
		if Input.is_action_just_pressed(action):
			return start_action(action)
	return false


func start_action(action: String) -> bool:
	var animation_name: String = _resolve_animation(action)

	# Si la animación no existe NO se bloquea al personaje
	if animation_name == "":
		push_warning("No existe la animación '%s_%s' ni '%s'" % [action, last_direction, action])
		return false

	# Fuerza que no sea bucle: una animación en loop nunca termina y bloquearía al personaje
	animated_sprite.sprite_frames.set_animation_loop(animation_name, false)

	_action_id += 1
	is_busy = true
	current_action = action
	velocity = Vector2.ZERO
	animated_sprite.play(animation_name)

	# Seguro extra: si la señal nunca llega (FPS en 0, etc.), se desbloquea igual
	_watchdog(_action_id, _get_animation_duration(animation_name))
	return true


func _watchdog(id: int, duration: float) -> void:
	await get_tree().create_timer(duration + 0.2).timeout
	if is_busy and _action_id == id:
		_finish_action()


func _on_animation_finished() -> void:
	if is_busy:
		_finish_action()


func _finish_action() -> void:
	var finished: String = current_action
	is_busy = false
	current_action = ""
	action_finished.emit(finished)


func _get_animation_duration(animation_name: String) -> float:
	var frames: SpriteFrames = animated_sprite.sprite_frames
	var fps: float = frames.get_animation_speed(animation_name)
	if fps <= 0.0:
		return 0.5

	var total: float = 0.0
	for i in frames.get_frame_count(animation_name):
		total += frames.get_frame_duration(animation_name, i)

	return total / fps / maxf(animated_sprite.speed_scale, 0.01)


# ---------- Utilidades ----------

# Busca primero "estado_direccion" (ej: scan_left) y si no existe, solo "estado" (ej: scan)
func _resolve_animation(state: String) -> String:
	var found: String = _find_animation(state + "_" + last_direction)
	if found == "":
		found = _find_animation(state)
	return found


# Busca la animación ignorando mayúsculas y espacios
func _find_animation(wanted: String) -> String:
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames.has_animation(wanted):
		return wanted
	for anim_name in frames.get_animation_names():
		if String(anim_name).replace(" ", "").to_lower() == wanted:
			return anim_name
	return ""


# Crea las acciones scan / collect / interact si no están en el Input Map
func _register_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = ACTION_KEYS[action]
		InputMap.action_add_event(action, key_event)
