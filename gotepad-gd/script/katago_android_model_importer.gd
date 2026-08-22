class_name KataGoAndroidModelImporter
extends Node

signal progress_changed(copied_bytes: int, total_bytes: int)
signal completed(
	succeeded: bool,
	model_path: String,
	model_name: String,
	message: String
)

const kModelDirectory: String = "user://katago/models"
const kMaximumModelSize: int = 1024 * 1024 * 1024
const kMinimumModelSize: int = 1024
const kCopyChunkSize: int = 1024 * 1024
const kChunksPerFrame: int = 4
const kValidationHeaderSize: int = 64 * 1024
const kValidationInputChunkSize: int = 16 * 1024

var source_: FileAccess
var target_: FileAccess
var source_path_: String = ""
var temporary_path_: String = ""
var copied_bytes_: int = 0
var total_bytes_: int = 0
var finishing_: bool = false
var model_role_: String = "analysis"


func _init(model_role: String = "analysis") -> void:
	model_role_ = "human" if model_role == "human" else "analysis"


func start_import(source_path: String) -> bool:
	if source_ != null or source_path.is_empty():
		return false
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(kModelDirectory)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		finish_(false, "", "", tr("无法创建外置模型目录：%s") %
			error_string(directory_error))
		return false
	source_ = FileAccess.open(source_path, FileAccess.READ)
	if source_ == null:
		finish_(false, "", "", tr("无法读取所选模型：%s") %
			error_string(FileAccess.get_open_error()))
		return false
	total_bytes_ = source_.get_length()
	if total_bytes_ < kMinimumModelSize or total_bytes_ > kMaximumModelSize:
		finish_(false, "", "", tr("模型文件大小必须在 1 KB 到 1 GB 之间。"))
		return false
	var directory: DirAccess = DirAccess.open(kModelDirectory)
	if directory != null and directory.get_space_left() < total_bytes_ * 2:
		finish_(false, "", "", tr("存储空间不足，导入模型至少需要模型大小两倍的可用空间。"))
		return false
	temporary_path_ = "%s/importing-%d.part" % [
		kModelDirectory, Time.get_ticks_usec()
	]
	target_ = FileAccess.open(temporary_path_, FileAccess.WRITE)
	if target_ == null:
		finish_(false, "", "", tr("无法创建模型临时文件：%s") %
			error_string(FileAccess.get_open_error()))
		return false
	source_path_ = source_path
	set_process(true)
	progress_changed.emit(0, total_bytes_)
	return true


func cancel_import() -> void:
	if finishing_:
		return
	finishing_ = true
	close_files_()
	remove_file_(temporary_path_)
	queue_free()


func _process(_delta: float) -> void:
	if source_ == null or target_ == null:
		return
	for _chunk_index: int in range(kChunksPerFrame):
		var remaining: int = total_bytes_ - copied_bytes_
		if remaining <= 0:
			complete_copy_()
			return
		var count: int = mini(remaining, kCopyChunkSize)
		var bytes: PackedByteArray = source_.get_buffer(count)
		if bytes.size() != count or not target_.store_buffer(bytes):
			finish_(false, "", "", tr("复制模型文件失败。"))
			return
		copied_bytes_ += count
	progress_changed.emit(copied_bytes_, total_bytes_)


func complete_copy_() -> void:
	target_.flush()
	var write_error: Error = target_.get_error()
	close_files_()
	if write_error != OK:
		finish_(false, "", "", tr("写入模型文件失败：%s") %
			error_string(write_error))
		return
	var validation: Dictionary = validate_model_(temporary_path_)
	if not bool(validation.get("valid", false)):
		finish_(false, "", "", str(validation.get(
			"message", tr("所选文件不是有效的 KataGo 模型。")
		)))
		return
	var suffix: String = "bin.gz" if bool(validation.get("binary", false)) \
		else "txt.gz"
	var final_path: String = "%s/external-%s-model-%d.%s" % [
		kModelDirectory, model_role_, Time.get_ticks_usec(), suffix
	]
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path_),
		ProjectSettings.globalize_path(final_path)
	)
	if rename_error != OK:
		finish_(false, "", "", tr("保存外置模型失败：%s") %
			error_string(rename_error))
		return
	temporary_path_ = ""
	finish_(true, final_path, str(validation.get("name", "")), "")


