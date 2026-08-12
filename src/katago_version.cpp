// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

#include "main.h"

#include <sstream>

std::string Version::getKataGoVersion() { return "1.17.1"; }

std::string Version::getKataGoVersionForHelp() { return "KataGo v1.17.1"; }

std::string Version::getKataGoVersionFullInfo() {
  std::ostringstream output{};
  output << getKataGoVersionForHelp() << '\n';
  output << "Git revision: embedded-v1.17.1\n";
  output << "Using Eigen(CPU) backend\n";
  return output.str();
}

std::string Version::getGitRevision() { return "embedded-v1.17.1"; }

std::string Version::getGitRevisionWithBackend() {
  return "embedded-v1.17.1-eigen";
}
