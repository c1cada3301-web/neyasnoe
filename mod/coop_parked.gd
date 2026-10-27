extends Reference
# Припаркованные машины: в уровнях это просто модели (MeshInstance кузова, иногда колёса
# отдельными мешами и StaticBody). Ехать они не могут, поэтому при посадке собираем из них
# VehicleBody: кузов, колёса и столкновения переносим внутрь, колёса делаем VehicleWheel.
# Оживляем только машины с колёсами отдельными мешами: иначе колёса не крутились бы.
#
# Два вида в сценах:
#   CarN (MeshInstance) → CarNWheelK (MeshInstance), StaticBody         — Level1, Level4
#   CarN (Spatial)      → CarN (MeshInstance), CarNWheelK, [StaticBody]  — Level2

const BODY_MESH = "res://Assets/ESCN/Car%d.mesh"
const ENGINE_SOUND = "res://Assets/Audios/Car1Engine.wav"
const MASS = 600.0
const WHEEL_REST = 0.05
const WHEEL_TRAVEL = 0.2
const WHEEL_STIFFNESS = 50.0
const WHEEL_ROLL = 0.2
const BODY_CLEARANCE = 0.3      # коробка столкновений не касается земли, землю держат колёса
const REACH = 3.0               # с какого расстояния можно сесть, м


# Корни всех припаркованных машин сцены (то, что станет VehicleBody).
static func find_all(scene):
	var out = []
	_collect(scene, out)
	return out


static func _collect(node, out):
	if node is VehicleBody:
		return   # машины-автопилоты и так умеют ездить
	if node.name.begins_with("Prewarm"):
		return   # уменьшенные копии машин под картой — прогрев шейдеров
	if node is MeshInstance and _is_body_mesh(node):
		var parent = node.get_parent()
		# держатель — Spatial «CarN» ровно с одним кузовом (не общая папка «Cars» в Level4)
		var holder = parent.get_class() == "Spatial" and parent.name.begins_with("Car") \
			and _body_count(parent) == 1
		var root = parent if holder else node
		if _has_wheels(root):
			out.append(root)   # кузов одним мешем (колёса нарисованы) не оживляем — пусть стоит
		return
	for child in node.get_children():
		_collect(child, out)


static func _has_wheels(root):
	for child in root.get_children():
		if child is MeshInstance and child.name.find("Wheel") >= 0:
			return true
	return false


static func _body_count(node):
	var n = 0
	for child in node.get_children():
		if child is MeshInstance and _is_body_mesh(child):
			n += 1
	return n


static func _is_body_mesh(node):
	var mesh = node.mesh
	if mesh == null:
		return false
	var file = mesh.resource_path.get_file().get_basename()   # Car2 → да, Car2Wheel1 → нет
	if not file.begins_with("Car"):
		return false
	var n = file.substr(3)
	return n.is_valid_integer() and mesh.resource_path == BODY_MESH % int(n)


# Машина, на которую смотрит камера: луч длиной REACH против габаритов кузова.
# Луч игры тут не годится: у части машин в Level2 вообще нет столкновений.
static func looked_at(cars, from, dir):
	var best = null
	var best_dist = REACH
	for root in cars:
		if not is_instance_valid(root) or not root.is_visible_in_tree():
			continue
		var body = body_mesh(root)
		var to_local = body.global_transform.affine_inverse()
		var a = to_local.xform(from)
		var b = to_local.xform(from + dir * REACH)
		var t = _segment_hits_box(a, b, body.get_aabb())
		if t < 0:
			continue
		var dist = t * REACH
		if dist < best_dist:
			best = root
			best_dist = dist
	return best


# Доля отрезка a→b до входа в коробку, или -1. Свой расчёт: встроенный
# AABB.intersects_segment в этой сборке Godot 3.4 роняет игру.
static func _segment_hits_box(a, b, box):
	var d = b - a
	var t_min = 0.0
	var t_max = 1.0
	for i in range(3):
		var lo = box.position[i]
		var hi = lo + box.size[i]
		if abs(d[i]) < 0.00001:
			if a[i] < lo or a[i] > hi:
				return -1.0
			continue
		var t1 = (lo - a[i]) / d[i]
		var t2 = (hi - a[i]) / d[i]
		t_min = max(t_min, min(t1, t2))
		t_max = min(t_max, max(t1, t2))
		if t_min > t_max:
			return -1.0
	return t_min


