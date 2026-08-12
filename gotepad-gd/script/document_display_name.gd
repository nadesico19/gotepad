class_name DocumentDisplayName
extends RefCounted

const kAndroidHostClass := "com.godot.game.GodotApp"
const kMaximumLength := 160


static func from_path(path: String) -> String:
	if path.is_empty():
		return ""
	if OS.get_name() != "Android" or not path.begins_with("content://"):
		return sanitize(path.get_file())

	var provider_name: String = android_provider_name_(path)
	if not provider_name.is_empty():
		return provider_name
	return fallback_uri_name_(path)


static func sanitize(value: String) -> String:
	var leaf_name: String = value.replace("\\", "/").get_file()
	var clean_name := ""
	for index: int in range(leaf_name.length()):
		var codepoint: int = leaf_name.unicode_at(index)
		if codepoint >= 32 and codepoint != 127:
			clean_name += leaf_name.substr(index, 1)
	clean_name = clean_name.strip_edges()
	if clean_name.length() > kMaximumLength:
		clean_name = clean_name.left(kMaximumLength).strip_edges()
	return clean_name


static func android_provider_name_(uri: String) -> String:
	var host_class: Variant = JavaClassWrapper.wrap(kAndroidHostClass)
	if host_class == null:
		return ""
	var value: Variant = host_class.getDocumentDisplayName(uri)
	if value == null:
		return ""
	return sanitize(str(value))


static func fallback_uri_name_(uri: String) -> String:
	# URI 只在这里为标题显示而解码；文件访问始终使用原始 content:// URI。
	var display_uri: String = uri.get_slice("#", 0).get_slice("?", 0)
	return sanitize(display_uri.uri_decode())
