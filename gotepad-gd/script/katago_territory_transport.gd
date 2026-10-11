class_name KataGoTerritoryTransport
extends KataGoTransport

var backend_: KataGoTransport


func start_transport() -> bool:
	if is_transport_running():
		return true
	var config_error: Error = SettingsStore.write_managed_katago_territory_config()
	if config_error != OK:
		transport_error.emit(tr("无法创建数目配置：%s") % error_string(config_error))
		return false
	if backend_ != null:
		stop_transport()
	backend_ = KataGoAndroidTransport.new() if OS.get_name() == "Android" \
		else KataGoEmbeddedTransport.new()
	add_child(backend_)
	backend_.line_received.connect(line_received.emit)
	backend_.log_received.connect(log_received.emit)
	backend_.transport_error.connect(transport_error.emit)
	backend_.transport_stopped.connect(transport_stopped.emit)
	return bool(backend_.call(
		"start_custom_transport", KataGoEmbeddedTransport.kInstalledModelPath,
		"", SettingsStore.get_managed_katago_territory_config_path(), ""
	))


func send_line(line: String) -> bool:
	return backend_ != null and backend_.send_line(line)


func stop_transport() -> void:
	if backend_ == null:
		return
	backend_.stop_transport()
	backend_.queue_free()
	backend_ = null


func is_transport_running() -> bool:
	return backend_ != null and backend_.is_transport_running()


func _exit_tree() -> void:
	stop_transport()
