class_name Geo
extends RefCounted
## Converts between JSBSim geodetic coordinates and local Godot metres
## around a world origin. East = +X, up = +Y, north = -Z.

const WGS84_A := 6378137.0
const WGS84_E2 := 6.69437999014e-3
const FT := 0.3048

var lat0_deg: float
var lon0_deg: float
var _m_per_rad_lat: float
var _m_per_rad_lon: float


func _init(origin_lat_deg: float, origin_lon_deg: float) -> void:
	lat0_deg = origin_lat_deg
	lon0_deg = origin_lon_deg
	var s := sin(deg_to_rad(lat0_deg))
	var w := sqrt(1.0 - WGS84_E2 * s * s)
	_m_per_rad_lat = WGS84_A * (1.0 - WGS84_E2) / (w * w * w)
	_m_per_rad_lon = WGS84_A / w * cos(deg_to_rad(lat0_deg))


func to_local(lat_deg: float, lon_deg: float, alt_m: float) -> Vector3:
	var north := deg_to_rad(lat_deg - lat0_deg) * _m_per_rad_lat
	var east := deg_to_rad(lon_deg - lon0_deg) * _m_per_rad_lon
	return Vector3(east, alt_m, -north)


## Returns Vector3(lat_deg, lon_deg, alt_m).
func to_geo(p: Vector3) -> Vector3:
	var lat := lat0_deg + rad_to_deg(-p.z / _m_per_rad_lat)
	var lon := lon0_deg + rad_to_deg(p.x / _m_per_rad_lon)
	return Vector3(lat, lon, p.y)


## JSBSim structural frame (inches; X aft, Y right, Z up) to Godot local metres.
static func struct_to_local(x_in: float, y_in: float, z_in: float) -> Vector3:
	return Vector3(y_in, z_in, x_in) * 0.0254
