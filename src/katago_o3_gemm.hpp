#pragma once

#include <android/log.h>
#include <array>
#include <cstdint>
#include <exception>
#include <string>
#include <vector>

#include "neuralnet/openclhelpers.h"
#include <CL/cl_ext.h>
#include "katago_model_acceleration.hpp"
#include "katago_model_structure.hpp"

namespace GotepadKataGo {

// Model-specific candidate: a 32x32 output tile, 16 input channels per local-memory tile.
// Separate output buffers preserve the existing NCHW layout without split copies.
inline constexpr char kO3GemmSource[] = R"CLC(
#pragma OPENCL EXTENSION cl_khr_fp16 : enable

inline half4 load_spatial4(__global const half* src, int base, int x) {
  if(x + 3 < 361) return vload4(0, src + base + x);
  half4 v = (half4)(0);
  // Explicit components avoid dynamic half-vector indexing on the O3 compiler.
  if(x < 361) v.s0 = src[base + x];
  if(x + 1 < 361) v.s1 = src[base + x + 1];
  if(x + 2 < 361) v.s2 = src[base + x + 2];
  if(x + 3 < 361) v.s3 = src[base + x + 3];
  return v;
}

inline void store_spatial4(__global half* dst, int base, int x, half4 v) {
  if(x + 3 < 361) vstore4(v, 0, dst + base + x);
  else {
    if(x < 361) dst[base + x] = v.s0;
    if(x + 1 < 361) dst[base + x + 1] = v.s1;
    if(x + 2 < 361) dst[base + x + 2] = v.s2;
    if(x + 3 < 361) dst[base + x + 3] = v.s3;
  }
}

__attribute__((reqd_work_group_size(8,8,1)))
__kernel void o3_projection(
  __global const half* input,
  __global const half* w0, __global const half* w1, __global const half* w2,
  __global half* out0, __global half* out1, __global half* out2,
  int in_channels, int out_channels
) {
  const int lx = get_local_id(0), ly = get_local_id(1);
  const int tid = ly * 8 + lx;
  const int x0 = get_group_id(0) * 32;
  const int c0 = get_group_id(1) * 32;
  const int batch = get_group_id(2);
  __local half4 a[16][8];
  __local half4 b[GROUPS][16][8];
  half4 acc[GROUPS][4];
  #pragma unroll
  for(int g = 0; g < GROUPS; ++g)
    #pragma unroll
    for(int c = 0; c < 4; ++c) acc[g][c] = (half4)(0);

  for(int kb = 0; kb < in_channels; kb += 16) {
    // Each lane loads two vectors; consecutive lanes access consecutive x/channels.
    for(int t = tid; t < 128; t += 64) {
      int k = t / 8, v = t % 8;
      a[k][v] = load_spatial4(input, (batch * in_channels + kb + k) * 361, x0 + v * 4);
      int wi = (kb + k) * out_channels + c0 + v * 4;
      b[0][k][v] = vload4(0, w0 + wi);
      #if GROUPS >= 2
      b[1][k][v] = vload4(0, w1 + wi);
      #endif
      #if GROUPS >= 3
      b[2][k][v] = vload4(0, w2 + wi);
      #endif
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    #pragma unroll
    for(int k = 0; k < 16; ++k) {
      half4 av = a[k][lx];
      #pragma unroll
      for(int g = 0; g < GROUPS; ++g) {
        half4 bv = b[g][k][ly];
        acc[g][0] += av * bv.s0;
        acc[g][1] += av * bv.s1;
        acc[g][2] += av * bv.s2;
        acc[g][3] += av * bv.s3;
      }
    }
    barrier(CLK_LOCAL_MEM_FENCE);
  }

  #pragma unroll
  for(int c = 0; c < 4; ++c) {
    int base = (batch * out_channels + c0 + ly * 4 + c) * 361;
    #if GROUPS == 2
    // Match the original half projection outputs followed by float SwiGLU.
    float4 main_value = convert_float4(acc[0][c]);
    float4 gate_value = convert_float4(acc[1][c]);
    half4 result = convert_half4_rte((main_value / (1.0f + exp(-main_value))) * gate_value);
    store_spatial4(out0, base, x0 + lx * 4, result);
    #else
    store_spatial4(out0, base, x0 + lx * 4, acc[0][c]);
    #if GROUPS == 3
    store_spatial4(out1, base, x0 + lx * 4, acc[1][c]);
    store_spatial4(out2, base, x0 + lx * 4, acc[2][c]);
    #endif
    #endif
  }
}
)CLC";

class O3Gemm final {
public:
  O3Gemm() = default;
  O3Gemm(const O3Gemm&) = delete;
  O3Gemm& operator=(const O3Gemm&) = delete;
  ~O3Gemm();
  void configure(cl_context context, cl_device_id device, bool enable, const ModelAccelerationStructure& structure);
  bool conv_enabled() const { return convolution_candidates_ > 0; }
  const char* kernel_path() const { return "structure-gemm-v2"; }
  bool enabled() const { return enabled_ && !validation_bypass_; }
  const std::string& initialization_reason() const { return initialization_reason_; }
  const nlohmann::json& capability_status() const { return capability_status_; }
  void set_validation_bypass(bool bypass) { validation_bypass_ = bypass; validation_tracking_ = true; }
  const std::array<uint64_t, 3>& validation_calls() const { return validation_calls_; }
  bool apply(cl_command_queue queue, int groups, int in_channels, int out_channels,
             int batch, cl_mem input, cl_mem w0, cl_mem w1, cl_mem w2,
             cl_mem out0, cl_mem out1, cl_mem out2, cl_event* event);

private:
  std::array<cl_program, 3> programs_{};
  std::array<cl_kernel, 3> kernels_{};
  bool enabled_ = false;
  std::string initialization_reason_ = "kernel_initialization_failed";
  nlohmann::json capability_status_ = {{"checked", false}};
  int convolution_candidates_ = 0;
  std::array<int, 3> candidates_{};
  bool validation_bypass_ = false;
  bool validation_tracking_ = false;
  std::array<uint64_t, 3> validation_calls_{};
  bool failed_(cl_int error, const char* operation);
};

inline O3Gemm::~O3Gemm() {
  remove_acceleration(this);
  for (cl_kernel kernel : kernels_) if (kernel != nullptr) clReleaseKernel(kernel);
  for (cl_program program : programs_) if (program != nullptr) clReleaseProgram(program);
}

inline void O3Gemm::configure(cl_context context, cl_device_id device, bool enable, const ModelAccelerationStructure& structure) {
  convolution_candidates_ = structure.convolution_candidates;
  candidates_ = structure.candidates;
  if (!enable) return;
  try {
    // The original backend's tuning preference is not a capability test for
    // these independent kernels. Query the device, then compile our actual code.
    capability_status_["checked"] = true;
    size_t extension_size = 0;
    cl_int status = clGetDeviceInfo(device, CL_DEVICE_EXTENSIONS, 0, nullptr, &extension_size);
    if (status != CL_SUCCESS || extension_size == 0) {
      initialization_reason_ = "device_capability_query_failed";
      capability_status_["queryError"] = status;
      return;
    }
    std::vector<char> extensions(extension_size + 1, 0);
    status = clGetDeviceInfo(device, CL_DEVICE_EXTENSIONS, extension_size, extensions.data(), nullptr);
    if (status != CL_SUCCESS) {
      initialization_reason_ = "device_capability_query_failed";
      capability_status_["queryError"] = status;
      return;
    }
    const bool has_fp16 = (" " + std::string(extensions.data()) + " ").find(" cl_khr_fp16 ") != std::string::npos;
    capability_status_["fp16Extension"] = has_fp16;
    if (!has_fp16) { initialization_reason_ = "device_fp16_not_supported"; return; }
    cl_device_fp_config half_config = 0;
    status = clGetDeviceInfo(device, CL_DEVICE_HALF_FP_CONFIG, sizeof(half_config), &half_config, nullptr);
    capability_status_["halfFpConfig"] = static_cast<uint64_t>(half_config);
    if (status != CL_SUCCESS) {
      initialization_reason_ = "device_capability_query_failed";
      capability_status_["queryError"] = status;
      return;
    }
    if ((half_config & CL_FP_ROUND_TO_NEAREST) == 0) {
      initialization_reason_ = "device_fp16_not_supported";
      return;
    }
    for (int g = 1; g <= 3; ++g) {
      if (candidates_[g - 1] == 0) continue;
      std::string error;
      if (!OpenCLHelpers::tryCompileProgram("gotepad_o3_gemm_v1", context, {device},
            kO3GemmSource, "-DGROUPS=" + std::to_string(g), programs_[g - 1], error)) {
        initialization_reason_ = "kernel_compilation_failed";
        capability_status_["buildError"] = error;
        __android_log_print(ANDROID_LOG_WARN, "GotepadO3Gemm",
                            "Compilation failed; using original kernels: %s", error.c_str());
        return;
      }
      cl_int status = CL_SUCCESS;
      kernels_[g - 1] = clCreateKernel(programs_[g - 1], "o3_projection", &status);
      if (failed_(status, "clCreateKernel")) return;
      size_t maximum = 0;
      status = clGetKernelWorkGroupInfo(kernels_[g - 1], device, CL_KERNEL_WORK_GROUP_SIZE,
                                       sizeof(maximum), &maximum, nullptr);
      if (failed_(status, "clGetKernelWorkGroupInfo")) return;
      if (maximum < 64) { failed_(CL_INVALID_WORK_GROUP_SIZE, "workgroup size"); return; }
      cl_ulong required_local = 0, available_local = 0;
      status = clGetKernelWorkGroupInfo(kernels_[g - 1], device, CL_KERNEL_LOCAL_MEM_SIZE,
                                       sizeof(required_local), &required_local, nullptr);
      if (failed_(status, "CL_KERNEL_LOCAL_MEM_SIZE")) return;
      status = clGetDeviceInfo(device, CL_DEVICE_LOCAL_MEM_SIZE, sizeof(available_local), &available_local, nullptr);
      if (failed_(status, "CL_DEVICE_LOCAL_MEM_SIZE")) return;
      if (required_local > available_local) { failed_(CL_OUT_OF_RESOURCES, "local memory size"); return; }
    }
    enabled_ = true;
    initialization_reason_ = "enabled";
    __android_log_write(ANDROID_LOG_INFO, "GotepadO3Gemm", "Structure GEMM v2 enabled (FP16, 19x19)");
  } catch (const std::exception& error) {
    enabled_ = false;
    capability_status_["initializationError"] = error.what();
    __android_log_print(ANDROID_LOG_WARN, "GotepadO3Gemm",
                        "Initialization failed; using original kernels: %s", error.what());
  }
}

inline bool O3Gemm::failed_(cl_int error, const char* operation) {
  if (error == CL_SUCCESS) return false;
  enabled_ = false;
  capability_status_["operation"] = operation;
  capability_status_["openclError"] = error;
  fail_acceleration(this);
  __android_log_print(ANDROID_LOG_WARN, "GotepadO3Gemm", "%s failed (%d); using original kernels", operation, error);
  return true;
}

inline bool O3Gemm::apply(cl_command_queue queue, int groups, int in_channels,
                         int out_channels, int batch, cl_mem input,
                         cl_mem w0, cl_mem w1, cl_mem w2,
                         cl_mem out0, cl_mem out1, cl_mem out2, cl_event* event) {
  if (!enabled() || batch < 1 || batch > 32 || groups < 1 || groups > 3) return false;
  const bool supported = candidates_[groups - 1] > 0 && accelerated_matrix_shape(in_channels, out_channels);
  if (!supported) return false;
  cl_kernel kernel = kernels_[groups - 1];
  const std::array<cl_mem, 7> buffers{input, w0, w1, w2, out0, out1, out2};
  for (cl_uint i = 0; i < buffers.size(); ++i)
    if (failed_(clSetKernelArg(kernel, i, sizeof(cl_mem), &buffers[i]), "clSetKernelArg")) return false;
  if (failed_(clSetKernelArg(kernel, 7, sizeof(int), &in_channels), "clSetKernelArg")) return false;
  if (failed_(clSetKernelArg(kernel, 8, sizeof(int), &out_channels), "clSetKernelArg")) return false;
  const size_t global[3] = {12 * 8, static_cast<size_t>(out_channels / 32 * 8), static_cast<size_t>(batch)};
  const size_t local[3] = {8, 8, 1};
  if (failed_(clEnqueueNDRangeKernel(queue, kernel, 3, nullptr, global, local,
                                    0, nullptr, event), "clEnqueueNDRangeKernel")) return false;
  if (validation_tracking_) ++validation_calls_[groups - 1];
  return true;
}

} // namespace GotepadKataGo
