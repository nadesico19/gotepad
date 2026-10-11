// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#include "macos_single_instance_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <mutex>
#include <poll.h>
#include <string>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace nd::go::gdext {
namespace {
using Clock = std::chrono::steady_clock;
inline constexpr uint32_t kPacketMagic = 0x47534731U;
inline constexpr uint32_t kMaximumPathCount = 256U;
inline constexpr uint32_t kMaximumPathBytes = 128U * 1024U;
inline constexpr size_t kMaximumPacketBytes = 1024U * 1024U;

struct PacketHeader {
  uint32_t magic{};
  uint32_t path_count{};
};

void configure_socket_(int socket) {
  const int enabled = 1;
  setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
  fcntl(socket, F_SETFD, FD_CLOEXEC);
  fcntl(socket, F_SETFL, O_NONBLOCK);
}

bool transfer_all_(int socket, void *data, size_t size, bool writing,
                   Clock::time_point deadline) {
  auto *cursor = static_cast<uint8_t *>(data);
  while (size > 0 && Clock::now() < deadline) {
    pollfd descriptor{socket, static_cast<short>(writing ? POLLOUT : POLLIN), 0};
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
        deadline - Clock::now()).count();
    const int ready = poll(&descriptor, 1, static_cast<int>(remaining));
    if (ready < 0 && errno == EINTR)
      continue;
    if (ready <= 0)
      return false;
    const ssize_t count = writing ? send(socket, cursor, size, 0)
                                  : recv(socket, cursor, size, 0);
    if (count < 0 && (errno == EINTR || errno == EAGAIN))
      continue;
    if (count <= 0)
      return false;
    cursor += count;
    size -= static_cast<size_t>(count);
  }
  return size == 0;
}

bool read_packet_(int socket, std::vector<std::string> &paths) {
  const auto deadline = Clock::now() + std::chrono::seconds(2);
  PacketHeader header{};
  if (!transfer_all_(socket, &header, sizeof(header), false, deadline) ||
      header.magic != kPacketMagic || header.path_count == 0 ||
      header.path_count > kMaximumPathCount)
    return false;
  size_t total{};
  for (uint32_t index = 0; index < header.path_count; ++index) {
    uint32_t length{};
    if (!transfer_all_(socket, &length, sizeof(length), false, deadline) ||
        length == 0 || length > kMaximumPathBytes)
      return false;
    total += length;
    if (total > kMaximumPacketBytes)
      return false;
    std::string path(length, '\0');
    if (!transfer_all_(socket, path.data(), length, false, deadline) ||
        path.find('\0') != std::string::npos)
      return false;
    paths.push_back(std::move(path));
  }
  return true;
}

bool forward_paths_(const sockaddr_un &address,
                    const godot::PackedStringArray &paths) {
  if (paths.size() > kMaximumPathCount)
    return false;
  std::vector<uint8_t> packet(sizeof(PacketHeader));
  const PacketHeader header{kPacketMagic, static_cast<uint32_t>(paths.size())};
  std::memcpy(packet.data(), &header, sizeof(header));
  for (const auto &path : paths) {
    const godot::CharString utf8 = path.utf8();
    const uint32_t length = static_cast<uint32_t>(utf8.length());
    if (length == 0 || length > kMaximumPathBytes ||
        packet.size() + sizeof(length) + length > kMaximumPacketBytes)
      return false;
    const size_t offset = packet.size();
    packet.resize(offset + sizeof(length) + length);
    std::memcpy(packet.data() + offset, &length, sizeof(length));
    std::memcpy(packet.data() + offset + sizeof(length), utf8.get_data(), length);
  }
  const auto deadline = Clock::now() + std::chrono::seconds(5);
  while (Clock::now() < deadline) {
    const int socket = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (socket < 0)
      return false;
    configure_socket_(socket);
    int connected = connect(socket, reinterpret_cast<const sockaddr *>(&address),
                            sizeof(address));
    if (connected < 0 && errno == EINPROGRESS) {
      pollfd descriptor{socket, POLLOUT, 0};
      if (poll(&descriptor, 1, 100) > 0) {
        int error{};
        socklen_t length = sizeof(error);
        if (getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0)
          connected = 0;
      }
    }
    if (connected == 0) {
      uint32_t acknowledgement{};
      const bool sent = transfer_all_(socket, packet.data(), packet.size(), true, deadline);
      const bool accepted = sent && transfer_all_(socket, &acknowledgement,
          sizeof(acknowledgement), false, deadline) && acknowledgement == kPacketMagic;
      close(socket);
      // Do not resend after delivery: the primary may have queued the request
      // even if the acknowledgement was lost.
      return accepted;
    }
    close(socket);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  return false;
}
} // namespace

