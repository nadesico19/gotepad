// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#ifdef GOTEPAD_KATAGO_EMBEDDED
#include "main.h"
#include <android/log.h>
#endif

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <exception>
#include <fstream>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace nd::go::katago::gdext {
namespace {
std::string utf8_text_(const godot::String &value) {
  const godot::CharString utf8 = value.utf8();
  return {utf8.get_data(), static_cast<size_t>(utf8.length())};
}

bool readable_file_(const std::string &path) {
  const std::ifstream input(path, std::ios::binary);
  return input.good();
}
} // namespace

class KataGoEmbeddedEngine final : public godot::RefCounted {
  GDCLASS(KataGoEmbeddedEngine, godot::RefCounted)

public:
  enum State : int32_t {
    kStopped = 0,
    kStarting = 1,
    kRunning = 2,
    kStopping = 3,
    kFailed = 4,
  };

  ~KataGoEmbeddedEngine() override { stop_engine(); }

  bool start_engine(const godot::String &model_path,
                    const godot::String &human_model_path,
                    const godot::String &config_path,
                    const godot::String &override_config);
  bool send_line(const godot::String &line);
  godot::PackedStringArray poll_lines();
  godot::PackedStringArray poll_logs();
  void stop_engine();
  int32_t get_state() const { return state_.load(std::memory_order_acquire); }
  godot::String get_error() const;

protected:
  static void _bind_methods();

private:
  void run_(std::string model_path, std::string human_model_path,
            std::string config_path,
            std::string override_config);
  bool read_line_(std::string &line);
  void write_line_(const std::string &line);
  void write_log_(std::string line);
  void set_error_(std::string message);

  std::atomic<int32_t> state_{kStopped};
  std::thread worker_{};

  mutable std::mutex input_mutex_{};
  std::condition_variable input_changed_{};
  std::deque<std::string> input_lines_{};
  bool input_closed_{false};

  mutable std::mutex output_mutex_{};
  std::deque<std::string> output_lines_{};
  std::deque<std::string> log_lines_{};

  mutable std::mutex error_mutex_{};
  std::string error_message_{};
};

void KataGoEmbeddedEngine::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD(
                                  "start_engine", "model_path",
                                  "human_model_path", "config_path",
                                  "override_config"),
                              &KataGoEmbeddedEngine::start_engine);
  godot::ClassDB::bind_method(godot::D_METHOD("send_line", "line"),
                              &KataGoEmbeddedEngine::send_line);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_lines"),
                              &KataGoEmbeddedEngine::poll_lines);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_logs"),
                              &KataGoEmbeddedEngine::poll_logs);
  godot::ClassDB::bind_method(godot::D_METHOD("stop_engine"),
                              &KataGoEmbeddedEngine::stop_engine);
  godot::ClassDB::bind_method(godot::D_METHOD("get_state"),
                              &KataGoEmbeddedEngine::get_state);
  godot::ClassDB::bind_method(godot::D_METHOD("get_error"),
                              &KataGoEmbeddedEngine::get_error);

  godot::ClassDB::bind_integer_constant(get_class_static(), "State",
                                        "STATE_STOPPED", kStopped);
  godot::ClassDB::bind_integer_constant(get_class_static(), "State",
                                        "STATE_STARTING", kStarting);
  godot::ClassDB::bind_integer_constant(get_class_static(), "State",
                                        "STATE_RUNNING", kRunning);
  godot::ClassDB::bind_integer_constant(get_class_static(), "State",
                                        "STATE_STOPPING", kStopping);
  godot::ClassDB::bind_integer_constant(get_class_static(), "State",
                                        "STATE_FAILED", kFailed);
}

