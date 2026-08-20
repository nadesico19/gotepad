#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace nd::go::gdext {

// 棋盘图片识别器只负责把图像转换为候选盘面，不直接修改GoNotes。
// 用户确认候选结果后，界面再通过PresetCommand一次性提交预置棋子。
class GoBoardImageRecognizer final : public godot::RefCounted {
  GDCLASS(GoBoardImageRecognizer, godot::RefCounted)

public:
  [[nodiscard]] bool is_available() const noexcept;
  [[nodiscard]] godot::Dictionary recognize(
      const godot::PackedByteArray &rgba, int64_t width, int64_t height,
      int64_t board_size,
      const godot::PackedVector2Array &grid_corners = {}) const;

protected:
  static void _bind_methods();
};

} // namespace nd::go::gdext
