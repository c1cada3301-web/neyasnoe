extends Reference
# Границы уровня для машин. У игры по краю уровня невидимые стены (StaticBody «WorldBorders*»
# на слое 2): пешком дальше не пройти. На машине внутри них тесно, особенно на площади Level2,
# поэтому для машин строим копию этих стен, растянутую от центра уровня, на отдельном слое.
# Игрок по-прежнему упирается в старые стены. За ними земля есть не везде: если машина
# всё же упадёт, coop_car.gd вернёт её на дорогу.

const GAME_BORDERS_BIT = 1      # слой стен игры
const CAR_BORDERS_BIT = 10      # слой наших стен: его видят только машины
const NODE_NAME = "CoopCarBorders"
# Насколько раздвинуть стены по горизонтали. Подобрано по тому, где за стенами ещё есть земля:
# в Level1 машина теперь упирается в стену на ~30 м дальше. В Level2 стены машину и так
# не держат — там край самой земли (площадь — остров в пустоте), раздвигать нечего.
const DEFAULT_SCALE = 1.15
const LEVEL_SCALE = {}


static func build(scene):
	if scene == null or scene.has_node(NODE_NAME):
		return
	var level = scene.filename.get_file().get_basename()
	var scale = LEVEL_SCALE.get(level, DEFAULT_SCALE)
	var fence = StaticBody.new()
	fence.name = NODE_NAME
	fence.collision_layer = 1 << CAR_BORDERS_BIT
	fence.collision_mask = 0
	var count = 0
	for wall in scene.get_children():
		if not (wall is StaticBody and wall.name.begins_with("WorldBorders")):
			continue
		if not wall.get_collision_layer_bit(GAME_BORDERS_BIT):
			continue
		for shape in wall.get_children():
			if shape is CollisionShape and shape.shape is ConcavePolygonShape:
				fence.add_child(_stretched(shape, scale))
				count += 1
	if count == 0:
		fence.free()
		return
	scene.add_child(fence)


# Копия формы стены, растянутая по горизонтали от центра её габаритов.
static func _stretched(shape, scale):
	var copy = CollisionShape.new()
	copy.shape = shape.shape
	var center = _center(shape)
	var stretch = Transform(Basis().scaled(Vector3(scale, 1, scale)), Vector3())
	var around = Transform(Basis(), center) * stretch * Transform(Basis(), -center)
	copy.transform = around * shape.global_transform
	return copy


static func _center(shape):
	var faces = shape.shape.get_faces()
	if faces.empty():
		return shape.global_transform.origin
	var lo = shape.global_transform.xform(faces[0])
	var hi = lo
	for v in faces:
		var g = shape.global_transform.xform(v)
		lo = Vector3(min(lo.x, g.x), min(lo.y, g.y), min(lo.z, g.z))
		hi = Vector3(max(hi.x, g.x), max(hi.y, g.y), max(hi.z, g.z))
	return (lo + hi) / 2


# Машина упирается в наши, раздвинутые стены, а не в стены игры.
static func fence_in(vehicle):
	vehicle.set_collision_mask_bit(GAME_BORDERS_BIT, false)
	vehicle.set_collision_mask_bit(CAR_BORDERS_BIT, true)
