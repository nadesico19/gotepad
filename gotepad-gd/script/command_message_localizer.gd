extends Node


func localize(native_message: String) -> String:
	var code: String = extract_code_(native_message)
	if code.is_empty():
		return native_message
	var localized_message: String = tr(code)
	if localized_message == code:
		return native_message
	return localized_message


func extract_code_(native_message: String) -> String:
	if native_message.length() < 9 or not native_message.begins_with("[GNE"):
		return ""
	if native_message.substr(8, 1) != "]":
		return ""
	var number: String = native_message.substr(4, 4)
	if not number.is_valid_int():
		return ""
	return native_message.substr(1, 7)
