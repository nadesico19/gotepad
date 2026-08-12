// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#include "main.h"

#include <android/log.h>
#include <jni.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <exception>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace nd::go::katago::android {
namespace {
constexpr const char *kLogTag = "GotepadKataGoOpenCL";

std::string from_java_string_(JNIEnv *environment, jstring value) {
  if (value == nullptr)
    return {};
  const char *text = environment->GetStringUTFChars(value, nullptr);
  if (text == nullptr)
    return {};
  std::string result{text};
  environment->ReleaseStringUTFChars(value, text);
  return result;
}

jobjectArray to_java_array_(JNIEnv *environment,
                            const std::vector<std::string> &values) {
  jclass string_class = environment->FindClass("java/lang/String");
  jobjectArray result = environment->NewObjectArray(
      static_cast<jsize>(values.size()), string_class, nullptr);
  for (size_t index = 0; index < values.size(); ++index) {
    jstring value = environment->NewStringUTF(values[index].c_str());
    environment->SetObjectArrayElement(result, static_cast<jsize>(index),
                                       value);
    environment->DeleteLocalRef(value);
  }
  environment->DeleteLocalRef(string_class);
  return result;
}

bool readable_file_(const std::string &path) {
  const std::ifstream input(path, std::ios::binary);
  return input.good();
}
} // namespace

class OpenCLEngine final {
public:
  enum State : int32_t {
    kStopped = 0,
    kStarting = 1,
    kRunning = 2,
    kStopping = 3,
    kFailed = 4,
  };

  ~OpenCLEngine() { stop(); }

