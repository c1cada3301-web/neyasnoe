extends CanvasLayer
# Короткие уведомления сверху по центру: «машина появилась», «полёт: вкл» и т.п.
# Новое сообщение заменяет старое; через SHOW_SECONDS текст плавно гаснет.
# Заодно следит за читами игры (F11 — читы, F3 — полёт, F4 — сквозь стены, F5/F6 — время,
# F7/F8 — скорость ходьбы): сама игра их никак не показывает.

const FONT = "res://Assets/Fonts/OldStandardRegular.tres"
const FONT_SIZE = 16
const TOP = 28
const SHOW_SECONDS = 2.0
const FADE_SECONDS = 0.6

var coop
var label
var shown = 0.0
var cheats = {}            # последнее увиденное состояние читов игрока


func _init():
	layer = 101
	pause_mode = Node.PAUSE_MODE_PROCESS


func _ready():
	label = Label.new()
	label.align = Label.ALIGN_CENTER
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.margin_top = TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	var base = load(FONT)
	if base is DynamicFont:
		var f = base.duplicate()
		f.size = FONT_SIZE
		label.add_font_override("font", f)
	label.modulate.a = 0.0
	add_child(label)


func show_text(text):
	label.text = text
	label.modulate.a = 1.0
	shown = 0.0


func _process(delta):
	_watch_cheats()
	if label.modulate.a <= 0.0:
		return
	shown += delta
	if shown > SHOW_SECONDS:
		label.modulate.a = max(0.0, 1.0 - (shown - SHOW_SECONDS) / FADE_SECONDS)


func _watch_cheats():
	var p = coop._local_player() if coop else null
	if p == null or not ("enable_cheats" in p):
		cheats = {}
		return
	var now = {
		"cheats": p.enable_cheats,
		"fly": p.is_flying,
		"noclip": not p.get_collision_mask_bit(0),
		"time": stepify(Engine.time_scale, 0.01),
		"walk": p.walk_speed,
	}
	# пока игрок в машине (или в катсцене), мод и игра сами меняют эти поля — молчим,
	# а после заново запоминаем состояние, чтобы выход из машины не выглядел как чит
	if not p.is_active or (coop.car and coop.car.driving()):
		cheats = {}
		return
	if not cheats.empty():
		if now["cheats"] != cheats["cheats"]:
			show_text("читы: " + _on_off(now["cheats"]))
		elif now["noclip"] != cheats["noclip"]:
			show_text("сквозь стены: " + _on_off(now["noclip"]))
		elif now["fly"] != cheats["fly"]:
			show_text("полёт: " + _on_off(now["fly"]))
		elif now["time"] != cheats["time"]:
			show_text("скорость времени: %s" % str(now["time"]))
		elif now["walk"] != cheats["walk"]:
			show_text("скорость ходьбы: %s" % str(now["walk"]))
	cheats = now


static func _on_off(value):
	return "вкл" if value else "выкл"
