#pragma once

// Included only by the Android OpenCL target. Profiling is independent of O3 optimization.
#include <android/log.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <fstream>
#include <map>
#include <string>
#include <vector>

#include "external/nlohmann_json/json.hpp"
#include "neuralnet/openclincludes.h"
#include "katago_log_retention.hpp"

namespace GotepadKataGo {

class O3ProfileEvent final {
public:
  O3ProfileEvent() = default;
  O3ProfileEvent(const O3ProfileEvent&) = delete;
  O3ProfileEvent& operator=(const O3ProfileEvent&) = delete;
  ~O3ProfileEvent() { if (value != nullptr) clReleaseEvent(value); }
  cl_event value = nullptr;
};

class O3Profile final {
public:
  using Clock = std::chrono::steady_clock;
  using Json = nlohmann::json;
  static std::string device_string(cl_device_id device, cl_device_info key);
  void configure(cl_context context, cl_device_id device, bool requested,
                 const std::string& directory);
  void metadata(Json value);
  cl_command_queue queue_or(cl_command_queue fallback) const {
    return queue_ != nullptr ? queue_ : fallback;
  }
  bool sampling() const { return sampling_; }
  bool eligible() const { return eligible_; }
  void begin(int batch);
  void uploaded() { if (sampling_) uploaded_ = Clock::now(); }
  void submitted() { if (sampling_) submitted_ = Clock::now(); }
  void read_done() { if (sampling_) read_done_ = Clock::now(); }
  void record(O3ProfileEvent& event, const std::string& name);
  void set_shape(const std::string& value) { if (sampling_) shape_ = value; }
  void finish();
  ~O3Profile();
  O3Profile() = default;
  O3Profile(const O3Profile&) = delete;
  O3Profile& operator=(const O3Profile&) = delete;

private:
  struct Pending { cl_event event; std::string name; };
  struct Totals {
    uint64_t calls = 0;
    double execution_ms = 0;
    double queued_submit_ms = 0;
    double submit_start_ms = 0;
  };
  void write_(Json value);
  void report_(const char* reason);
  void clear_events_();
  static double milliseconds_(Clock::duration duration) {
    return std::chrono::duration<double, std::milli>(duration).count();
  }
  static constexpr int kWarmupBatches = 3;
  static constexpr int kSampleInterval = 8;
  bool eligible_ = false;
  bool sampling_ = false;
  cl_command_queue queue_ = nullptr;
  std::ofstream file_;
  static constexpr uint64_t kMaxFileBytes = 20ULL * 1024 * 1024;
  uint64_t file_bytes_ = 0;
  bool file_limit_reached_ = false;
  std::string session_;
  std::string shape_;
  int batch_ = 0;
  uint64_t batches_ = 0, rows_ = 0, samples_ = 0, errors_ = 0;
  uint64_t reported_batches_ = 0;
  double wall_ms_ = 0, upload_ms_ = 0, enqueue_ms_ = 0, read_ms_ = 0;
  double kernel_span_ms_ = 0, kernel_gap_ms_ = 0;
  std::map<int, uint64_t> batch_histogram_, sample_histogram_;
  std::map<std::string, Totals> totals_;
  std::vector<Pending> events_;
  Clock::time_point began_, uploaded_, submitted_, read_done_;
  Clock::time_point last_report_ = Clock::now();
};

inline std::string O3Profile::device_string(cl_device_id device, cl_device_info key) {
  size_t size = 0;
  if (clGetDeviceInfo(device, key, 0, nullptr, &size) != CL_SUCCESS || size == 0)
    return "unknown";
  std::vector<char> value(size + 1, 0);
  if (clGetDeviceInfo(device, key, size, value.data(), nullptr) != CL_SUCCESS)
    return "unknown";
  return value.data();
}

inline void O3Profile::configure(cl_context context, cl_device_id device,
                                 bool requested, const std::string& directory) {
  const std::string name = device_string(device, CL_DEVICE_NAME);
  eligible_ = true; // All Android OpenCL devices; precision/workgroup checks remain in the kernels.
  static std::atomic<unsigned> next_id{0};
  const auto epoch = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  session_ = std::to_string(epoch) + "-" + std::to_string(getpid()) + "-" +
             std::to_string(next_id.fetch_add(1));
  if (protect_log_directory(directory))
    file_.open(directory + "/o3-" + session_ + ".jsonl", std::ios::out);
  cl_int error = CL_SUCCESS;
  if (requested)
    queue_ = clCreateCommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &error);
  write_({{"type", "device"}, {"gpu", name},
          {"driver", device_string(device, CL_DRIVER_VERSION)},
          {"opencl", device_string(device, CL_DEVICE_VERSION)},
          {"extensions", device_string(device, CL_DEVICE_EXTENSIONS)},
          {"requested", requested}, {"profiling", queue_ != nullptr},
          {"queueError", error}, {"fileAvailable", file_.is_open()},
          {"kernelSelection", "see model record"}, {"warmupBatches", kWarmupBatches},
          {"sampleEveryBatches", kSampleInterval}});
}

inline void O3Profile::metadata(Json value) {
  if (eligible_) { value["type"] = "model"; write_(std::move(value)); }
}

