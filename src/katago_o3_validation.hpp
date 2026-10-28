#pragma once

// Included by the OpenCL backend after its private handle types are complete.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <memory>
#include <limits>
#include <map>
#include <array>
#include "katago_log_retention.hpp"

namespace GotepadKataGo {
namespace O3Validation {
using Json = nlohmann::json;
using Values = std::map<std::string, std::vector<double>>;

inline Json difference(const std::vector<double>& reference, const std::vector<double>& candidate) {
  double maximum = 0, sum = 0, squares = 0;
  size_t nonfinite = 0, count = 0, worst = 0;
  if(reference.size() != candidate.size()) throw StringError("Validation output shape mismatch");
  for(size_t i = 0; i < reference.size(); ++i) {
    if(!std::isfinite(reference[i]) || !std::isfinite(candidate[i])) { ++nonfinite; continue; }
    double error = std::abs(reference[i] - candidate[i]);
    if(error > maximum) { maximum = error; worst = i; }
    sum += error; squares += error * error; ++count;
  }
  return {{"maxAbs", maximum}, {"meanAbs", count ? sum / count : 0},
          {"rms", count ? std::sqrt(squares / count) : 0}, {"worstIndex", worst},
          {"nonfinite", nonfinite}, {"count", count}};
}

inline Json compare(const Values& reference, const Values& candidate) {
  Json result = Json::object();
  for(const auto& item : reference) result[item.first] = difference(item.second, candidate.at(item.first));
  return result;
}

inline Values capture(const NNOutput& output, const ModelDesc& model,
                      const std::vector<bool>& legal, Player next_player) {
  Values result;
  auto& policy = result["policyLogits"];
  policy.assign(output.policyProbs, output.policyProbs + 362);
  result["valueLogits"] = {output.whiteWinProb, output.whiteLossProb, output.whiteNoResultProb};
  result["scoreRaw"] = {output.whiteScoreMean, output.whiteScoreMeanSq, output.whiteLead,
                       output.varTimeLeft, output.shorttermWinlossError, output.shorttermScoreError};
  result["ownershipLogits"].assign(output.whiteOwnerMap, output.whiteOwnerMap + 361);
  const auto& params = model.postProcessParams;
  const double scale = params.outputScaleMultiplier;
  // Fixed TT rules: no-result is impossible. These derived fields use white's perspective.
  const double sign = next_player == P_WHITE ? 1.0 : -1.0;
  double w = output.whiteWinProb * scale, l = output.whiteLossProb * scale;
  double maximum = std::max(w, l);
  double win = std::exp(w - maximum) / (std::exp(w - maximum) + std::exp(l - maximum));
  result["whiteWinProbability"] = {next_player == P_WHITE ? win : 1.0 - win};
  result["whiteScoreMeanPoints"] = {sign * output.whiteScoreMean * scale * params.scoreMeanMultiplier};
  auto& owners = result["whiteOwnership"];
  for(int i = 0; i < 361; ++i) owners.push_back(sign * std::tanh(output.whiteOwnerMap[i] * scale));
  auto& probabilities = result["legalPolicyProbability"];
  probabilities.resize(362, 0.0);
  maximum = -std::numeric_limits<double>::infinity();
  for(int i = 0; i < 362; ++i) if(legal[i]) maximum = std::max(maximum, policy[i] * scale);
  double sum = 0;
  for(int i = 0; i < 362; ++i) if(legal[i]) { probabilities[i] = std::exp(policy[i] * scale - maximum); sum += probabilities[i]; }
  for(double& value : probabilities) value /= sum;
  return result;
}
} // namespace O3Validation

// This creates an isolated handle and never changes the live evaluator or saved settings.
nlohmann::json run_o3_validation(const std::string& model_file, ConfigParser& original_cfg,
                                        Logger* logger, int batch_size) {
  using namespace O3Validation;
  if(batch_size != 1 && batch_size != 2 && batch_size != 4 && batch_size != 8 && batch_size != 16 && batch_size != 32)
    throw StringError("O3 validation requires batch 1,2,4,8,16,32");
  if(!original_cfg.contains("gotepadO3Validation") || !original_cfg.getBool("gotepadO3Validation"))
    throw StringError("O3 validation requires its dedicated session");
  ConfigParser cfg(original_cfg);
  cfg.overrideKey("gotepadO3Profile", "false");
  cfg.overrideKey("gotepadO3Optimize", "true");
  const std::string directory = cfg.getString("gotepadO3ProfileLogDir");
  if(directory.empty()) throw StringError("O3 validation report directory unavailable");
  const auto stamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  if (!protect_log_directory(directory)) throw StringError("Cannot protect validation reports from cleanup");
  const std::string run_id = cfg.contains("gotepadO3ValidationRunId") ?
      cfg.getString("gotepadO3ValidationRunId") : "";
  if (!run_id.empty() && run_id.find_first_not_of("0123456789-") != std::string::npos)
    throw StringError("Invalid validation run ID");
  const std::string report_id = run_id.empty() ? std::to_string(stamp) : "run" + run_id;
  const std::string path = directory + "/validation-" + report_id + "-b" + std::to_string(batch_size) + ".jsonl";
  std::ofstream report(path);
  if(!report) throw StringError("Cannot create O3 validation report");
  auto write = [&](const Json& record) {
    report << record.dump() << '\n'; report.flush();
    if(!report) throw StringError("Cannot write O3 validation report");
  };
  write({{"type", "start"}, {"schema", 1}, {"suite", "o3-generated-v1"}, {"batchSize", batch_size},
         {"caseCount", 32}, {"modelFile", model_file}, {"search", false}, {"cache", false},
         {"profiling", false}, {"policyTemperature", 1.0}, {"policyOptimism", 0.0},
         {"note", "Generated legal positions, not a curated tactical suite. Completion is not numerical acceptance."}});
  try {
    std::unique_ptr<LoadedModel, decltype(&NeuralNet::freeLoadedModel)> loaded(
        NeuralNet::loadModelFile(model_file, ""), NeuralNet::freeLoadedModel);
    const auto& model = NeuralNet::getModelDesc(loaded.get());
    const auto structure = inspect_acceleration_structure(model);
    write({{"type", "structure"}, {"structure", structure.summary(true)}});
    if(!structure.supported())
      throw StringError("Model structure is not supported for acceleration: " + structure.reason);
    std::unique_ptr<ComputeContext, decltype(&NeuralNet::freeComputeContext)> context(
        NeuralNet::createComputeContext({-1}, logger, 19, 19,
            cfg.contains("homeDataDir") ? cfg.getString("homeDataDir") : "", enabled_t::Auto, loaded.get(), cfg),
        NeuralNet::freeComputeContext);
    std::unique_ptr<ComputeHandle, decltype(&NeuralNet::freeComputeHandle)> handle(
        NeuralNet::createComputeHandle(context.get(), loaded.get(), logger, batch_size, false, false, -1, 0),
        NeuralNet::freeComputeHandle);
    auto& gemm = handle->handle->o3Gemm;
    const auto acceleration_status = get_acceleration_status(model.name, model.modelVersion);
    if(!gemm.enabled()) {
      write({{"type", "accelerationUnavailable"}, {"status", acceleration_status}});
      throw StringError("Experimental kernels unavailable; validation aborted, not passed: " +
                        acceleration_status.value("reason", std::string("unknown")));
    }
    write({{"type", "model"}, {"name", model.name}, {"sha256", model.sha256}, {"version", model.modelVersion},
           {"kernelPath", gemm.kernel_path()}, {"fp16Storage", handle->handle->usingFP16Storage},
           {"fp16Compute", handle->handle->usingFP16Compute},
           {"modelAcceleration", acceleration_status},
           {"gemmTune", handle->handle->tuneParams.xGemmDirect.desc()},
           {"attentionTune", handle->handle->tuneParams.transformer.desc()}});
    std::unique_ptr<InputBuffers, decltype(&NeuralNet::freeInputBuffers)> buffers(
        NeuralNet::createInputBuffers(loaded.get(), batch_size, 19, 19), NeuralNet::freeInputBuffers);
    std::array<NNResultBuf, 32> inputs;
    std::array<std::vector<bool>, 32> legal;
    std::array<Player, 32> players;
    const int lengths[] = {0, 8, 24, 60, 100, 160, 220, 280};
    for(int index = 0; index < 32; ++index) {
      Board board(19, 19);
      Rules rules = Rules::getTrompTaylorish();
      rules.komi = index % 3 == 0 ? 7.5f : (index % 3 == 1 ? 0.5f : -7.5f);
      BoardHistory history(board, P_BLACK, rules, 0, model.preferPassAliveUnderSuicideRules);
      Player player = P_BLACK;
      uint32_t state = 0x03c384u + static_cast<uint32_t>(index) * 7919u;
      Json moves = Json::array();
      for(int turn = 0; turn < lengths[index % 8] + (index / 8) % 2; ++turn) {
        Loc move = Board::PASS_LOC;
        state = state * 1664525u + 1013904223u;
        for(int attempt = 0; attempt < 361; ++attempt) {
          int pos = static_cast<int>((state % 361u + attempt) % 361u);
          Loc candidate = Location::getLoc(pos % 19, pos / 19, 19);
          if(history.isLegal(board, candidate, player)) { move = candidate; break; }
        }
        if(move == Board::PASS_LOC) break;
        moves.push_back({player == P_BLACK ? "B" : "W", Location::toString(move, board)});
        history.makeBoardMoveAssumeLegal(board, move, player, nullptr);
        player = getOpp(player);
        if(history.isGameFinished) break;
      }
      players[index] = player;
      auto& input = inputs[index];
      input.rowSpatialBuf.resize(model.numInputChannels * 361);
      input.rowGlobalBuf.resize(model.numInputGlobalChannels);
      input.hasRowMeta = false;
      input.symmetry = index % 8;
      input.policyOptimism = 0;
      MiscNNInputParams params;
      NNInputs::fillRowV7(board, history, player, params, 19, 19, false,
                         input.rowSpatialBuf.data(), input.rowGlobalBuf.data());
      for(int pos = 0; pos < 362; ++pos)
        legal[index].push_back(history.isLegal(board, pos == 361 ? Board::PASS_LOC : Location::getLoc(pos % 19, pos / 19, 19), player));
      write({{"type", "case"}, {"caseId", index}, {"symmetry", input.symmetry}, {"komi", rules.komi},
             {"rules", "tromp-taylor"}, {"nextPlayer", player == P_BLACK ? "B" : "W"}, {"moves", moves},
             {"legalMask", legal[index]}, {"spatialInput", input.rowSpatialBuf}, {"globalInput", input.rowGlobalBuf}});
    }
    auto evaluate = [&](const std::vector<int>& ids, bool optimized, const std::string& phase) {
      gemm.set_validation_bypass(!optimized);
      if(optimized && !gemm.enabled()) throw StringError("O3 kernels fell back during validation");
      std::vector<std::unique_ptr<NNOutput>> owned;
      std::vector<NNOutput*> outputs;
      std::vector<NNResultBuf*> rows;
      for(int id : ids) {
        owned.emplace_back(new NNOutput());
        auto* out = owned.back().get();
        out->nnXLen = 19; out->nnYLen = 19;
        out->whiteOwnerMap = new float[361];
        outputs.push_back(out); rows.push_back(&inputs[id]);
      }
      NeuralNet::getOutput(handle.get(), buffers.get(), static_cast<int>(ids.size()), rows.data(), outputs);
      if(optimized && !gemm.enabled()) throw StringError("O3 kernels fell back during validation");
      std::vector<Values> captured;
      for(size_t i = 0; i < ids.size(); ++i) {
        captured.push_back(capture(*outputs[i], model, legal[ids[i]], players[ids[i]]));
        write({{"type", "output"}, {"phase", phase}, {"caseId", ids[i]}, {"slot", i},
               {"actualBatchSize", ids.size()}, {"optimized", optimized}, {"values", captured.back()}});
      }
      return captured;
    };
    std::array<Values, 32> single_original, single_candidate;
    for(int i = 0; i < 32; ++i) {
      single_original[i] = evaluate({i}, false, "singleOriginal")[0];
      single_candidate[i] = evaluate({i}, true, "singleCandidate")[0];
    }
    Json aggregate = Json::object();
    size_t nonfinite = 0;
    auto record_comparison = [&](const std::string& kind, int id, const Values& a, const Values& b) {
      Json metrics = compare(a, b);
      for(auto it = metrics.begin(); it != metrics.end(); ++it) {
        nonfinite += it.value()["nonfinite"].get<size_t>();
        double maximum = it.value()["maxAbs"].get<double>();
        double previous = aggregate.contains(kind) && aggregate[kind].contains(it.key())
            ? aggregate[kind][it.key()].get<double>() : 0.0;
        aggregate[kind][it.key()] = std::max(previous, maximum);
      }
      write({{"type", "comparison"}, {"kind", kind}, {"caseId", id}, {"metrics", metrics}});
    };
    for(int layout = 0; layout < 2; ++layout) {
      for(int start = 0; start < 32; start += batch_size) {
        std::vector<int> ids;
        for(int slot = 0; slot < batch_size; ++slot)
          ids.push_back(layout == 0 ? start + slot : (39 - start - slot) % 32);
        auto original = evaluate(ids, false, "batchOriginal");
        auto repeated = evaluate(ids, false, "batchOriginalRepeat");
        auto candidate = evaluate(ids, true, "batchCandidate");
        auto candidate_repeat = evaluate(ids, true, "batchCandidateRepeat");
        for(size_t i = 0; i < ids.size(); ++i) {
          int id = ids[i];
          record_comparison("originalRepeat", id, original[i], repeated[i]);
          record_comparison("candidateRepeat", id, candidate[i], candidate_repeat[i]);
          record_comparison("originalVsCandidate", id, original[i], candidate[i]);
          record_comparison("originalSingleVsBatch", id, single_original[id], original[i]);
          record_comparison("candidateSingleVsBatch", id, single_candidate[id], candidate[i]);
        }
      }
    }
    gemm.set_validation_bypass(false);
    for(int group = 0; group < 3; ++group)
      if(structure.candidates[group] > 0 && gemm.validation_calls()[group] == 0)
        throw StringError("An expected experimental kernel variant was not exercised");
    Json result = {{"type", "complete"}, {"kernelPath", gemm.kernel_path()}, {"model", model.name}, {"batchSize", batch_size}, {"caseCount", 32},
                   {"nonfiniteComparisons", nonfinite}, {"maxAbsByComparison", aggregate},
                   {"experimentalKernelCalls", gemm.validation_calls()},
                   {"experimentalKernelCallNames", {"singleProjectionIncludingResidual", "SwiGLU", "QKV", "projectionResidualV4"}}, {"structure", structure.summary()}, {"reportPath", path},
                   {"status", nonfinite ? "nonfinite_detected" : "completed_needs_review"},
                   {"numericalAcceptance", "not_evaluated"}};
    write(result);
    return result;
  } catch(const std::exception& error) {
    write({{"type", "error"}, {"message", error.what()}, {"reportPath", path}});
    throw;
  }
}
} // namespace GotepadKataGo