  bool start(std::string model_path, std::string config_path,
             std::string override_config);
  bool send_line(std::string line);
  std::vector<std::string> poll_lines();
  std::vector<std::string> poll_logs();
  void stop();
  int32_t state() const { return state_.load(std::memory_order_acquire); }
  std::string error() const;

private:
  void run_(std::string model_path, std::string config_path,
            std::string override_config);
  bool read_line_(std::string &line);
  void write_line_(const std::string &line);
  void write_log_(std::string line);
  void fail_(std::string message);

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

bool OpenCLEngine::start(std::string model_path, std::string config_path,
                         std::string override_config) {
  const int32_t current_state = state();
  if (current_state == kStarting || current_state == kRunning)
    return true;
  if (current_state == kStopping)
    return false;
  if (worker_.joinable()) {
    if (worker_.get_id() == std::this_thread::get_id())
      worker_.detach();
    else
      worker_.join();
  }
  if (!readable_file_(model_path)) {
    fail_("Unable to open the OpenCL KataGo model: " + model_path);
    return false;
  }
  if (!readable_file_(config_path)) {
    fail_("Unable to open the OpenCL KataGo config: " + config_path);
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
  write_log_("Creating the isolated OpenCL KataGo worker thread.");
  try {
    worker_ = std::thread(&OpenCLEngine::run_, this, std::move(model_path),
                          std::move(config_path), std::move(override_config));
  } catch (const std::exception &error) {
    fail_(std::string("Unable to create the OpenCL KataGo worker: ") +
          error.what());
    return false;
  } catch (...) {
    fail_("Unable to create the OpenCL KataGo worker");
    return false;
  }
  return true;
}

bool OpenCLEngine::send_line(std::string line) {
  const int32_t current_state = state();
  if (current_state != kStarting && current_state != kRunning)
    return false;
  {
    const std::lock_guard<std::mutex> lock(input_mutex_);
    if (input_closed_)
      return false;
    input_lines_.push_back(std::move(line));
  }
  input_changed_.notify_one();
  return true;
}

std::vector<std::string> OpenCLEngine::poll_lines() {
  std::vector<std::string> result{};
  const std::lock_guard<std::mutex> lock(output_mutex_);
  result.reserve(output_lines_.size());
  while (!output_lines_.empty()) {
    result.push_back(std::move(output_lines_.front()));
    output_lines_.pop_front();
  }
  return result;
}

std::vector<std::string> OpenCLEngine::poll_logs() {
  std::vector<std::string> result{};
  const std::lock_guard<std::mutex> lock(output_mutex_);
  result.reserve(log_lines_.size());
  while (!log_lines_.empty()) {
    result.push_back(std::move(log_lines_.front()));
    log_lines_.pop_front();
  }
  return result;
}

void OpenCLEngine::stop() {
  const int32_t current_state = state();
  if (current_state == kStarting || current_state == kRunning) {
    state_.store(kStopping, std::memory_order_release);
    {
      const std::lock_guard<std::mutex> lock(input_mutex_);
      input_lines_.push_back(
          R"({"id":"gotepad-opencl-shutdown","action":"terminate_all"})");
      input_closed_ = true;
    }
    input_changed_.notify_all();
  }
  if (worker_.joinable()) {
    if (worker_.get_id() == std::this_thread::get_id())
      worker_.detach();
    else
      worker_.join();
  }
  if (state() != kFailed)
    state_.store(kStopped, std::memory_order_release);
}

std::string OpenCLEngine::error() const {
  const std::lock_guard<std::mutex> lock(error_mutex_);
  return error_message_;
}

void OpenCLEngine::run_(std::string model_path, std::string config_path,
                        std::string override_config) {
  try {
    std::vector<std::string> arguments{"analysis",
                                       "-model",
                                       std::move(model_path),
                                       "-config",
                                       std::move(config_path),
                                       "-quit-without-waiting"};
    if (!override_config.empty()) {
      arguments.push_back("-override-config");
      arguments.push_back(std::move(override_config));
    }
    state_.store(kRunning, std::memory_order_release);
    write_log_("OpenCL KataGo is loading its configuration and model.");
    const int result = MainCmds::analysisEmbedded(
        arguments, [this](std::string &line) { return read_line_(line); },
        [this](const std::string &line) { write_line_(line); });
    if (result == 0) {
      state_.store(kStopped, std::memory_order_release);
    } else {
      fail_("OpenCL KataGo exited with code " + std::to_string(result));
    }
  } catch (const std::exception &error) {
    fail_(error.what());
  } catch (...) {
    fail_("OpenCL KataGo failed with an unknown native exception");
  }
}

bool OpenCLEngine::read_line_(std::string &line) {
  std::unique_lock<std::mutex> lock(input_mutex_);
  input_changed_.wait(
      lock, [this] { return input_closed_ || !input_lines_.empty(); });
  if (input_lines_.empty())
    return false;
  line = std::move(input_lines_.front());
  input_lines_.pop_front();
  return true;
}

void OpenCLEngine::write_line_(const std::string &line) {
  const std::lock_guard<std::mutex> lock(output_mutex_);
  output_lines_.push_back(line);
}

void OpenCLEngine::write_log_(std::string line) {
  __android_log_write(ANDROID_LOG_INFO, kLogTag, line.c_str());
  const std::lock_guard<std::mutex> lock(output_mutex_);
  log_lines_.push_back(std::move(line));
}

void OpenCLEngine::fail_(std::string message) {
  __android_log_write(ANDROID_LOG_ERROR, kLogTag, message.c_str());
  {
    const std::lock_guard<std::mutex> lock(error_mutex_);
    error_message_ = std::move(message);
  }
  state_.store(kFailed, std::memory_order_release);
}

OpenCLEngine &engine_() {
  static OpenCLEngine engine{};
  return engine;
}
} // namespace nd::go::katago::android

extern "C" JNIEXPORT jboolean JNICALL
Java_com_godot_game_KataGoOpenCLService_nativeStart(JNIEnv *environment, jclass,
                                                    jstring model_path,
                                                    jstring config_path,
                                                    jstring override_config) {
  return nd::go::katago::android::engine_().start(
      nd::go::katago::android::from_java_string_(environment, model_path),
      nd::go::katago::android::from_java_string_(environment, config_path),
      nd::go::katago::android::from_java_string_(environment, override_config));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_godot_game_KataGoOpenCLService_nativeSendLine(JNIEnv *environment,
                                                       jclass, jstring line) {
  return nd::go::katago::android::engine_().send_line(
      nd::go::katago::android::from_java_string_(environment, line));
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_godot_game_KataGoOpenCLService_nativePollLines(JNIEnv *environment,
                                                        jclass) {
  return nd::go::katago::android::to_java_array_(
      environment, nd::go::katago::android::engine_().poll_lines());
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_godot_game_KataGoOpenCLService_nativePollLogs(JNIEnv *environment,
                                                       jclass) {
  return nd::go::katago::android::to_java_array_(
      environment, nd::go::katago::android::engine_().poll_logs());
}

extern "C" JNIEXPORT void JNICALL
Java_com_godot_game_KataGoOpenCLService_nativeStop(JNIEnv *, jclass) {
  nd::go::katago::android::engine_().stop();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_godot_game_KataGoOpenCLService_nativeGetState(JNIEnv *, jclass) {
  return nd::go::katago::android::engine_().state();
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_godot_game_KataGoOpenCLService_nativeGetError(JNIEnv *environment,
                                                       jclass) {
  const std::string error = nd::go::katago::android::engine_().error();
  return environment->NewStringUTF(error.c_str());
}
