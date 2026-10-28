#pragma once

#include <atomic>
#include <chrono>
#include <mutex>
#include "external/nlohmann_json/json.hpp"

namespace GotepadKataGo {
using DiagnosticClock = std::chrono::steady_clock;
inline std::atomic<unsigned> diagnostic_handles{0};
inline std::mutex diagnostic_environment_mutex;
inline nlohmann::json diagnostic_environment = {{"available", false}};
// Populated by the evaluator on the same server thread, consumed once by getOutput.
struct DiagnosticBatchContext {
  double server_wait_ms = 0;
  double feature_ms = 0;
  double queue_ms = 0;
  unsigned rows = 0;
};
inline thread_local DiagnosticBatchContext diagnostic_batch;
inline double diagnostic_ms(DiagnosticClock::duration duration) {
  return std::chrono::duration<double, std::milli>(duration).count();
}
inline nlohmann::json get_diagnostic_environment() {
  const std::lock_guard<std::mutex> lock(diagnostic_environment_mutex);
  return diagnostic_environment;
}
inline void set_diagnostic_environment(nlohmann::json value) {
  const std::lock_guard<std::mutex> lock(diagnostic_environment_mutex);
  diagnostic_environment = std::move(value);
}
} // namespace GotepadKataGo
