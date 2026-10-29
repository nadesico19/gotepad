#pragma once

#include <chrono>
#include <memory>
#include <vector>

#include "neuralnet/nninterface.h"
#include "neuralnet/modelversion.h"

namespace GotepadKataGo {

inline double warm_up_metal_search(NNEvaluator* nn_eval) {
  if (nn_eval->requiresSGFMetadata()) {
    return 0.0;
  }
  const auto started = std::chrono::steady_clock::now();
  Board board(nn_eval->getNNXLen(), nn_eval->getNNYLen());
  BoardHistory history(board, P_BLACK, Rules::getTrompTaylorish(), 0,
                       nn_eval->modelPreferPassAliveUnderSuicideRules());
  MiscNNInputParams params;
  NNResultBuf result;
  // Go through the real server handle. Its fixed physical batch is compiled
  // before the caller starts timing search; only real rows count as throughput.
  nn_eval->evaluate(board, history, P_BLACK, params, result, true, false);
  return std::chrono::duration<double>(
      std::chrono::steady_clock::now() - started).count();
}

inline nlohmann::json run_metal_nn_benchmark(
    NNEvaluator* nn_eval, int batch_size, int duration_millis,
    ConfigParser& cfg, Logger* logger) {
  if (nn_eval->requiresSGFMetadata()) {
    throw StringError("The embedded NN benchmark does not support Human SL models");
  }
  if (batch_size < 1 || batch_size > nn_eval->getMaxBatchSize()) {
    throw StringError("Metal benchmark batch is outside the configured range");
  }

  const auto loading_started = std::chrono::steady_clock::now();
  std::unique_ptr<LoadedModel, decltype(&NeuralNet::freeLoadedModel)> model(
      NeuralNet::loadModelFile(nn_eval->getModelFileName(), ""),
      NeuralNet::freeLoadedModel);
  const ModelDesc& desc = NeuralNet::getModelDesc(model.get());
  const int width = nn_eval->getNNXLen();
  const int height = nn_eval->getNNYLen();
  std::unique_ptr<ComputeContext, decltype(&NeuralNet::freeComputeContext)> context(
      NeuralNet::createComputeContext({0}, logger, width, height,
          cfg.contains("homeDataDir") ? cfg.getString("homeDataDir") : "",
          nn_eval->getUsingFP16Mode(), model.get(), cfg),
      NeuralNet::freeComputeContext);
  std::unique_ptr<ComputeHandle, decltype(&NeuralNet::freeComputeHandle)> handle(
      NeuralNet::createComputeHandle(context.get(), model.get(), logger,
          batch_size, false, false, 0, 0), NeuralNet::freeComputeHandle);
  std::unique_ptr<InputBuffers, decltype(&NeuralNet::freeInputBuffers)> buffers(
      NeuralNet::createInputBuffers(model.get(), batch_size, width, height),
      NeuralNet::freeInputBuffers);

  Board board(width, height);
  BoardHistory history(board, P_BLACK, Rules::getTrompTaylorish(), 0,
                       nn_eval->modelPreferPassAliveUnderSuicideRules());
  MiscNNInputParams params;
  std::vector<std::unique_ptr<NNResultBuf>> inputs;
  std::vector<std::unique_ptr<NNOutput>> owned_outputs;
  std::vector<NNResultBuf*> rows;
  std::vector<NNOutput*> outputs;
  const int inputs_version = NNModelVersion::getInputsVersion(desc.modelVersion);
  for (int row = 0; row < batch_size; ++row) {
    inputs.emplace_back(new NNResultBuf());
    auto& input = *inputs.back();
    input.rowSpatialBuf.resize(desc.numInputChannels * width * height);
    input.rowGlobalBuf.resize(desc.numInputGlobalChannels);
    input.hasRowMeta = false;
    input.symmetry = 0;
    input.policyOptimism = 0;
    auto* spatial = input.rowSpatialBuf.data();
    auto* global = input.rowGlobalBuf.data();
    switch (inputs_version) {
      case 3: NNInputs::fillRowV3(board, history, P_BLACK, params, width, height, false, spatial, global); break;
      case 4: NNInputs::fillRowV4(board, history, P_BLACK, params, width, height, false, spatial, global); break;
      case 5: NNInputs::fillRowV5(board, history, P_BLACK, params, width, height, false, spatial, global); break;
      case 6: NNInputs::fillRowV6(board, history, P_BLACK, params, width, height, false, spatial, global); break;
      case 7: NNInputs::fillRowV7(board, history, P_BLACK, params, width, height, false, spatial, global); break;
      default: throw StringError("Unsupported Metal benchmark input version");
    }
    owned_outputs.emplace_back(new NNOutput());
    owned_outputs.back()->nnXLen = width;
    owned_outputs.back()->nnYLen = height;
    owned_outputs.back()->whiteOwnerMap = nullptr;
    rows.push_back(&input);
    outputs.push_back(owned_outputs.back().get());
  }

  const auto warmup_started = std::chrono::steady_clock::now();
  NeuralNet::getOutput(handle.get(), buffers.get(), batch_size, rows.data(), outputs);
  const auto started = std::chrono::steady_clock::now();
  const auto deadline = started + std::chrono::milliseconds(duration_millis);
  uint64_t batches = 0;
  do {
    NeuralNet::getOutput(handle.get(), buffers.get(), batch_size, rows.data(), outputs);
    ++batches;
  } while (std::chrono::steady_clock::now() < deadline);
  const double elapsed = std::chrono::duration<double>(
      std::chrono::steady_clock::now() - started).count();
  nlohmann::json result = get_embedded_nn_stats(nn_eval);
  result["measurementMode"] = "fixed-backend-batch";
  result["requestedBatchSize"] = batch_size;
  result["currentBatchSize"] = batch_size;
  result["averageBatchSize"] = batch_size;
  result["backendBatchSize"] = batch_size;
  result["batches"] = batches;
  result["rows"] = batches * batch_size;
  result["completedRows"] = batches * batch_size;
  result["cacheHits"] = 0;
  result["usingFP16"] = NeuralNet::isUsingFP16(handle.get());
  result["elapsedSeconds"] = elapsed;
  result["positionsPerSecond"] = batches * batch_size / elapsed;
  result["initializationSeconds"] = std::chrono::duration<double>(warmup_started - loading_started).count();
  result["warmupSeconds"] = std::chrono::duration<double>(started - warmup_started).count();
  // Handles, graph specializations and buffers are released at the end of
  // every candidate, including exceptions; larger candidates start cleanly.
  return result;
}

}  // namespace GotepadKataGo
