extends Node

const kLanguageNative: StringName = &"native"
const kLanguageSimplifiedChinese: StringName = &"zh_CN"

var language_: StringName = kLanguageSimplifiedChinese
var translations_: Dictionary = {
	kLanguageSimplifiedChinese: {
		"GNE0001": "命令已经执行。",
		"GNE0002": "坐标超出棋盘范围。",
		"GNE0003": "设置预置棋子失败。",
		"GNE0004": "命令无法撤销。",
		"GNE0005": "恢复预置棋子失败。",
		"GNE0006": "落子失败。",
		"GNE0007": "悔棋失败。",
		"GNE0008": "恢复被悔棋的棋子失败。",
		"GNE0009": "该位置的落子已经存在。",
		"GNE0010": "棋局漫游失败。",
		"GNE0011": "无效命令。",
		"GNE0012": "没有可撤销的命令。",
		"GNE0013": "未在指定位置找到落子。",
		"GNE0014": "没有可重做的命令。",

		"GNE0016": "笔记层级超出范围。",
		"GNE0017": "笔记标记坐标超出棋盘范围。",
		"GNE0018": "该位置已经有顺序标记。",
		"GNE0019": "该位置没有顺序标记。",
		"GNE0020": "该位置没有符号标记。",
		"GNE0021": "恢复笔记失败。",
		"GNE0022": "剪切棋局分支失败。",
		"GNE0023": "相同的预置局面分支已经存在。",
		"GNE0024": "棋子编号方式超出有效范围。",
		"GNE0025": "当前棋谱没有可供排版的笔记。",
		"GNE0026": "无法读取 PPTX 排版模板。",
		"GNE0027": "PPTX 排版模板无效。",
		"GNE0028": "无法写入 PPTX 文件。",
		"GNE0029": "棋谱结果（RE）不是有效的 SGF 格式。",
		"GNE0030": "棋谱信息中包含未知字段。",
		"GNE0031": "棋谱信息的填写格式无效。",
		"GNE0032": "恢复棋谱信息失败。",
		"GNE0033": "不支持所选的 PPTX 棋盘图片格式。",
		"GNE0034": "无法将棋盘图转换为 PNG。",
		"GNE0035": "当前预置节点无法修改，或修改没有产生实际变化。",
		"GNE0036": "修改后的预置局面包含没有气的棋块。",
		"GNE0037": "修改预置棋子后，后续棋局分支无法继续重放。",
		"GNE0038": "恢复预置节点修改失败。",
		"GNE0039": "棋谱没有可删除的旁支，或保留主干失败。",
		"GNE0040": "当前棋谱没有可清除的笔记。",
	}
}


func get_language() -> StringName:
	return language_


func set_language(language: StringName) -> bool:
	if language != kLanguageNative and not translations_.has(language):
		return false
	language_ = language
	return true


func register_language(language: StringName, messages: Dictionary) -> bool:
	if language == &"" or language == kLanguageNative:
		return false
	translations_[language] = messages.duplicate(true)
	return true


func localize(native_message: String) -> String:
	if language_ == kLanguageNative:
		return native_message
	var code: String = extract_code_(native_message)
	if code.is_empty():
		return native_message
	var table_value: Variant = translations_.get(language_, {})
	if table_value is not Dictionary:
		return native_message
	var table: Dictionary = Dictionary(table_value)
	var localized_value: Variant = table.get(code, "")
	if localized_value is not String:
		return native_message
	var localized_message: String = String(localized_value)
	if localized_message.is_empty():
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
