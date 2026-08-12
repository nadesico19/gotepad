// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

// This library exists only while linking the Android OpenCL backend. It gives
// the resulting module a DT_NEEDED entry for the device-provided libOpenCL.so
// and is deliberately never packaged in the APK.
#define CL_TARGET_OPENCL_VERSION 120
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#include <CL/cl.h>
#include <CL/cl_ext.h>

extern "C" {
CL_API_ENTRY cl_int CL_API_CALL clGetPlatformIDs(cl_uint, cl_platform_id *,
                                                 cl_uint *) {
  return CL_PLATFORM_NOT_FOUND_KHR;
}
CL_API_ENTRY cl_int CL_API_CALL clGetPlatformInfo(cl_platform_id,
                                                  cl_platform_info, size_t,
                                                  void *, size_t *) {
  return CL_INVALID_PLATFORM;
}
CL_API_ENTRY cl_int CL_API_CALL clGetDeviceIDs(cl_platform_id, cl_device_type,
                                               cl_uint, cl_device_id *,
                                               cl_uint *) {
  return CL_DEVICE_NOT_FOUND;
}
CL_API_ENTRY cl_int CL_API_CALL clGetDeviceInfo(cl_device_id, cl_device_info,
                                                size_t, void *, size_t *) {
  return CL_INVALID_DEVICE;
}
CL_API_ENTRY cl_context CL_API_CALL
clCreateContext(const cl_context_properties *, cl_uint, const cl_device_id *,
                void(CL_CALLBACK *)(const char *, const void *, size_t, void *),
                void *, cl_int *error) {
  if (error != nullptr)
    *error = CL_INVALID_OPERATION;
  return nullptr;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseContext(cl_context) {
  return CL_INVALID_CONTEXT;
}
CL_API_ENTRY cl_command_queue CL_API_CALL clCreateCommandQueue(
    cl_context, cl_device_id, cl_command_queue_properties, cl_int *error) {
  if (error != nullptr)
    *error = CL_INVALID_OPERATION;
  return nullptr;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseCommandQueue(cl_command_queue) {
  return CL_INVALID_COMMAND_QUEUE;
}
CL_API_ENTRY cl_mem CL_API_CALL clCreateBuffer(cl_context, cl_mem_flags, size_t,
                                               void *, cl_int *error) {
  if (error != nullptr)
    *error = CL_INVALID_OPERATION;
  return nullptr;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseMemObject(cl_mem) {
  return CL_INVALID_MEM_OBJECT;
}
CL_API_ENTRY cl_program CL_API_CALL clCreateProgramWithSource(
    cl_context, cl_uint, const char **, const size_t *, cl_int *error) {
  if (error != nullptr)
    *error = CL_INVALID_OPERATION;
  return nullptr;
}
CL_API_ENTRY cl_int CL_API_CALL
clBuildProgram(cl_program, cl_uint, const cl_device_id *, const char *,
               void(CL_CALLBACK *)(cl_program, void *), void *) {
  return CL_INVALID_PROGRAM;
}
CL_API_ENTRY cl_int CL_API_CALL clGetProgramBuildInfo(cl_program, cl_device_id,
                                                      cl_program_build_info,
                                                      size_t, void *,
                                                      size_t *) {
  return CL_INVALID_PROGRAM;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseProgram(cl_program) {
  return CL_INVALID_PROGRAM;
}
CL_API_ENTRY cl_kernel CL_API_CALL clCreateKernel(cl_program, const char *,
                                                  cl_int *error) {
  if (error != nullptr)
    *error = CL_INVALID_OPERATION;
  return nullptr;
}
CL_API_ENTRY cl_int CL_API_CALL clSetKernelArg(cl_kernel, cl_uint, size_t,
                                               const void *) {
  return CL_INVALID_KERNEL;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseKernel(cl_kernel) {
  return CL_INVALID_KERNEL;
}
CL_API_ENTRY cl_int CL_API_CALL clEnqueueReadBuffer(cl_command_queue, cl_mem,
                                                    cl_bool, size_t, size_t,
                                                    void *, cl_uint,
                                                    const cl_event *,
                                                    cl_event *) {
  return CL_INVALID_COMMAND_QUEUE;
}
CL_API_ENTRY cl_int CL_API_CALL clEnqueueWriteBuffer(cl_command_queue, cl_mem,
                                                     cl_bool, size_t, size_t,
                                                     const void *, cl_uint,
                                                     const cl_event *,
                                                     cl_event *) {
  return CL_INVALID_COMMAND_QUEUE;
}
CL_API_ENTRY cl_int CL_API_CALL clEnqueueNDRangeKernel(
    cl_command_queue, cl_kernel, cl_uint, const size_t *, const size_t *,
    const size_t *, cl_uint, const cl_event *, cl_event *) {
  return CL_INVALID_COMMAND_QUEUE;
}
CL_API_ENTRY cl_int CL_API_CALL clWaitForEvents(cl_uint, const cl_event *) {
  return CL_INVALID_EVENT;
}
CL_API_ENTRY cl_int CL_API_CALL clGetEventProfilingInfo(cl_event,
                                                        cl_profiling_info,
                                                        size_t, void *,
                                                        size_t *) {
  return CL_INVALID_EVENT;
}
CL_API_ENTRY cl_int CL_API_CALL clReleaseEvent(cl_event) {
  return CL_INVALID_EVENT;
}
CL_API_ENTRY cl_int CL_API_CALL clFlush(cl_command_queue) {
  return CL_INVALID_COMMAND_QUEUE;
}
CL_API_ENTRY cl_int CL_API_CALL clFinish(cl_command_queue) {
  return CL_INVALID_COMMAND_QUEUE;
}
}
