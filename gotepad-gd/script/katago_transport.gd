class_name KataGoTransport
extends Node

signal line_received(line: String)
signal transport_error(message: String)
signal transport_stopped


func start_transport() -> bool:
	return false


func send_line(_line: String) -> bool:
	return false


func stop_transport() -> void:
	pass


func is_transport_running() -> bool:
	return false
