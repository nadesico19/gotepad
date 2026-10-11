#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <memory>

struct IOSModelPickerState;

class IOSModelFilePicker : public godot::RefCounted {
  GDCLASS(IOSModelFilePicker, godot::RefCounted)
protected:
  static void _bind_methods();
public:
  IOSModelFilePicker();
  bool open_file();
  void cancel();
  godot::Dictionary poll_result();
private:
  std::shared_ptr<IOSModelPickerState> state_;
};
