#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <exception>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

#include "game/board.h"
#include "game/boardhistory.h"
#include "neuralnet/nneval.h"
#include "external/nlohmann_json/json.hpp"

namespace GotepadKataGo {

inline nlohmann::json get_embedded_nn_stats(NNEvaluator* nn_eval) {
  nlohmann::json stats;
  const uint64_t rows = nn_eval->numRowsProcessed();
  const uint64_t batches = nn_eval->numBatchesProcessed();
  stats["nnXLen"] = nn_eval->getNNXLen();
  stats["nnYLen"] = nn_eval->getNNYLen();
  stats["maxBatchSize"] = nn_eval->getMaxBatchSize();
  stats["currentBatchSize"] = nn_eval->getCurrentBatchSize();
  stats["modelName"] = nn_eval->getModelName();
  stats["modelInternalName"] = nn_eval->getInternalModelName();
  stats["modelVersion"] = nn_eval->getModelVersion();
  stats["numGpus"] = nn_eval->getNumGpus();
  stats["numServerThreads"] = nn_eval->getNumServerThreads();
  stats["rows"] = rows;
  stats["batches"] = batches;
  stats["averageBatchSize"] =
      batches > 0 ? static_cast<double>(rows) / static_cast<double>(batches)
                  : 0.0;
  stats["cacheHits"] = nn_eval->numCacheHits();
  stats["requestedFP16Mode"] = nn_eval->getUsingFP16Mode().toString();
  stats["usingFP16"] = nn_eval->isAnyThreadUsingFP16();
  return stats;
}

inline nlohmann::json run_embedded_nn_benchmark(
    NNEvaluator* nn_eval, int batch_size, int duration_millis) {
  if (nn_eval->requiresSGFMetadata()) {
    throw StringError(
        "The embedded NN benchmark does not support Human SL models");
  }

  const int previous_batch_size = nn_eval->getCurrentBatchSize();
  const bool previous_randomize = nn_eval->getDoRandomize();
  const int previous_symmetry = nn_eval->getDefaultSymmetry();
  nn_eval->setCurrentBatchSize(batch_size);
  nn_eval->setDoRandomize(false);
  nn_eval->setDefaultSymmetry(0);
  nn_eval->clearCache();

  auto run_workers = [nn_eval, batch_size](int run_millis) {
    std::atomic<int> ready_count(0);
    std::atomic<bool> start(false);
    std::atomic<bool> stop(false);
    std::atomic<uint64_t> completed(0);
    std::mutex error_mutex;
    std::exception_ptr worker_error = nullptr;
    std::chrono::steady_clock::time_point deadline;
    std::vector<std::thread> workers;
    workers.reserve(batch_size);

    for (int i = 0; i < batch_size; i++) {
      workers.emplace_back([&]() {
        bool reported_ready = false;
        try {
          Board board(nn_eval->getNNXLen(), nn_eval->getNNYLen());
          BoardHistory history(
              board, P_BLACK, Rules::getTrompTaylorish(), 0,
              nn_eval->modelPreferPassAliveUnderSuicideRules());
          MiscNNInputParams nn_input_params;
          NNResultBuf result_buf;
          ready_count.fetch_add(1, std::memory_order_release);
          reported_ready = true;
          while (!start.load(std::memory_order_acquire) &&
                 !stop.load(std::memory_order_acquire)) {
            std::this_thread::yield();
          }
          do {
            nn_eval->evaluate(board, history, P_BLACK, nn_input_params,
                              result_buf, true, false);
            completed.fetch_add(1, std::memory_order_relaxed);
          } while (run_millis > 0 &&
                   !stop.load(std::memory_order_acquire) &&
                   std::chrono::steady_clock::now() < deadline);
        } catch (...) {
          if (!reported_ready) {
            ready_count.fetch_add(1, std::memory_order_release);
          }
          {
            std::lock_guard<std::mutex> lock(error_mutex);
            if (worker_error == nullptr) {
              worker_error = std::current_exception();
            }
          }
          stop.store(true, std::memory_order_release);
        }
      });
    }

    while (ready_count.load(std::memory_order_acquire) < batch_size) {
      std::this_thread::yield();
    }
    const auto started = std::chrono::steady_clock::now();
    deadline = started + std::chrono::milliseconds(run_millis);
    start.store(true, std::memory_order_release);
    for (std::thread& worker : workers) {
      worker.join();
    }
    const double elapsed_seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - started).count();
    if (worker_error != nullptr) {
      std::rethrow_exception(worker_error);
    }
    return std::make_pair(completed.load(std::memory_order_relaxed),
                          elapsed_seconds);
  };

  try {
    run_workers(0);
    nn_eval->clearStats();
    const std::pair<uint64_t, double> measured =
        run_workers(duration_millis);
    nlohmann::json result = get_embedded_nn_stats(nn_eval);
    result["requestedBatchSize"] = batch_size;
    result["completedRows"] = measured.first;
    result["elapsedSeconds"] = measured.second;
    result["positionsPerSecond"] =
        measured.second > 0.0
            ? static_cast<double>(measured.first) / measured.second
            : 0.0;
    nn_eval->setCurrentBatchSize(previous_batch_size);
    nn_eval->setDoRandomize(previous_randomize);
    nn_eval->setDefaultSymmetry(previous_symmetry);
    return result;
  } catch (...) {
    nn_eval->setCurrentBatchSize(previous_batch_size);
    nn_eval->setDoRandomize(previous_randomize);
    nn_eval->setDefaultSymmetry(previous_symmetry);
    throw;
  }
}

}  // namespace GotepadKataGo
