class_name EnvMesh
extends RefCounted

##Small 3D building blocks for the environment pieces, all in metres, y up. The picture is taken from straight above, with -Z at the top
##and +X on the right, so a piece is just a model seen from overhead: what matters is how high each surface is and which way it faces.
##Bevels are tilted so the cel bands read the way the character sprites do: the sides facing the light (top, left) get the highlight
##band, the sides facing away (bottom, right) the shadow band. See cel.gdshader.

const CEL_SHADER : Shader = preload("res://night_shift/environment/render/cel.gdshader")
const FLAT_SHADER : Shader = preload("res://night_shift/environment/render/flat.gdshader")

##Palette A, from the sprite kit's anim.py.
const PAL : Dictionary = {
	"void": "#07090c", "shadow": "#0c0e12", "deep": "#151920",
	"floor": "#1a1f27", "tile": "#222833", "wall": "#2a313d", "wall_top": "#3a4352", "metal": "#5a6475",
	#Baked from the lit look the art is judged by (a screenshot with the amber lamps on): olive-grey floors and very dark navy walls. These are the colours the pieces use,
	#now that the lighting is gone. The names above are the kit palette; the ones below are what the lamps turned them into.
	"floor_deep": "#161714", "floor_slab": "#1b1c18", "floor_panel_dim": "#20221d", "floor_panel": "#262822", "floor_stud": "#34352d",
	"wall_dark": "#101829", "cap_dark": "#0b1220", "pipe": "#1c2a4a", "door_leaf": "#16203b", "door_leaf_ext": "#1b2848", "door_inner": "#1d2a4d",
	"floor_stain": "#1d1f1a", "hazard": "#8a6a22", "hazard_dark": "#15130e", "cap_groove": "#060a14",
	"g0": "#1b2435", "uniform": "#2b3a55", "uniform_light": "#4a5d80", "armor": "#3c4a63",
	"flash": "#fff3c4", "backup": "#f2b544", "warm": "#e07b2a",
	"alarm": "#e5484d", "medic": "#c8322f", "item": "#6fd3e8", "nv": "#4be38a",
	"text": "#e7e3d8", "muted": "#a9a495", "accent": "#8fb3e0",
}

##Bevel tilt from vertical, in degrees. The light is up and to the left, so a bevel on a lit side has to be tilted about 28 degrees to
##reach the highlight band, and one on a shaded side about 47 degrees to reach the shadow band (the ramp thresholds are 0.9 and 0.38).
const TILT_LIT : float = 27.7
const TILT_SHADED : float = 47.0


static func color_of(value : Variant) -> Color:
	if value is Color:
		return value
	return Color.html(PAL.get(value, value))


##The character renderer's tone(): below 1 darkens, above 1 moves towards white.
static func tone(c : Color, k : float) -> Color:
	if k <= 1.0:
		return Color(c.r * k, c.g * k, c.b * k)
	return Color(c.r + (1.0 - c.r) * (k - 1.0), c.g + (1.0 - c.g) * (k - 1.0), c.b + (1.0 - c.b) * (k - 1.0))


##Cel material. base is a palette name, a hex string or a Color; the shadow and highlight bands are derived from it like in anim.py.
static func cel(base : Variant) -> ShaderMaterial:
	var b : Color = color_of(base)
	var m : ShaderMaterial = ShaderMaterial.new()
	m.shader = CEL_SHADER
	m.set_shader_parameter("base_color", b)
	m.set_shader_parameter("shadow_color", tone(b, 0.62))
	m.set_shader_parameter("highlight_color", tone(b, 1.22))
	return m


static func flat(color : Variant) -> ShaderMaterial:
	var m : ShaderMaterial = ShaderMaterial.new()
	m.shader = FLAT_SHADER
	m.set_shader_parameter("flat_color", color_of(color))
	return m


##A flat horizontal surface. rect is (x, z, width, depth).
static func quad(rect : Rect2, y : float, material : Material) -> MeshInstance3D:
	var st : SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, Vector3(rect.position.x, y, rect.position.y), Vector3(rect.end.x, y, rect.position.y),
		Vector3(rect.end.x, y, rect.end.y), Vector3(rect.position.x, y, rect.end.y), Vector3.UP)
	return _instance(st, material)