struct MacOSSingleInstanceBridge::Impl {
  godot::String error{};
  int lock{-1};
  int listener{-1};
  std::string socket_path{};
  std::atomic_bool stopping{false};
  std::thread worker{};
  std::mutex requests_mutex{};
  std::deque<std::vector<std::string>> requests{};
};

MacOSSingleInstanceBridge::MacOSSingleInstanceBridge()
    : impl_(std::make_unique<Impl>()) {}

MacOSSingleInstanceBridge::~MacOSSingleInstanceBridge() {
  impl_->stopping.store(true);
  if (impl_->worker.joinable())
    impl_->worker.join();
  if (impl_->listener >= 0) {
    close(impl_->listener);
    unlink(impl_->socket_path.c_str());
  }
  // Keep the lock file: unlinking it would allow two different lock inodes.
  if (impl_->lock >= 0)
    close(impl_->lock);
}

void MacOSSingleInstanceBridge::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("start_or_forward", "paths"),
                            &MacOSSingleInstanceBridge::start_or_forward);
  godot::ClassDB::bind_method(godot::D_METHOD("poll_requests"),
                            &MacOSSingleInstanceBridge::poll_requests);
  godot::ClassDB::bind_method(godot::D_METHOD("get_error"),
                            &MacOSSingleInstanceBridge::get_error);
}

bool MacOSSingleInstanceBridge::start_or_forward(const godot::PackedStringArray &paths) {
  if (impl_->lock >= 0)
    return true;
  const std::string directory = "/tmp/gotepad-sgf-" + std::to_string(getuid());
  struct stat info{};
  if ((mkdir(directory.c_str(), 0700) != 0 && errno != EEXIST) ||
      lstat(directory.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != getuid() || (info.st_mode & 077) != 0) {
    impl_->error = "Unable to create the private Gotepad file request directory";
    return true;
  }
  const int lock = open((directory + "/primary.lock").c_str(),
                        O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (lock < 0) {
    impl_->error = "Unable to open the Gotepad single-instance lock";
    return true;
  }
  sockaddr_un address{};
  address.sun_family = AF_UNIX;
  address.sun_len = sizeof(address);
  impl_->socket_path = directory + "/open.sock";
  std::memcpy(address.sun_path, impl_->socket_path.c_str(), impl_->socket_path.size() + 1);
  if (flock(lock, LOCK_EX | LOCK_NB) != 0) {
    const int lock_error = errno;
    close(lock);
    if (lock_error != EWOULDBLOCK) {
      impl_->error = "Unable to acquire the Gotepad single-instance lock";
      return true;
    }
    if (paths.is_empty())
      return true;
    if (forward_paths_(address, paths))
      return false;
    impl_->error = "Unable to contact the existing Gotepad process";
    return true;
  }
  const int listener = socket(AF_UNIX, SOCK_STREAM, 0);
  if (listener >= 0)
    configure_socket_(listener);
  // The lock owner alone may replace a socket left behind after a crash.
  unlink(impl_->socket_path.c_str());
  if (listener < 0 || bind(listener, reinterpret_cast<const sockaddr *>(&address),
                            sizeof(address)) != 0 || listen(listener, 16) != 0) {
    if (listener >= 0)
      close(listener);
    close(lock);
    impl_->error = "Unable to listen for Gotepad file requests";
    return true;
  }
  impl_->lock = lock;
  impl_->listener = listener;
  impl_->worker = std::thread([this]() {
    while (!impl_->stopping.load()) {
      pollfd descriptor{impl_->listener, POLLIN, 0};
      if (poll(&descriptor, 1, 100) <= 0)
        continue;
      const int client = accept(impl_->listener, nullptr, nullptr);
      if (client < 0)
        continue;
      configure_socket_(client);
      uid_t user{};
      gid_t group{};
      std::vector<std::string> paths{};
      if (getpeereid(client, &user, &group) == 0 && user == getuid() &&
          read_packet_(client, paths)) {
        {
          const std::lock_guard<std::mutex> guard(impl_->requests_mutex);
          impl_->requests.push_back(std::move(paths));
        }
        uint32_t acknowledgement = kPacketMagic;
        transfer_all_(client, &acknowledgement, sizeof(acknowledgement), true,
                      Clock::now() + std::chrono::seconds(1));
      }
      close(client);
    }
  });
  return true;
}

godot::Array MacOSSingleInstanceBridge::poll_requests() {
  std::deque<std::vector<std::string>> requests{};
  {
    const std::lock_guard<std::mutex> guard(impl_->requests_mutex);
    requests.swap(impl_->requests);
  }
  godot::Array result{};
  for (const auto &request : requests) {
    godot::PackedStringArray paths{};
    for (const auto &path : request)
      paths.push_back(godot::String::utf8(path.data(), path.size()));
    result.push_back(paths);
  }
  return result;
}

godot::String MacOSSingleInstanceBridge::get_error() const {
  return impl_->error;
}
} // namespace nd::go::gdext