static func body_mesh(root):
	if root is MeshInstance:
		return root
	for child in root.get_children():
		if child is MeshInstance and _is_body_mesh(child):
			return child
	return null


# Собирает VehicleBody на месте модели и возвращает его. Модель остаётся та же, только
# переезжает внутрь новой машины. StaticBody модели удаляем: столкновения даёт коробка кузова.
static func make_drivable(root):
	var body = body_mesh(root)
	var parent = root.get_parent()
	var vb = VehicleBody.new()
	vb.name = root.name + "_Drivable"
	vb.mass = MASS
	vb.can_sleep = false
	parent.add_child(vb)
	var base = root.global_transform
	if root is MeshInstance:
		base.origin = body.global_transform.xform(_aabb_bottom(body))
	vb.global_transform = base
	var wheels = []
	var parts = []
	for node in ([root] if root is MeshInstance else []) + root.get_children():
		if node is MeshInstance and node.name.find("Wheel") >= 0:
			wheels.append(node)
		elif node is StaticBody:
			pass   # её формы доходят до земли и проваливают машину сквозь пол — ставим свою коробку
		elif node != root:
			parts.append(node)
	if root is MeshInstance:
		_move(root, vb)        # кузов сам был корнем, колёса и прочее едут вместе с ним
		for w in wheels:
			if w != root:
				_move(w, vb)
	else:
		for p in parts:
			_move(p, vb)
	vb.add_child(_box_from(body, vb))
	_free_static_bodies(root)
	for w in wheels:
		_add_wheel(vb, w)
	_add_engine_sound(vb)
	if not (root is MeshInstance):
		root.queue_free()   # пустой держатель от Level2
	vb.sleeping = false
	return vb


static func _move(node, new_parent):
	var xf = node.global_transform
	node.get_parent().remove_child(node)
	new_parent.add_child(node)
	node.global_transform = xf


static func _free_static_bodies(root):
	for node in root.get_children():
		if node is StaticBody:
			node.queue_free()


static func _aabb_bottom(mesh):
	var a = mesh.get_aabb()
	return Vector3(a.position.x + a.size.x / 2, a.position.y, a.position.z + a.size.z / 2)


static func _box_from(body, vb):
	var a = body.get_aabb()
	a.position.y += BODY_CLEARANCE
	a.size.y = max(0.2, a.size.y - BODY_CLEARANCE)
	var box = BoxShape.new()
	box.extents = a.size / 2
	var shape = CollisionShape.new()
	shape.shape = box
	var center_global = body.global_transform.xform(a.position + a.size / 2)
	shape.transform = Transform(vb.global_transform.basis.inverse() * body.global_transform.basis,
		vb.global_transform.affine_inverse().xform(center_global))
	return shape


# Колесо-меш становится ребёнком VehicleWheel так, чтобы его центр был на оси: тогда оно крутится.
static func _add_wheel(vb, mesh):
	var a = mesh.get_aabb()
	var center_local = a.position + a.size / 2
	var center = vb.global_transform.affine_inverse().xform(mesh.global_transform.xform(center_local))
	var wheel = _new_wheel(min(a.size.y, a.size.z) / 2, center)
	vb.add_child(wheel)
	var basis = vb.global_transform.basis.inverse() * mesh.global_transform.basis
	mesh.get_parent().remove_child(mesh)
	wheel.add_child(mesh)
	mesh.transform = Transform(basis, -basis.xform(center_local))


static func _new_wheel(radius, center):
	var wheel = VehicleWheel.new()
	wheel.wheel_radius = radius
	wheel.wheel_rest_length = WHEEL_REST
	wheel.suspension_travel = WHEEL_TRAVEL
	wheel.suspension_stiffness = WHEEL_STIFFNESS
	wheel.wheel_roll_influence = WHEEL_ROLL
	wheel.use_as_steering = center.z > 0    # перед машин в игре — +Z
	wheel.use_as_traction = center.z < 0    # задний привод, как у машин-автопилотов
	wheel.translation = center + Vector3.UP * WHEEL_REST
	return wheel


static func _add_engine_sound(vb):
	var stream = load(ENGINE_SOUND)
	if stream == null:
		return
	if stream is AudioStreamSample and stream.loop_mode == AudioStreamSample.LOOP_DISABLED:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamSample.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var audio = AudioStreamPlayer3D.new()
	audio.name = "EngineSound"
	audio.stream = stream
	audio.unit_db = -10
	vb.add_child(audio)
	audio.play()
