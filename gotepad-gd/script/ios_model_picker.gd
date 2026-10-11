class_name IOSModelPicker
extends Node

signal completed(result: Dictionary)

var picker_: Object


func open_file() -> bool:
	if not ClassDB.class_exists(&"IOSModelFilePicker"):
		return false
	picker_ = ClassDB.instantiate(&"IOSModelFilePicker")
	if picker_ == null or not bool(picker_.call("open_file")):
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
