#pragma once

#include <map>
#include <mutex>
#include <string>
#include "external/nlohmann_json/json.hpp"

namespace GotepadKataGo {
// Backend threads publish initialization/fallback state; the analysis thread reads copies.
inline std::mutex acceleration_mutex;
inline std::map<const void*, nlohmann::json> acceleration_handles;
inline void publish_acceleration(const void* owner, const nlohmann::json& state) {
  std::lock_guard<std::mutex> lock(acceleration_mutex);
  acceleration_handles[owner] = state;
}
inline void remove_acceleration(const void* owner) {
  std::lock_guard<std::mutex> lock(acceleration_mutex);
  acceleration_handles.erase(owner);
}
inline void fail_acceleration(const void* owner) {
  std::lock_guard<std::mutex> lock(acceleration_mutex);
  auto it = acceleration_handles.find(owner);
  if(it == acceleration_handles.end()) return;
  it->second["enabled"] = false;
  it->second["reason"] = "kernel_failed";
  it->second["kernelPath"] = "original";
  it->second["precision"]["experimentalFP16Compute"] = false;
}
inline nlohmann::json get_acceleration_status(const std::string& name, int version) {
  std::lock_guard<std::mutex> lock(acceleration_mutex);
  nlohmann::json result = {{"modelWhitelisted", false}, {"structureSupported", false},
    {"available", false}, {"enabled", false}, {"reason", "initializing"}, {"kernelPath", "original"}};
  size_t count = 0, enabled = 0;
  for(const auto& item : acceleration_handles) {
    if(item.second.at("model") != name || item.second.at("modelVersion") != version) continue;
    ++count;
    if(item.second.at("enabled").get<bool>()) ++enabled;
    // Keep a disabled handle's reason when not all handles are enabled.
    if(!result["available"].get<bool>() || !item.second.at("enabled").get<bool>()) {
      result["reason"] = item.second.at("reason");
      result["kernelPath"] = item.second.at("kernelPath");
      if(item.second.contains("precision")) result["precision"] = item.second.at("precision");
      result["structure"] = item.second.at("structure");
      result["structureSupported"] = item.second.at("structure").at("supported");
      result["modelWhitelisted"] = result["structureSupported"]; // Legacy report field, now structural.
    }
    result["available"] = true;
  }
  result["enabled"] = count > 0 && count == enabled;
  result["handleCount"] = count;
  result["enabledHandleCount"] = enabled;
  return result;
}
} // namespace GotepadKataGo
