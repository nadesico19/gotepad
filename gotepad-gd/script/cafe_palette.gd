class_name CafePalette
extends RefCounted

# 榛木与奶油：通用控件和自绘 UI 共用的语义色。
const kBase: Color = Color("#211D19")
const kPanel: Color = Color("#2B2520")
const kRaised: Color = Color("#342C25")
const kInput: Color = Color("#191612")
const kBorder: Color = Color("#665443")
const kDivider: Color = Color("#483C31")
const kText: Color = Color("#EFE3CF")
const kSecondary: Color = Color("#C5B49D")
const kMuted: Color = Color("#A7957E")
const kAccent: Color = Color("#D0AD72")
const kAccentHover: Color = Color("#DEC18E")
const kAccentPressed: Color = Color("#BC965A")
const kSelection: Color = Color("#59472E")
const kSuccess: Color = Color("#A6B995")
const kInfo: Color = Color("#91ADB4")
const kWarning: Color = Color("#DCB876")
const kError: Color = Color("#D49A88")
const kDanger: Color = Color("#6A3E36")
const kOnAccent: Color = Color("#241B12")
const kOnDanger: Color = Color("#F4D9D1")
const kDisabledText: Color = Color("#8A7B69")
const kDisabledBackground: Color = Color("#393129")
const kDisabledOpacity: float = 0.45
const kSuccessBackground: Color = Color("#2B3427")
const kInfoBackground: Color = Color("#263135")
const kWarningBackground: Color = Color("#3C3020")
const kErrorBackground: Color = Color("#3C2924")
const kHover: Color = Color("#40362D")
const kDangerHover: Color = Color("#805047")
const kDangerPressed: Color = Color("#58322C")


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
	return kSecondary if button.disabled else kText
