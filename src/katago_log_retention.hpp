#pragma once

// Android OpenCL writers share a POSIX lock with the Java history cleaner.
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <mutex>
#include <string>

namespace GotepadKataGo {

inline bool protect_log_directory(const std::string& directory) {
  static std::mutex mutex;
  static int descriptor = -1;
  static std::string protected_directory;
  std::lock_guard<std::mutex> guard(mutex);
  if (descriptor >= 0) return protected_directory == directory;
  if (directory.empty()) return false;
  const int candidate = open((directory + "/.retention.lock").c_str(),
                             O_CREAT | O_RDWR | O_CLOEXEC, 0600);
  if (candidate < 0) return false;
  struct flock lock {};
  lock.l_type = F_RDLCK;
  lock.l_whence = SEEK_SET;
  int result;
  do { result = fcntl(candidate, F_SETLKW, &lock); } while (result < 0 && errno == EINTR);
  if (result < 0) { close(candidate); return false; }
  // Deliberately retain this sole descriptor until the isolated backend exits.
  // Closing any descriptor for this inode would release this process's locks.
  descriptor = candidate;
  protected_directory = directory;
  return true;
}

} // namespace GotepadKataGo