bool KataGoEmbeddedEngine::start_engine(const godot::String &model_path,
                                        const godot::String &human_model_path,
                                        const godot::String &config_path,
                                        const godot::String &override_config) {
#ifndef GOTEPAD_KATAGO_EMBEDDED
  static_cast<void>(model_path);
  static_cast<void>(human_model_path);
  static_cast<void>(config_path);
  static_cast<void>(override_config);
  set_error_("Embedded KataGo is not available on this platform");
  state_.store(kFailed, std::memory_order_release);
  return false;
#else
  const int32_t state = get_state();
  if (state == kStarting || state == kRunning)
    return true;
  if (state == kStopping)
    return false;
  if (worker_.joinable())
    worker_.join();

  const std::string model = utf8_text_(model_path);
  const std::string human_model = utf8_text_(human_model_path);
  const std::string config = utf8_text_(config_path);
  if (!readable_file_(model)) {
    set_error_("Unable to open embedded KataGo model: " + model);
    state_.store(kFailed, std::memory_order_release);
    return false;
  }
  if (!human_model.empty() && !readable_file_(human_model)) {
    set_error_("Unable to open embedded KataGo Human SL model: " +
               human_model);
    state_.store(kFailed, std::memory_order_release);
    return false;
  }
  if (!readable_file_(config)) {
    set_error_("Unable to open embedded KataGo config: " + config);
    state_.store(kFailed, std::memory_order_release);
    return false;
  }

  {
    const std::lock_guard<std::mutex> lock(input_mutex_);
    input_lines_.clear();
    input_closed_ = false;
  }
  {
    const std::lock_guard<std::mutex> lock(output_mutex_);
    output_lines_.clear();
    log_lines_.clear();
  }
  {
    const std::lock_guard<std::mutex> lock(error_mutex_);
    error_message_.clear();
  }

  state_.store(kStarting, std::memory_order_release);
  write_log_("Creating embedded KataGo worker thread.");
  try {
    worker_ = std::thread(&KataGoEmbeddedEngine::run_, this, model,
                          human_model, config, utf8_text_(override_config));
  } catch (const std::exception &error) {
    set_error_(std::string("Unable to create embedded KataGo worker thread: ") +
               error.what());
    write_log_(std::string("Embedded KataGo thread creation failed: ") +
               error.what());
    state_.store(kFailed, std::memory_order_release);
    return false;
  } catch (...) {
    set_error_("Unable to create embedded KataGo worker thread");
    write_log_("Embedded KataGo thread creation failed with an unknown error.");
    state_.store(kFailed, std::memory_order_release);
    return false;
  }
  return true;
#endif
}

bool KataGoEmbeddedEngine::send_line(const godot::String &line) {
  const int32_t state = get_state();
  if (state != kStarting && state != kRunning)
    return false;
  {
    const std::lock_guard<std::mutex> lock(input_mutex_);
    if (input_closed_)
      return false;
    input_lines_.push_back(utf8_text_(line));
  }
  input_changed_.notify_one();
  return true;
}

godot::PackedStringArray KataGoEmbeddedEngine::poll_lines() {
  godot::PackedStringArray result{};
  const std::lock_guard<std::mutex> lock(output_mutex_);
  while (!output_lines_.empty()) {
    result.push_back(godot::String::utf8(output_lines_.front().c_str()));
    output_lines_.pop_front();
  }
  return result;
}

godot::PackedStringArray KataGoEmbeddedEngine::poll_logs() {
  godot::PackedStringArray result{};
  const std::lock_guard<std::mutex> lock(output_mutex_);
  while (!log_lines_.empty()) {
    result.push_back(godot::String::utf8(log_lines_.front().c_str()));
    log_lines_.pop_front();
  }
  return result;
}

void KataGoEmbeddedEngine::stop_engine() {
  const int32_t state = get_state();
  if (state == kStarting || state == kRunning) {
    state_.store(kStopping, std::memory_order_release);
    {
      const std::lock_guard<std::mutex> lock(input_mutex_);
      input_lines_.push_back(
          R"({"id":"gotepad-shutdown","action":"terminate_all"})");
      input_closed_ = true;
    }
    input_changed_.notify_all();
  }
  if (worker_.joinable())
    worker_.join();
  if (get_state() != kFailed)
    state_.store(kStopped, std::memory_order_release);
}

godot::String KataGoEmbeddedEngine::get_error() const {
  const std::lock_guard<std::mutex> lock(error_mutex_);
  return godot::String::utf8(error_message_.c_str());
}

