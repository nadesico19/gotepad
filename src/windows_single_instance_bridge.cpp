// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#include "windows_single_instance_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/char_string.hpp>

#include <atomic>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <thread>
#endif

namespace nd::go::gdext {
namespace {
#ifdef _WIN32
inline constexpr wchar_t kInstanceMutexName[] =
    L"Local\\Gotepad.SgfSingleInstance.v1";
inline constexpr wchar_t kOpenRequestPipeName[] =
    L"\\\\.\\pipe\\Gotepad.SgfOpen.v1";
inline constexpr uint32_t kPacketMagic = 0x47534731U;
inline constexpr uint32_t kShutdownPacketMagic = 0x47534758U;
inline constexpr uint32_t kMaximumPathCount = 256U;
inline constexpr uint32_t kMaximumPathBytes = 128U * 1024U;
inline constexpr DWORD kForwardRetryMilliseconds = 5000U;

struct PacketHeader {
  uint32_t magic{};
  uint32_t path_count{};
};

bool write_all_(HANDLE pipe, const void *data, size_t size) {
  const auto *cursor = static_cast<const uint8_t *>(data);
  while (size > 0) {
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(size, static_cast<size_t>(MAXDWORD)));
    DWORD written{};
    if (!WriteFile(pipe, cursor, chunk, &written, nullptr) || written == 0)
      return false;
    cursor += written;
    size -= written;
  }
  return true;
}

bool read_all_(HANDLE pipe, void *data, size_t size) {
  auto *cursor = static_cast<uint8_t *>(data);
  while (size > 0) {
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(size, static_cast<size_t>(MAXDWORD)));
    DWORD read{};
    if (!ReadFile(pipe, cursor, chunk, &read, nullptr) || read == 0)
      return false;
    cursor += read;
    size -= read;
  }
  return true;
}

std::vector<std::string>
utf8_paths_(const godot::PackedStringArray &paths) {
  std::vector<std::string> result{};
  const int64_t count = std::min<int64_t>(paths.size(), kMaximumPathCount);
  result.reserve(static_cast<size_t>(count));
  for (int64_t index = 0; index < count; ++index) {
    const godot::CharString utf8 = paths[index].utf8();
    if (utf8.length() <= 0 ||
        utf8.length() > static_cast<int64_t>(kMaximumPathBytes))
      continue;
    result.emplace_back(utf8.get_data(), static_cast<size_t>(utf8.length()));
  }
  return result;
}

bool write_packet_(HANDLE pipe, uint32_t magic,
                   const std::vector<std::string> &paths) {
  const PacketHeader header{magic, static_cast<uint32_t>(paths.size())};
  if (!write_all_(pipe, &header, sizeof(header)))
    return false;
  for (const auto &path : paths) {
    const uint32_t length = static_cast<uint32_t>(path.size());
    if (!write_all_(pipe, &length, sizeof(length)) ||
        !write_all_(pipe, path.data(), path.size()))
      return false;
  }
  return true;
}

bool read_packet_(HANDLE pipe, uint32_t &magic,
                  std::vector<std::string> &paths) {
  PacketHeader header{};
  if (!read_all_(pipe, &header, sizeof(header)) ||
      header.path_count > kMaximumPathCount)
    return false;
  magic = header.magic;
  paths.clear();
  paths.reserve(header.path_count);
  for (uint32_t index = 0; index < header.path_count; ++index) {
    uint32_t length{};
    if (!read_all_(pipe, &length, sizeof(length)) ||
        length > kMaximumPathBytes)
      return false;
    std::string path(length, '\0');
    if (length > 0 && !read_all_(pipe, path.data(), length))
      return false;
    paths.push_back(std::move(path));
  }
  return true;
}

HANDLE connect_to_primary_() {
  const uint64_t deadline =
      GetTickCount64() + static_cast<uint64_t>(kForwardRetryMilliseconds);
  do {
    HANDLE pipe = CreateFileW(kOpenRequestPipeName, GENERIC_WRITE, 0, nullptr,
                              OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      ULONG primary_process_id{};
      if (GetNamedPipeServerProcessId(pipe, &primary_process_id) != FALSE &&
          primary_process_id != 0)
        static_cast<void>(AllowSetForegroundWindow(primary_process_id));
      return pipe;
    }
    if (GetLastError() == ERROR_PIPE_BUSY)
      static_cast<void>(WaitNamedPipeW(kOpenRequestPipeName, 200U));
    else
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
  } while (GetTickCount64() < deadline);
  return INVALID_HANDLE_VALUE;
}

