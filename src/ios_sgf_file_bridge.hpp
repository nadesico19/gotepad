#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <memory>

struct IOSSGFPickerState;

class IOSSGFFileBridge : public godot::RefCounted {
  GDCLASS(IOSSGFFileBridge, godot::RefCounted)
protected:
  static void _bind_methods();
public:
  IOSSGFFileBridge();
  bool open_file();
  bool open_image();
  bool open_camera();
  bool open_image_source(const godot::String& title, const godot::String& album_label, const godot::String& file_label, const godot::String& cancel_label);
  bool export_file(const godot::String& path);
  bool overwrite_file(const godot::String& path, const godot::String& bookmark);
  void cancel();
  godot::Dictionary poll_result();
  godot::Array poll_external_files();
private:
  bool open_picker_(bool image, const godot::String& export_path);
  std::shared_ptr<IOSSGFPickerState> state_;
};

