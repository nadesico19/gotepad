class_name KataGoTransport
extends Node

signal line_received(line: String)
signal log_received(line: String)
signal transport_error(message: String)
signal transport_stopped
signal transport_ready
signal recovery_started


func start_transport() -> bool:
	return false


func send_line(_line: String) -> bool:
	return false


func stop_transport() -> void:
	pass


func is_transport_running() -> bool:
	return false


func is_transport_initializing() -> bool:
	return false
