class_name CafePalette
extends RefCounted

# 榛木与奶油：通用控件和自绘 UI 共用的语义色。
const kBase: Color = Color("#211D19")
const kPanel: Color = Color("#2B2520")
const kRaised: Color = Color("#342C25")
const kInput: Color = Color("#191612")
const kBorder: Color = Color("#A38A68")
const kDivider: Color = Color("#685744")
const kText: Color = Color("#F6EAD5")
const kSecondary: Color = Color("#D7C5AA")
const kMuted: Color = Color("#B9A58A")
const kAccent: Color = Color("#E0BA78")
const kAccentHover: Color = Color("#F2D49B")
const kAccentPressed: Color = Color("#CBA164")
const kSelection: Color = Color("#5F482A")
const kSuccess: Color = Color("#B6CEA0")
const kInfo: Color = Color("#A8C9D1")
const kWarning: Color = Color("#EDC982")
const kError: Color = Color("#ECB09B")
const kDanger: Color = Color("#75463C")
const kOnAccent: Color = Color("#241B12")
const kOnDanger: Color = Color("#FFE6DE")
const kDisabledText: Color = Color("#8A7B69")
const kDisabledBackground: Color = Color("#29241F")
const kSuccessBackground: Color = Color("#263220")
const kInfoBackground: Color = Color("#202F34")
const kWarningBackground: Color = Color("#3B2E1B")
const kErrorBackground: Color = Color("#39241F")
const kHover: Color = Color("#493B2E")
const kDangerHover: Color = Color("#875448")
const kDangerPressed: Color = Color("#5B3028")
const kDisabledBorder: Color = Color("#4D4237")
const kCheckboxBackground: Color = Color("#211D19")
const kCheckboxBorder: Color = Color("#F0D6A5")
const kPressedBackground: Color = Color("#483622")
const kDisabledOpacity: float = 0.45


# 深色面板上的禁用文字色不适合直接叠在木纹、榻榻米等纹理上。
# flat 按钮不会自动绘制 disabled 样式，自绘图标需补上衬底。
static func draw_disabled_backing(button: Button) -> void:
	if not button.disabled or not button.flat:
		return
	button.draw_style_box(
		button.get_theme_stylebox(&"disabled"),
		Rect2(Vector2.ZERO, button.size)
	)


static func button_icon_color(button: Button) -> Color:
	return kDisabledText if button.disabled else kText
