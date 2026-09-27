#pragma once

#include <array>
#include <functional>
#include <limits>
#include "core/global.h"
#include "neuralnet/desc.h"
#include "neuralnet/nninputs.h"
#include "external/nlohmann_json/json.hpp"

namespace GotepadKataGo {

// Shared by structural discovery and the actual dispatch. No model names or weights.
inline bool accelerated_matrix_shape(int input, int output) {
  constexpr int kMaxChannels = std::numeric_limits<int>::max() / (361 * 32);
  return input > 0 && output > 0 && input % 16 == 0 && output % 32 == 0 &&
         input <= kMaxChannels && output <= kMaxChannels &&
         static_cast<int64_t>(input) * output <= std::numeric_limits<int>::max();
}

struct ModelAccelerationStructure {
  bool valid = true;
  int nested_blocks = 0;
  int attention_blocks = 0;
  int ffn_blocks = 0;
  int convolution_candidates = 0;
  std::array<int, 3> candidates{};
  std::string reason = "no_compatible_operators";
  nlohmann::json graph = nlohmann::json::array();
  bool supported() const { return valid && (candidates[0] + candidates[1] + candidates[2] > 0); }
  bool transformer() const { return attention_blocks + ffn_blocks > 0; }
  std::string family() const {
    return transformer() ? (nested_blocks ? "nbt_transformer" : "transformer") :
           (nested_blocks ? "nbt" : "conv");
  }
  nlohmann::json summary(bool include_graph = false) const;
};

inline nlohmann::json ModelAccelerationStructure::summary(bool include_graph) const {
  nlohmann::json value = {{"matcher", "structure-v1"}, {"supported", supported()}, {"family", family()},
    {"reason", reason}, {"nestedBlocks", nested_blocks}, {"attentionBlocks", attention_blocks},
    {"ffnBlocks", ffn_blocks}, {"conv1x1Candidates", convolution_candidates}, {"kernelCandidates", candidates}};
  if (include_graph) value["graph"] = graph;
  return value;
}

// Walk all nested blocks and both heads. Untouched operators may have other
// dimensions: only the compatible operators are dispatched to experimental code.
inline ModelAccelerationStructure inspect_acceleration_structure(const ModelDesc& model) {
  ModelAccelerationStructure result;
  auto matrix = [&](const MatMulLayerDesc& layer, bool candidate) {
    if (layer.inChannels <= 0 || layer.outChannels <= 0) result.valid = false;
    result.graph.push_back({{"op", "matmul"}, {"in", layer.inChannels}, {"out", layer.outChannels},
                            {"accelerated", candidate}});
    if (candidate) ++result.candidates[0];
  };
  auto shape = [](const MatMulLayerDesc& layer) {
    return accelerated_matrix_shape(layer.inChannels, layer.outChannels);
  };
  std::function<void(const std::vector<std::pair<int, unique_ptr_void>>&, int, int)> blocks;
  blocks = [&](const auto& entries, int channels, int depth) {
    if (depth > 64 || channels <= 0) { result.valid = false; return; }
    for (const auto& entry : entries) {
      if (!entry.second) { result.valid = false; continue; }
      result.graph.push_back({{"block", entry.first}, {"channels", channels}, {"depth", depth}});
      switch (entry.first) {
      case ORDINARY_BLOCK_KIND: {
        const auto& b = *static_cast<const ResidualBlockDesc*>(entry.second.get());
        if (b.preBN.numChannels != channels || b.regularConv.inChannels != channels ||
            b.midBN.numChannels != b.regularConv.outChannels ||
            b.finalConv.inChannels != b.regularConv.outChannels || b.finalConv.outChannels != channels)
          result.valid = false;
        break;
      }
      case GLOBAL_POOLING_BLOCK_KIND: {
        const auto& b = *static_cast<const GlobalPoolingResidualBlockDesc*>(entry.second.get());
        if (b.preBN.numChannels != channels || b.regularConv.inChannels != channels ||
            b.gpoolConv.inChannels != channels || b.gpoolBN.numChannels != b.gpoolConv.outChannels ||
            b.gpoolToBiasMul.inChannels != static_cast<int64_t>(b.gpoolConv.outChannels) * 3 ||
            b.gpoolToBiasMul.outChannels != b.regularConv.outChannels ||
            b.midBN.numChannels != b.regularConv.outChannels ||
            b.finalConv.inChannels != b.regularConv.outChannels || b.finalConv.outChannels != channels)
          result.valid = false;
        matrix(b.gpoolToBiasMul, false);
        break;
      }
      case NESTED_BOTTLENECK_BLOCK_KIND: {
        const auto& b = *static_cast<const NestedBottleneckResidualBlockDesc*>(entry.second.get());
        ++result.nested_blocks;
        if (b.numBlocks != static_cast<int>(b.blocks.size()) || b.preBN.numChannels != channels ||
            b.preConv.inChannels != channels || b.postBN.numChannels != b.preConv.outChannels ||
            b.postConv.inChannels != b.preConv.outChannels || b.postConv.outChannels != channels)
          result.valid = false;
        blocks(b.blocks, b.preConv.outChannels, depth + 1);
        break;
      }
      case TRANSFORMER_ATTENTION_BLOCK_KIND: {
        const auto& b = *static_cast<const TransformerAttentionDesc*>(entry.second.get());
        ++result.attention_blocks;
        if (b.preLN.numChannels != channels || b.numHeads <= 0 || b.numKVHeads <= 0 ||
            b.qHeadDim <= 0 || b.vHeadDim <= 0 || b.numHeads % b.numKVHeads != 0 ||
            b.qProj.inChannels != channels || b.kProj.inChannels != channels || b.vProj.inChannels != channels ||
            b.qProj.outChannels != static_cast<int64_t>(b.numHeads) * b.qHeadDim ||
            b.kProj.outChannels != static_cast<int64_t>(b.numKVHeads) * b.qHeadDim ||
            b.vProj.outChannels != static_cast<int64_t>(b.numKVHeads) * b.vHeadDim ||
            b.outProj.inChannels != static_cast<int64_t>(b.numHeads) * b.vHeadDim || b.outProj.outChannels != channels)
          result.valid = false;
        const bool fused = shape(b.qProj) && b.qProj.outChannels == b.kProj.outChannels &&
                           b.qProj.outChannels == b.vProj.outChannels;
        if (fused) ++result.candidates[2];
        matrix(b.qProj, !fused && shape(b.qProj));
        matrix(b.kProj, !fused && shape(b.kProj));
        matrix(b.vProj, !fused && shape(b.vProj));
        matrix(b.outProj, shape(b.outProj));
        result.graph.push_back({{"heads", b.numHeads}, {"kvHeads", b.numKVHeads},
          {"qHeadDim", b.qHeadDim}, {"vHeadDim", b.vHeadDim}, {"rope", b.useRope},
          {"learnableRope", b.learnableRope}, {"fusedQKV", fused}});
        break;
      }
      case TRANSFORMER_FFN_BLOCK_KIND: {
        const auto& b = *static_cast<const TransformerFFNDesc*>(entry.second.get());
        ++result.ffn_blocks;
        if (!b.useSwiGLU || b.numChannels != channels || b.preLN.numChannels != channels ||
            b.linear1.inChannels != channels || b.linear1.outChannels != b.ffnChannels ||
            b.linearGate.inChannels != channels || b.linearGate.outChannels != b.ffnChannels ||
            b.linear2.inChannels != b.ffnChannels || b.linear2.outChannels != channels)
          result.valid = false;
        const bool fused = b.useSwiGLU && shape(b.linear1);
        if (fused) ++result.candidates[1];
        matrix(b.linear1, !fused && shape(b.linear1));
        if (b.useSwiGLU) matrix(b.linearGate, !fused && shape(b.linearGate));
        matrix(b.linear2, shape(b.linear2));
        result.graph.push_back({{"swiglu", b.useSwiGLU}, {"fusedFFN", fused}});
        break;
      }
      default: result.valid = false; break;
      }
    }
  };
  const auto& trunk = model.trunk;
  result.graph.push_back({{"modelVersion", model.modelVersion}, {"inputSpatial", model.numInputChannels},
    {"inputGlobal", model.numInputGlobalChannels}, {"inputMetadata", model.numInputMetaChannels},
    {"trunkChannels", trunk.trunkNumChannels}, {"trunkNorm", trunk.trunkNormKind},
    {"trunkActivation", trunk.trunkTipActivation.activation}});
  // These are the descriptor/feature formats understood by this integration,
  // not checkpoints or network widths. Future formats require another review.
  if (model.modelVersion < 14 || model.modelVersion > 17 || model.numInputMetaChannels != 0 ||
      model.numInputChannels != NNInputs::NUM_FEATURES_SPATIAL_V7 ||
      model.numInputGlobalChannels != NNInputs::NUM_FEATURES_GLOBAL_V7 ||
      trunk.numBlocks != static_cast<int>(trunk.blocks.size()) ||
      trunk.initialConv.inChannels != model.numInputChannels ||
      trunk.initialConv.outChannels != trunk.trunkNumChannels ||
      trunk.initialMatMul.inChannels != model.numInputGlobalChannels ||
      trunk.initialMatMul.outChannels != trunk.trunkNumChannels)
    result.valid = false;
  if ((trunk.trunkNormKind == TRUNK_NORM_KIND_STANDARD && trunk.trunkTipBN.numChannels != trunk.trunkNumChannels) ||
      (trunk.trunkNormKind == TRUNK_NORM_KIND_RMSNORM && trunk.trunkTipRMSNorm.numChannels != trunk.trunkNumChannels) ||
      (trunk.trunkNormKind != TRUNK_NORM_KIND_STANDARD && trunk.trunkNormKind != TRUNK_NORM_KIND_RMSNORM))
    result.valid = false;
  blocks(trunk.blocks, trunk.trunkNumChannels, 0);
  // iterConvLayers assumes known block types. Never call it on an unknown graph.
  if (result.valid) {
    model.iterConvLayers([&](const ConvLayerDesc& layer) {
      if (layer.inChannels <= 0 || layer.outChannels <= 0 || layer.convXSize <= 0 ||
          layer.convYSize <= 0 || layer.dilationX != 1 || layer.dilationY != 1) result.valid = false;
      const bool candidate = layer.convXSize == 1 && layer.convYSize == 1 &&
                             accelerated_matrix_shape(layer.inChannels, layer.outChannels);
      result.graph.push_back({{"op", "conv"}, {"x", layer.convXSize}, {"y", layer.convYSize},
        {"in", layer.inChannels}, {"out", layer.outChannels}, {"accelerated", candidate}});
      if (candidate) { ++result.convolution_candidates; ++result.candidates[0]; }
    });
  }
  matrix(trunk.initialMatMul, false);
  const auto& policy = model.policyHead;
  const auto& value = model.valueHead;
  matrix(policy.gpoolToBiasMul, false);
  matrix(policy.gpoolToPassMul, false);
  if (model.modelVersion >= 15) matrix(policy.gpoolToPassMul2, false);
  matrix(value.v2Mul, false);
  matrix(value.v3Mul, false);
  matrix(value.sv3Mul, false);
  if (policy.p1Conv.inChannels != trunk.trunkNumChannels || policy.g1Conv.inChannels != trunk.trunkNumChannels ||
      value.v1Conv.inChannels != trunk.trunkNumChannels || model.numValueChannels != 3 ||
      model.numOwnershipChannels != 1) result.valid = false;
  if (policy.g1BN.numChannels != policy.g1Conv.outChannels ||
      policy.p1BN.numChannels != policy.p1Conv.outChannels || policy.p2Conv.inChannels != policy.p1Conv.outChannels ||
      policy.gpoolToBiasMul.inChannels != static_cast<int64_t>(policy.g1Conv.outChannels) * 3 ||
      policy.gpoolToBiasMul.outChannels != policy.p1Conv.outChannels ||
      policy.gpoolToPassMul.inChannels != static_cast<int64_t>(policy.g1Conv.outChannels) * 3 ||
      policy.p2Conv.outChannels != model.numPolicyChannels ||
      value.v1BN.numChannels != value.v1Conv.outChannels ||
      value.v2Mul.inChannels != static_cast<int64_t>(value.v1Conv.outChannels) * 3 ||
      value.v2Bias.numChannels != value.v2Mul.outChannels || value.v3Mul.inChannels != value.v2Mul.outChannels ||
      value.sv3Mul.inChannels != value.v2Mul.outChannels || value.vOwnershipConv.inChannels != value.v1Conv.outChannels ||
      value.v3Mul.outChannels != model.numValueChannels || value.sv3Mul.outChannels != model.numScoreValueChannels ||
      value.vOwnershipConv.outChannels != model.numOwnershipChannels) result.valid = false;
  result.graph.push_back({{"policyChannels", model.numPolicyChannels}, {"valueChannels", model.numValueChannels},
    {"scoreChannels", model.numScoreValueChannels}, {"ownershipChannels", model.numOwnershipChannels}});
  result.reason = !result.valid ? "unsupported_structure" :
                  result.supported() ? "compatible_operators" : "no_compatible_operators";
  return result;
}

} // namespace GotepadKataGo
