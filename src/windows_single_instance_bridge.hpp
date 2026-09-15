// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

namespace nd::go::gdext {
class WindowsSingleInstanceBridge final : public godot::RefCounted {
  GDCLASS(WindowsSingleInstanceBridge, godot::RefCounted)

public:
  WindowsSingleInstanceBridge();
  ~WindowsSingleInstanceBridge() override;

  bool start_or_forward(const godot::PackedStringArray &paths);
  [[nodiscard]] godot::Array poll_requests();
  [[nodiscard]] godot::String get_error() const;

protected:
  static void _bind_methods();

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
} // namespace nd::go::gdext
