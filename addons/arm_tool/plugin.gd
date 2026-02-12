@tool
extends EditorPlugin

var dock

func _enter_tree():
	# Cargar la escena del dock
	dock = preload("res://addons/arm_tool/resources/channel_packer_dock.tscn").instantiate()
	# Añadir el dock a la pestaña
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree():
	# Limpiar al desactivar el plugin
	remove_control_from_docks(dock)
	dock.free()
