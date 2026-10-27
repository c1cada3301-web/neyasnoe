extends Reference
# Что друг держит и включил: сигарета во рту и фонарик. В игре курение видно только от первого
# лица (руки игрока), а у прохожих-скинов анимации курения нет, поэтому сигарету собираем сами:
# тонкий цилиндр с тлеющим кончиком и дымок у рта. Высоту рта берём от макушки скелета скина
# (у скинов разный рост); голова в анимациях ходьбы почти не двигается, поэтому крепим к аватару.

const HEAD_TOP_SUFFIX = "HeadTop_End"     # mixamorig_HeadTop_End / mixamorigHeadTop_End
const MOUTH_BELOW_TOP = 0.215
const MOUTH_FORWARD = 0.1                 # аватар смотрит в −Z
const DEFAULT_MOUTH_HEIGHT = 1.62
const CIGARETTE_LENGTH = 0.08
const CIGARETTE_RADIUS = 0.005
const EMBER_IDLE = 1.0
const SMOKE_TEXTURE = "res://Assets/Textures/SmokeParticle2.png"   # дым выдоха игрока
# Зажигалка: в игре она часть меша рук, отдельной модели нет — собираем коробочку сами.
const LIGHTER_SIZE = Vector3(0.022, 0.06, 0.012)
const LIGHTER_COLOR = Color(0.55, 0.08, 0.06)
const EMBER_SCALE = 1.2
const FLASHLIGHT_HEIGHT = 1.6
# Как у фонарика игрока (Player.tscn → RotationHelper/Flashlight), но без теней:
# свет чужого фонаря тени не стоит, а атлас теней у игры небольшой.
const FLASHLIGHT_COLOR = Color(0.964706, 1, 0.784314)
const FLASHLIGHT_ENERGY = 2.0
const FLASHLIGHT_RANGE = 7.0
const FLASHLIGHT_ANGLE = 60.0


# Сигарета у рта скина; skin_root уже должен быть в дереве (нужна поза скелета).
static func attach_cigarette(avatar, skin_root):
	var cigarette = _cigarette()
	cigarette.translation = Vector3(0.01, _mouth_height(avatar, skin_root), -MOUTH_FORWARD)
	cigarette.rotation_degrees = Vector3(15, 180, 0)   # вперёд от губ и чуть вниз
	cigarette.visible = false
	avatar.add_child(cigarette)
	return cigarette


static func _mouth_height(avatar, skin_root):
	var skeleton = _find_skeleton(skin_root)
	if skeleton == null:
		return DEFAULT_MOUTH_HEIGHT
	for i in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(i).ends_with(HEAD_TOP_SUFFIX):
			var top = skeleton.global_transform.xform(skeleton.get_bone_global_pose(i).origin)
			return avatar.global_transform.affine_inverse().xform(top).y - MOUTH_BELOW_TOP
	return DEFAULT_MOUTH_HEIGHT


# Цилиндр вдоль +Z (от губ вперёд), оранжевый кончик и дым с кончика.
static func _cigarette():
	var root = Spatial.new()
	root.name = "CoopCigarette"
	var paper = SpatialMaterial.new()
	paper.albedo_color = Color(0.93, 0.92, 0.88)
	var body = MeshInstance.new()
	var tube = CylinderMesh.new()
	tube.top_radius = CIGARETTE_RADIUS
	tube.bottom_radius = CIGARETTE_RADIUS
	tube.height = CIGARETTE_LENGTH
	tube.radial_segments = 8
	tube.rings = 1
	body.mesh = tube
	body.material_override = paper
	body.rotation_degrees = Vector3(90, 0, 0)   # цилиндр Godot стоит вдоль Y
	body.translation = Vector3(0, 0, CIGARETTE_LENGTH / 2)
	root.add_child(body)
	var ember = SpatialMaterial.new()
	ember.albedo_color = Color(1.0, 0.35, 0.05)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.35, 0.05)
	ember.emission_energy = 4.0
	var tip = MeshInstance.new()
	var dot = SphereMesh.new()
	dot.radius = CIGARETTE_RADIUS * 1.1
	dot.height = CIGARETTE_RADIUS * 2.2
	dot.radial_segments = 8
	dot.rings = 4
	tip.mesh = dot
	tip.material_override = ember
	tip.name = "Ember"
	tip.translation = Vector3(0, 0, CIGARETTE_LENGTH)
	root.add_child(tip)
	var smoke = CPUParticles.new()
	smoke.amount = 12
	smoke.lifetime = 2.5
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.gravity = Vector3(0, 0.15, 0)
	smoke.initial_velocity = 0.12
	smoke.scale_amount = 0.6
	smoke.scale_amount_random = 0.4
	smoke.angle_random = 1.0
	smoke.angular_velocity = 20.0
	smoke.angular_velocity_random = 1.0
	var puff = QuadMesh.new()
	puff.size = Vector2(0.06, 0.06)
	var haze = SpatialMaterial.new()
	haze.albedo_texture = load(SMOKE_TEXTURE)   # мягкий клуб из игры, а не квадратик
	haze.flags_transparent = true
	haze.flags_unshaded = true
	haze.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	haze.vertex_color_use_as_albedo = true
	haze.albedo_color = Color(0.8, 0.8, 0.8, 0.25)
	puff.material = haze
	smoke.mesh = puff
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.6))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = fade
	smoke.translation = Vector3(0, 0, CIGARETTE_LENGTH)
	root.add_child(smoke)
	return root


# Фонарик на уровне глаз, светит туда, куда смотрит друг (наклон приходит в пакете).
static func flashlight():
	var light = SpotLight.new()
	light.name = "CoopFlashlight"
	light.light_color = FLASHLIGHT_COLOR
	light.light_energy = FLASHLIGHT_ENERGY
	light.spot_range = FLASHLIGHT_RANGE
	light.spot_angle = FLASHLIGHT_ANGLE
	light.spot_attenuation = 3.0
	light.spot_angle_attenuation = 0.4
	light.shadow_enabled = false
	light.translation = Vector3(0, FLASHLIGHT_HEIGHT, 0)
	light.visible = false
	return light


static func lighter():
	var body = MeshInstance.new()
	body.name = "CoopLighter"
	var box = CubeMesh.new()
	box.size = LIGHTER_SIZE
	body.mesh = box
	var plastic = SpatialMaterial.new()
	plastic.albedo_color = LIGHTER_COLOR
	plastic.roughness = 0.4
	body.material_override = plastic
	body.visible = false
	return body


# Кончик сигареты: 0 — не горит, 1 — тлеет, 5 — затяжка (как у сигареты в руках игрока).
static func set_ember(cigarette, energy):
	var tip = cigarette.get_node_or_null("Ember")
	if tip and tip.material_override:
		tip.material_override.emission_energy = energy * EMBER_SCALE
		tip.visible = energy > 0.0


static func _find_skeleton(node):
	if node is Skeleton:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null