bool send_packet_to_primary_(uint32_t magic,
                             const std::vector<std::string> &paths) {
  HANDLE pipe = connect_to_primary_();
  if (pipe == INVALID_HANDLE_VALUE)
    return false;
  const bool written = write_packet_(pipe, magic, paths);
  CloseHandle(pipe);
  return written;
}
#endif
} // namespace

struct WindowsSingleInstanceBridge::Impl {
  godot::String error{};
#ifdef _WIN32
  HANDLE instance_mutex{nullptr};
  std::atomic_bool stopping{false};
  std::thread listener{};
  std::mutex requests_mutex{};
  std::deque<std::vector<std::string>> requests{};
#endif
};

WindowsSingleInstanceBridge::WindowsSingleInstanceBridge()
    : impl_(std::make_unique<Impl>()) {}

WindowsSingleInstanceBridge::~WindowsSingleInstanceBridge() {
#ifdef _WIN32
  if (impl_->listener.joinable()) {
    impl_->stopping.store(true, std::memory_order_release);
    static_cast<void>(send_packet_to_primary_(kShutdownPacketMagic, {}));
    static_cast<void>(CancelSynchronousIo(impl_->listener.native_handle()));
    impl_->listener.join();
  }
  if (impl_->instance_mutex != nullptr)
    CloseHandle(impl_->instance_mutex);
#endif
}

void WindowsSingleInstanceBridge::_bind_methods() {
  godot::ClassDB::bind_method(
      godot::D_METHOD("start_or_forward", "paths"),
      &WindowsSingleInstanceBridge::start_or_forward);
  godot::ClassDB::bind_method(
      godot::D_METHOD("poll_requests"),
      &WindowsSingleInstanceBridge::poll_requests);
  godot::ClassDB::bind_method(godot::D_METHOD("get_error"),
                              &WindowsSingleInstanceBridge::get_error);
}

bool WindowsSingleInstanceBridge::start_or_forward(
    const godot::PackedStringArray &paths) {
#ifdef _WIN32
  if (impl_->instance_mutex != nullptr || impl_->listener.joinable())
    return true;
  const std::vector<std::string> forwarded_paths = utf8_paths_(paths);
  HANDLE instance_mutex =
      CreateMutexW(nullptr, FALSE, kInstanceMutexName);
  if (instance_mutex == nullptr) {
    impl_->error = "Unable to create the Gotepad single-instance mutex";
    return true;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(instance_mutex);
    if (forwarded_paths.empty())
      return true;
    if (send_packet_to_primary_(kPacketMagic, forwarded_paths))
      return false;
    impl_->error = "Unable to contact the existing Gotepad process";
    return true;
  }
  impl_->instance_mutex = instance_mutex;
  impl_->stopping.store(false, std::memory_order_release);
  impl_->listener = std::thread([this]() {
    while (!impl_->stopping.load(std::memory_order_acquire)) {
      HANDLE pipe = CreateNamedPipeW(
          kOpenRequestPipeName, PIPE_ACCESS_INBOUND,
          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
              PIPE_REJECT_REMOTE_CLIENTS,
          PIPE_UNLIMITED_INSTANCES, 64U * 1024U, 64U * 1024U, 0, nullptr);
      if (pipe == INVALID_HANDLE_VALUE)
        break;
      const bool connected = ConnectNamedPipe(pipe, nullptr) != FALSE ||
                             GetLastError() == ERROR_PIPE_CONNECTED;
      uint32_t magic{};
      std::vector<std::string> request{};
      const bool received = connected && read_packet_(pipe, magic, request);
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
      if (!received)
        continue;
      if (magic == kShutdownPacketMagic)
        break;
      if (magic != kPacketMagic)
        continue;
      const std::lock_guard<std::mutex> lock(impl_->requests_mutex);
      impl_->requests.push_back(std::move(request));
    }
  });
#else
  static_cast<void>(paths);
#endif
  return true;
}

godot::Array WindowsSingleInstanceBridge::poll_requests() {
  godot::Array result{};
#ifdef _WIN32
  std::deque<std::vector<std::string>> requests{};
  {
    const std::lock_guard<std::mutex> lock(impl_->requests_mutex);
    requests.swap(impl_->requests);
  }
  for (const auto &request : requests) {
    godot::PackedStringArray paths{};
    for (const auto &path : request)
      paths.push_back(godot::String::utf8(path.data(), path.size()));
    result.push_back(paths);
  }
#endif
  return result;
}

godot::String WindowsSingleInstanceBridge::get_error() const {
  return impl_->error;
}
} // namespace nd::go::gdext
