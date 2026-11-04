# vc114: keep-clear guard — face must never be covered by a planet/panel.
# Created because no sky_layout.gd existed (only a comment referencing it).
class_name SkyLayout
extends Node

func keep_clear_of_face(node: Node3D, face: Node3D, min_deg := 40.0) -> void:
    var cam := get_viewport().get_camera_3d()
    var o := cam.global_position
    var a := (node.global_position - o)
    var dist := a.length()
    a = a.normalized()
    var b := (face.global_position - o).normalized()
    if rad_to_deg(a.angle_to(b)) >= min_deg:
        return
    var yaw_a := atan2(a.x, -a.z)
    var yaw_b := atan2(b.x, -b.z)
    var diff := angle_difference(yaw_b, yaw_a)
    var side := 1.0 if diff >= 0.0 else -1.0
    var yaw := yaw_b + side * deg_to_rad(min_deg)
    var el := asin(clampf(a.y, -1.0, 1.0))
    var dir := Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
    node.global_position = o + dir * dist