inline void O3Profile::write_(Json value) {
  if (file_limit_reached_) return;
  value["schema"] = 1;
  value["session"] = session_;
  value["unixTimeMs"] = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  const std::string line = value.dump();
  // One compact JSON record per line, also available without private app access.
  if (file_.is_open()) {
    // Reserve room for a complete final record instead of truncating JSON.
    if (file_bytes_ + line.size() + 1 > kMaxFileBytes - 1024) {
      const std::string marker = Json{{"type", "loggingStopped"}, {"schema", 1},
          {"session", session_}, {"reason", "fileSizeLimit"},
          {"maxBytes", kMaxFileBytes}, {"incomplete", true}}.dump();
      file_ << marker << '\n';
      file_.close();
      file_limit_reached_ = true;
      __android_log_write(ANDROID_LOG_WARN, "GotepadO3Profile", marker.c_str());
      return;
    }
    file_ << line << '\n'; file_.flush();
    file_bytes_ += line.size() + 1;
  }
  __android_log_write(ANDROID_LOG_INFO, "GotepadO3Profile", line.c_str());
}

inline void O3Profile::begin(int batch) {
  if (queue_ == nullptr || file_limit_reached_) { sampling_ = false; return; }
  ++batches_;
  rows_ += batch;
  ++batch_histogram_[batch];
  batch_ = batch;
  sampling_ = batches_ > kWarmupBatches &&
              (batches_ - kWarmupBatches - 1) % kSampleInterval == 0;
  if (sampling_) began_ = Clock::now();
}

inline void O3Profile::record(O3ProfileEvent& event, const std::string& name) {
  if (event.value == nullptr) return;
  events_.push_back({event.value, name + shape_ + "/B=" + std::to_string(batch_)});
  event.value = nullptr;
  shape_.clear();
}

inline void O3Profile::clear_events_() {
  for (const auto& item : events_) clReleaseEvent(item.event);
  events_.clear();
}

inline void O3Profile::finish() {
  if (!sampling_) return;
  const auto ended = Clock::now();
  ++samples_;
  ++sample_histogram_[batch_];
  wall_ms_ += milliseconds_(ended - began_);
  upload_ms_ += milliseconds_(uploaded_ - began_);
  enqueue_ms_ += milliseconds_(submitted_ - uploaded_);
  read_ms_ += milliseconds_(read_done_ - submitted_);
  cl_ulong first = 0, last = 0;
  for (const auto& item : events_) {
    cl_ulong queued = 0, submit = 0, start = 0, end = 0;
    const bool ok =
        clGetEventProfilingInfo(item.event, CL_PROFILING_COMMAND_QUEUED, sizeof(queued), &queued, nullptr) == CL_SUCCESS &&
        clGetEventProfilingInfo(item.event, CL_PROFILING_COMMAND_SUBMIT, sizeof(submit), &submit, nullptr) == CL_SUCCESS &&
        clGetEventProfilingInfo(item.event, CL_PROFILING_COMMAND_START, sizeof(start), &start, nullptr) == CL_SUCCESS &&
        clGetEventProfilingInfo(item.event, CL_PROFILING_COMMAND_END, sizeof(end), &end, nullptr) == CL_SUCCESS;
    if (!ok || queued > submit || submit > start || start > end) { ++errors_; continue; }
    Totals& total = totals_[item.name];
    ++total.calls;
    total.execution_ms += (end - start) * 1e-6;
    total.queued_submit_ms += (submit - queued) * 1e-6;
    total.submit_start_ms += (start - submit) * 1e-6;
    if (first == 0) first = start;
    if (last != 0 && start > last) kernel_gap_ms_ += (start - last) * 1e-6;
    last = std::max(last, end);
  }
  if (first != 0) kernel_span_ms_ += (last - first) * 1e-6;
  clear_events_();
  sampling_ = false;
  if (ended - last_report_ >= std::chrono::seconds(5)) {
    report_("periodic");
    last_report_ = Clock::now();
  }
}

inline void O3Profile::report_(const char* reason) {
  if (queue_ == nullptr || batches_ == reported_batches_) return;
  double kernel_ms = 0;
  for (const auto& item : totals_) kernel_ms += item.second.execution_ms;
  Json histogram = Json::object(), sampled = Json::object();
  for (const auto& item : batch_histogram_) histogram[std::to_string(item.first)] = item.second;
  for (const auto& item : sample_histogram_) sampled[std::to_string(item.first)] = item.second;
  write_({{"type", "summary"}, {"reason", reason}, {"cumulative", true},
          {"batches", batches_}, {"rows", rows_}, {"samples", samples_},
          {"actualBatchHistogram", histogram}, {"sampledBatchHistogram", sampled},
          {"sampleBackendWallMs", wall_ms_}, {"samplePrepareUploadCpuMs", upload_ms_},
          {"sampleEnqueueCpuMs", enqueue_ms_}, {"sampleReadWaitCpuMs", read_ms_},
          {"sampleKernelMs", kernel_ms}, {"sampleKernelSpanMs", kernel_span_ms_},
          {"sampleBetweenKernelGapMs", kernel_gap_ms_}, {"eventErrors", errors_}});
  for (const auto& item : totals_) {
    const Totals& total = item.second;
    write_({{"type", "kernel"}, {"samples", samples_}, {"key", item.first},
            {"calls", total.calls}, {"totalMs", total.execution_ms},
            {"meanMs", total.execution_ms / total.calls},
            {"kernelPercent", kernel_ms > 0 ? 100 * total.execution_ms / kernel_ms : 0},
            {"queuedToSubmitMs", total.queued_submit_ms},
            {"submitToStartMs", total.submit_start_ms}});
  }
  reported_batches_ = batches_;
}

inline O3Profile::~O3Profile() {
  // Normal inference already performs blocking result reads; no extra clFinish.
  clear_events_();
  try { report_("shutdown"); } catch (...) { /* Diagnostics must not prevent cleanup. */ }
  if (queue_ != nullptr) clReleaseCommandQueue(queue_);
}

} // namespace GotepadKataGo