##A raised plate with a bevelled rim. rect is the outer footprint at the foot of the bevel; the flat top is smaller by the bevel widths.
##The plate sits on y_base, its top is y_base + height, and the bevel drops `drop` metres from the top to the outer edge, so `height`
##should be at least `drop`. sides picks which edges get a bevel (n, e, s, w); an edge without one stays flush, which is how plates
##on neighbouring wall cells join into one surface.
static func plate(rect : Rect2, y_base : float, height : float, material : Material, drop : float = 0.03,
		sides : String = "nesw") -> MeshInstance3D:
	var top : float = y_base + height
	var foot : float = top - drop
	var w_lit : float = drop * tan(deg_to_rad(TILT_LIT))
	var w_shaded : float = drop * tan(deg_to_rad(TILT_SHADED))
	var x0 : float = rect.position.x
	var z0 : float = rect.position.y
	var x1 : float = rect.end.x
	var z1 : float = rect.end.y
	var ix0 : float = x0 + (w_lit if "w" in sides else 0.0)
	var iz0 : float = z0 + (w_lit if "n" in sides else 0.0)
	var ix1 : float = x1 - (w_shaded if "e" in sides else 0.0)
	var iz1 : float = z1 - (w_shaded if "s" in sides else 0.0)
	var st : SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, Vector3(ix0, top, iz0), Vector3(ix1, top, iz0), Vector3(ix1, top, iz1), Vector3(ix0, top, iz1), Vector3.UP)
	if "n" in sides:
		_add_quad_auto(st, Vector3(x0, foot, z0), Vector3(x1, foot, z0), Vector3(ix1, top, iz0), Vector3(ix0, top, iz0))
	if "s" in sides:
		_add_quad_auto(st, Vector3(ix0, top, iz1), Vector3(ix1, top, iz1), Vector3(x1, foot, z1), Vector3(x0, foot, z1))
	if "w" in sides:
		_add_quad_auto(st, Vector3(x0, foot, z0), Vector3(ix0, top, iz0), Vector3(ix0, top, iz1), Vector3(x0, foot, z1))
	if "e" in sides:
		_add_quad_auto(st, Vector3(ix1, top, iz0), Vector3(x1, foot, z0), Vector3(x1, foot, z1), Vector3(ix1, top, iz1))
	return _instance(st, material)


##A round stud, bolt or dome: a cone frustum standing on y_base. With few segments and a turn it is a diamond or a hexagon.
static func stud(center : Vector2, y_base : float, radius_foot : float, radius_top : float, height : float, material : Material,
		segments : int = 12, turn_degrees : float = 0.0) -> MeshInstance3D:
	var mesh : CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_foot
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.cap_bottom = false
	var node : MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(center.x, y_base + height / 2.0, center.y)
	node.rotation_degrees.y = turn_degrees
	return node


##A pipe lying along X (along_x true) or along Z, centred on `center`, its axis `radius` above y_base.
static func pipe(center : Vector2, y_base : float, length : float, radius : float, along_x : bool, material : Material) -> MeshInstance3D:
	var mesh : CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var node : MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(center.x, y_base + radius, center.y)
	if along_x:
		node.rotation_degrees.z = 90.0
	else:
		node.rotation_degrees.x = 90.0
	return node


##A ball, used to join pipes at a bend, a junction or an end. Its radius is the pipe's, so it sits flush with the pipes it joins.
static func ball(center : Vector2, y_base : float, radius : float, material : Material) -> MeshInstance3D:
	var mesh : SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var node : MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(center.x, y_base + radius, center.y)
	return node

static func _add_quad(st : SurfaceTool, a : Vector3, b : Vector3, c : Vector3, d : Vector3, normal : Vector3) -> void:
	_add_tri(st, a, b, c, normal)
	_add_tri(st, a, c, d, normal)


##A quad whose normal is worked out from its corners, pointing up.
static func _add_quad_auto(st : SurfaceTool, a : Vector3, b : Vector3, c : Vector3, d : Vector3) -> void:
	var normal : Vector3 = (b - a).cross(d - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	_add_quad(st, a, b, c, d, normal)


##Godot treats clockwise triangles as front faces, so the corners are ordered to match the normal.
static func _add_tri(st : SurfaceTool, a : Vector3, b : Vector3, c : Vector3, normal : Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t : Vector3 = b
		b = c
		c = t
	for v : Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)


static func _instance(st : SurfaceTool, material : Material) -> MeshInstance3D:
	var node : MeshInstance3D = MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material
	return node
