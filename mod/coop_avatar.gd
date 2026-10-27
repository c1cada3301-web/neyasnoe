extends Spatial
# Второй игрок в мире: выбранный им скин (прохожий из игры без скрипта, коллизий и триггеров),
# плавно догоняет присланные позиции. Над головой — имя из Steam.

var Skins = load("user://mods/coop_skins.gd")

const WALK_THRESHOLD = 0.5
const FOLLOW_SPEED = 12.0
const NAME_HEIGHT = 2.0
const NAME_FONT_SIZE = 13
const TELEPORT_DISTANCE = 8.0

var display_name = ""
var skin_id = ""
var skin
var target_pos = Vector3()
var target_yaw = 0.0
var speed = 0.0
var has_state = false
var label


func _ready():
	# пауза у каждого своя: друг продолжает ходить, даже когда у нас открыто меню паузы
	pause_mode = Node.PAUSE_MODE_PROCESS
	# курсив Old Standard, как в субтитрах игры (у шрифта Godot по умолчанию нет кириллицы)
	var base = load("res://Assets/Fonts/OldStandardItalic.tres")
	label = Label.new()
	if base is DynamicFont:
		var font = base.duplicate()
		font.size = NAME_FONT_SIZE
		label.add_font_override("font", font)
	label.text = display_name
	label.align = Label.ALIGN_CENTER
	label.add_color_override("font_color", Color(1, 1, 1))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	label.visible = false   # покажем, когда будет известно, где голова
	var layer = CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
	visible = false


func set_skin(id):
	id = Skins.id_at(Skins.index_of(id))   # только из списка: id приходит по сети
	if id == skin_id:
		return
	skin_id = id
	if skin:
		skin["node"].queue_free()
	skin = Skins.build(id)
	if skin == null:
		push_warning("CoopMod: не удалось собрать скин " + id)
		return
	add_child(skin["node"])
	Skins.play_idle(skin, 0.0)


func push_state(pos, yaw, move_speed, id):
	set_skin(id)
	target_pos = pos
	target_yaw = yaw
	speed = move_speed
	if not has_state or global_transform.origin.distance_to(pos) > TELEPORT_DISTANCE:
		global_transform.origin = pos
		rotation.y = yaw
	has_state = true
	visible = true


func _process(delta):
	if not has_state:
		return
	var k = clamp(delta * FOLLOW_SPEED, 0.0, 1.0)
	global_transform.origin = global_transform.origin.linear_interpolate(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)
	if skin:
		if speed > WALK_THRESHOLD:
			Skins.play_walk(skin)
		else:
			Skins.play_idle(skin)
	_update_label()


func _update_label():
	var cam = get_viewport().get_camera()
	var head = global_transform.origin + Vector3(0, NAME_HEIGHT, 0)
	if cam == null or cam.is_position_behind(head):
		label.visible = false
		return
	label.visible = true
	var p = cam.unproject_position(head)
	label.rect_position = p - Vector2(label.rect_size.x / 2.0, label.rect_size.y)