func validate_model_(path: String) -> Dictionary:
	var header_result: Dictionary = read_gzip_header_(path)
	if not bool(header_result.get("valid", false)):
		return {
			"valid": false,
			"message": tr("无法解压模型文件，请选择标准 KataGo .bin.gz 或 .txt.gz 模型。")
		}
	var header_bytes: PackedByteArray = header_result.get(
		"bytes", PackedByteArray()
	)
	if header_bytes.is_empty():
		return {"valid": false, "message": tr("模型文件内容不完整。")}
	var header: String = header_bytes.get_string_from_ascii()
	var lines: PackedStringArray = header.split("\n", false)
	if lines.size() < 2:
		return {"valid": false, "message": tr("模型文件头无效。")}
	var model_name: String = lines[0].strip_edges()
	var version_text: String = lines[1].strip_edges()
	if model_name.is_empty() or not version_text.is_valid_int():
		return {"valid": false, "message": tr("模型文件头无效。")}
	var version: int = version_text.to_int()
	if version < 3 or version > 99:
		return {"valid": false, "message": tr("模型版本号无效。")}
	return {
		"valid": true,
		"binary": header.contains("@BIN@"),
		"name": model_name,
	}


func read_gzip_header_(path: String) -> Dictionary:
	var source: FileAccess = FileAccess.open(path, FileAccess.READ)
	if source == null:
		return {"valid": false}
	var gzip_magic: PackedByteArray = source.get_buffer(2)
	if gzip_magic.size() != 2 or gzip_magic[0] != 0x1f or gzip_magic[1] != 0x8b:
		source.close()
		return {"valid": false}
	source.seek(0)
	var gzip: StreamPeerGZIP = StreamPeerGZIP.new()
	if gzip.start_decompression(false, kValidationHeaderSize * 2) != OK:
		source.close()
		return {"valid": false}
	var header_bytes := PackedByteArray()
	while source.get_position() < source.get_length() \
			and header_bytes.size() < kValidationHeaderSize:
		var read_count: int = mini(
			kValidationInputChunkSize,
			source.get_length() - source.get_position()
		)
		var input: PackedByteArray = source.get_buffer(read_count)
		if input.size() != read_count:
			gzip.clear()
			source.close()
			return {"valid": false}
		var input_offset: int = 0
		while input_offset < input.size() \
				and header_bytes.size() < kValidationHeaderSize:
			var write_result: Array = gzip.put_partial_data(
				input.slice(input_offset)
			)
			if write_result.size() != 2 or int(write_result[0]) != OK:
				gzip.clear()
				source.close()
				return {"valid": false}
			var consumed: int = int(write_result[1])
			var available: int = gzip.get_available_bytes()
			if available > 0:
				var output_result: Array = gzip.get_data(available)
				if output_result.size() != 2 or int(output_result[0]) != OK:
					gzip.clear()
					source.close()
					return {"valid": false}
				var output: PackedByteArray = output_result[1]
				var needed: int = kValidationHeaderSize - header_bytes.size()
				header_bytes.append_array(output.slice(0, mini(output.size(), needed)))
			if consumed <= 0 and available <= 0:
				gzip.clear()
				source.close()
				return {"valid": false}
			input_offset += consumed
	gzip.clear()
	source.close()
	return {"valid": not header_bytes.is_empty(), "bytes": header_bytes}


func finish_(
	succeeded: bool,
	model_path: String,
	model_name: String,
	message: String
) -> void:
	if finishing_:
		return
	finishing_ = true
	set_process(false)
	close_files_()
	if not succeeded:
		remove_file_(temporary_path_)
	completed.emit(succeeded, model_path, model_name, message)
	queue_free()


func close_files_() -> void:
	if source_ != null:
		source_.close()
		source_ = null
	if target_ != null:
		target_.close()
		target_ = null


func remove_file_(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _exit_tree() -> void:
	close_files_()
