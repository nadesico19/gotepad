class_name IOSSGFPicker
extends Node

signal completed(result: Dictionary)

var picker_: Object


func open_file() -> bool:
	return start_("open_file", [])


func open_image() -> bool:
	return start_("open_image", [])


func open_camera() -> bool:
	return start_("open_camera", [])


func open_image_source(title: String, album_label: String, file_label: String, cancel_label: String) -> bool:
	return start_("open_image_source", [title, album_label, file_label, cancel_label])


func export_file(path: String) -> bool:
	return start_("export_file", [path])


func overwrite_file(path: String, bookmark: String) -> bool:
	return start_("overwrite_file", [path, bookmark])


func start_(method: String, arguments: Array) -> bool:
	if not ClassDB.class_exists(&"IOSSGFFileBridge"):
		return false
	picker_ = ClassDB.instantiate(&"IOSSGFFileBridge")
	if picker_ == null or not bool(picker_.callv(method, arguments)):
		return false
	set_process(true)
	return true


func _process(_delta: float) -> void:
	var result: Dictionary = Dictionary(picker_.call("poll_result"))
	if result.is_empty():
		return
	set_process(false)
	completed.emit(result)
	queue_free()


func _exit_tree() -> void:
	if picker_ != null:
		picker_.call("cancel")
