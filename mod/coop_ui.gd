extends Reference
# Общие элементы интерфейса кооп-мода в стиле меню игры: Old Standard, строчные пункты,
# приглушённые подписи, тёмные полупрозрачные панели.

const REGULAR = "res://Assets/Fonts/OldStandardRegular.tres"
const ITALIC = "res://Assets/Fonts/OldStandardItalic.tres"
const BUTTON_H = 25
const DIM = Color(0, 0, 0, 0.627451)     # как у экрана выбора главы
const ACCENT = Color("#69b2ff")          # голубой из темы игры


static func font(path, size):
	var base = load(path)
	if not (base is DynamicFont):
		return null
	var f = base.duplicate()
	f.size = size
	return f


static func button(text, pos, width = 260):
	var b = Button.new()
	b.text = text
	b.align = Button.ALIGN_LEFT
	b.rect_position = pos
	b.rect_size = Vector2(width, BUTTON_H)
	return b


static func label(text, pos, size, alpha = 1.0, f = null):
	var l = Label.new()
	l.text = text
	l.rect_position = pos
	l.rect_size = size
	l.autowrap = true
	l.modulate = Color(1, 1, 1, alpha)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if f:
		l.add_font_override("font", f)
	return l


static func dim():
	var r = ColorRect.new()
	r.set_anchors_preset(Control.PRESET_WIDE)
	r.color = DIM
	return r


static func panel_style(alpha = 0.55):
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, alpha)
	s.border_color = Color(1, 1, 1, 0.18)
	s.set_border_width_all(1)
	for side in [MARGIN_LEFT, MARGIN_TOP, MARGIN_RIGHT, MARGIN_BOTTOM]:
		s.set_default_margin(side, 10)
	return s


static func panel(rect, alpha = 0.55):
	var p = Panel.new()
	p.rect_position = rect.position
	p.rect_size = rect.size
	p.add_stylebox_override("panel", panel_style(alpha))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# Вертикальная цепочка фокуса для клавиатуры и геймпада (по кругу).
static func chain_focus(controls):
	var list = []
	for c in controls:
		if c and c.visible:
			list.append(c)
	for i in range(list.size()):
		var a = list[i]
		var b = list[(i + 1) % list.size()]
		a.focus_neighbour_bottom = a.get_path_to(b)
		a.focus_next = a.get_path_to(b)
		b.focus_neighbour_top = b.get_path_to(a)
		b.focus_previous = b.get_path_to(a)