void KataGoEmbeddedEngine::run_(std::string model_path,
                                std::string human_model_path,
                                std::string config_path,
                                std::string override_config) {
#ifdef GOTEPAD_KATAGO_EMBEDDED
  try {
    std::vector<std::string> arguments{"analysis",
                                       "-model",
                                       std::move(model_path),
                                       "-config",
                                       std::move(config_path),
                                       "-quit-without-waiting"};
    if (!human_model_path.empty()) {
      arguments.push_back("-human-model");
      arguments.push_back(std::move(human_model_path));
    }
    if (!override_config.empty()) {
      arguments.push_back("-override-config");
      arguments.push_back(std::move(override_config));
    }
    state_.store(kRunning, std::memory_order_release);
    write_log_("Embedded KataGo is loading its configuration and model.");
    const int result = MainCmds::analysisEmbedded(
        arguments, [this](std::string &line) { return read_line_(line); },
        [this](const std::string &line) { write_line_(line); });
    if (result != 0) {
      set_error_("Embedded KataGo exited with code " + std::to_string(result));
      state_.store(kFailed, std::memory_order_release);
    } else {
      state_.store(kStopped, std::memory_order_release);
    }
  } catch (const std::exception &error) {
    set_error_(error.what());
    write_log_(std::string("Embedded KataGo failed: ") + error.what());
    state_.store(kFailed, std::memory_order_release);
  } catch (...) {
    set_error_("Embedded KataGo failed with an unknown native exception");
    write_log_("Embedded KataGo failed with an unknown native exception.");
    state_.store(kFailed, std::memory_order_release);
  }
#else
  static_cast<void>(model_path);
  static_cast<void>(human_model_path);
  static_cast<void>(config_path);
  static_cast<void>(override_config);
  set_error_("Embedded KataGo is not available on this platform");
  state_.store(kFailed, std::memory_order_release);
#endif
}

bool KataGoEmbeddedEngine::read_line_(std::string &line) {
  std::unique_lock<std::mutex> lock(input_mutex_);
  input_changed_.wait(
      lock, [this] { return input_closed_ || !input_lines_.empty(); });
  if (input_lines_.empty())
    return false;
  line = std::move(input_lines_.front());
  input_lines_.pop_front();
  return true;
}

void KataGoEmbeddedEngine::write_line_(const std::string &line) {
  const std::lock_guard<std::mutex> lock(output_mutex_);
  output_lines_.push_back(line);
}

void KataGoEmbeddedEngine::write_log_(std::string line) {
#ifdef GOTEPAD_KATAGO_EMBEDDED
  __android_log_write(ANDROID_LOG_INFO, "GotepadKataGo", line.c_str());
#endif
  const std::lock_guard<std::mutex> lock(output_mutex_);
  log_lines_.push_back(std::move(line));
}

void KataGoEmbeddedEngine::set_error_(std::string message) {
#ifdef GOTEPAD_KATAGO_EMBEDDED
  __android_log_write(ANDROID_LOG_ERROR, "GotepadKataGo", message.c_str());
#endif
  const std::lock_guard<std::mutex> lock(error_mutex_);
  error_message_ = std::move(message);
}

void initialize_katago_gdext(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
    return;
  GDREGISTER_CLASS(KataGoEmbeddedEngine)
}

void uninitialize_katago_gdext(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
    return;
}
} // namespace nd::go::katago::gdext

#ifndef GOTEPAD_KATAGO_MERGED
extern "C" {
GDExtensionBool GDE_EXPORT
katago_gdext_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                          const GDExtensionClassLibraryPtr library,
                          GDExtensionInitialization *initialization) {
  godot::GDExtensionBinding::InitObject init_object(get_proc_address, library,
                                                    initialization);
  init_object.register_initializer(
      nd::go::katago::gdext::initialize_katago_gdext);
  init_object.register_terminator(
      nd::go::katago::gdext::uninitialize_katago_gdext);
  init_object.set_minimum_library_initialization_level(
      godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return init_object.init();
}
}
#endif
