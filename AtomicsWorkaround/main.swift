//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Metal

//===----------------------------------------------------------------------===//
// Configuration (change this)
//===----------------------------------------------------------------------===//

// Make this `false` to test 64-bit atomics on an A15 or M2 GPU.
let emulating64BitAtomics: Bool = true

// The method used to emulate 64-bit atomics.
let emulationWorkaroundType: WorkaroundType = .originalNanite

enum WorkaroundType {
  // Lower bandwidth for geometry-heavy scenes.
  case originalNanite
  
  // Removes the need to reconstruct textures, potentially easier to implement.
  // TODO: Record data races encountered in this workaround.
  // TODO: Test whether this works on AMD (was designed for M1).
  
  // This mode is currently broken; DO NOT use it.
  //
  // Why is this currently failing?
  // - Maybe, multiple nearby locations are mapping to the same lock. My tests
  //   in metal-float64 somehow didn't cover this case, yet that specific case
  //   breaks the algorithm.
  // - The same location is mapping to different locks.
  // - Because I didn't link this function as a `MTLDynamicLibrary`.
  //
  // How to resolve the bug:
  // - Test libMetalAtomic64 but make every single address resolve to the same
  //   lock address. If that doesn't cause a test failure, proceed.
  // - Add a new test to MetalFloat64 that perfectly replicates the data we're
  //   entering into the Nanite workaround. I highly doubt that will cause a
  //   failure.
  // - Add a new test that uses textures and perfectly replicates the conditions
  //   from ue5-nanite-macos. Potentially the source of failure.
  // - Extract all the Swift code that compiles libMetalAtomic64 at runtime into
  //   the test. Potentially the source of failure.
  // - Reformat so the entire shader, including anything touching a lock buffer,
  //   is compiled from scratch at runtime. Potentially the source of failure.
  // - Add a new test that copies the Nanite script verbatim into the
  //   metal-float64 test suite. If this doesn't fail, there's a bug in the laws
  //   of physics. I'll need to report it to whoever created this universe.
  case metalFloat64
}

//===----------------------------------------------------------------------===//
// Source code (don't change this)
//===----------------------------------------------------------------------===//

let reconstructingTexture =
  emulating64BitAtomics && emulationWorkaroundType == .originalNanite

let textureWidth = 2
let textureHeight = 2

#if os(macOS)
// A buffer-backed texture must have rows aligned to 16 bytes. Accomplish this
// by setting stride to an even number of 8-bit elements. Align depth/count
// buffers to this stride, so that one address can index into all buffers.
//let textureRowStride = ~1 & (1 + textureWidth)

// Apparently that is not true?
let textureRowStride = ~(512/8 - 1) & ((512/8 - 1) + textureWidth)
#else
// On iOS, the minimum alignment is 64 bytes.
let textureRowStride = ~7 & (7 + textureWidth)
#endif

// High ratio of (numIterationsPerKernelInvocation * numKernelInvocations) /
// (textureWidth * textureHeight) creates heavy congestion, and likely many data
// races.
//
// If the ratio > 256, you can test what happens when the lower 8 bits of a
// depth lock wrap around to 0.
let numIterationsPerKernelInvocation = 20

// Currently debugging failure with MetalFloat64 approach
let numKernelInvocations =
  (emulating64BitAtomics && emulationWorkaroundType == .metalFloat64)
  ? 2 : 100
let numTests = 5

let devices = MTLCopyAllDevices()
let device = devices.first { !$0.isLowPower } ?? devices[0]
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
let reconstructTexturePipeline = try! device.makeComputePipelineState(
  function: library.makeFunction(name: "reconstructTexture")!)
var atomicsTestPipeline: MTLComputePipelineState

// NOTE: You must explicitly `useResource` the lock buffer inside the Metal
// compute command encoder. Otherwise, the GPU will freeze.
var lockBuffer: MTLBuffer!

if emulating64BitAtomics && emulationWorkaroundType == .metalFloat64 {
  // Actual buffer size is twice this, for reasons explained below.
  let lockBufferSize = 1 << 16 * MemoryLayout<UInt32>.stride
  let bufferStorageMode = device.hasUnifiedMemory
    ? MTLResourceOptions.storageModeShared : .storageModePrivate
  let lockBuffer = device.makeBuffer(
    length: 2 * lockBufferSize, options: bufferStorageMode)!

  // Align the base address so its lower bits are all zero. That way, shaders
  // only need to mask the lower bits with the hash. This saves ~3 cycles of
  // ALU time.
  var lockBufferAddress = lockBuffer.gpuAddress
  let sizeMinus1 = UInt64(lockBufferSize - 1)
  lockBufferAddress = ~sizeMinus1 & (lockBufferAddress + sizeMinus1)
  
  let constants = MTLFunctionConstantValues()
  constants.setConstantValue(&lockBufferAddress, type: .ulong, index: 0)
  let function = try! library.makeFunction(
    name: "atomicsTestMetalFloat64", constantValues: constants)
  atomicsTestPipeline = try! device.makeComputePipelineState(function: function)
} else if emulating64BitAtomics {
  atomicsTestPipeline = try! device.makeComputePipelineState(
    function: library.makeFunction(name: "atomicsTestOriginal")!)
} else {
  atomicsTestPipeline = try! device.makeComputePipelineState(
    function: library.makeFunction(name: "atomicsTestApple8")!)
}

// MARK: - Allocate Buffers

#if os(macOS)
// Make sure this runs well on Intel Macs. Using CPU-hosted storage would change
// how atomics are handled and seriously degrade performance.
let bufferOptions: MTLResourceOptions = .storageModeManaged
#else
// Allow testing of native 64-bit atomics on A15 in the future.
let bufferOptions: MTLResourceOptions = .storageModeShared
#endif

// Determine size of resources.
let depthBufferSize = 4 * textureRowStride * textureHeight
let countBufferSize = 4 * textureRowStride * textureHeight
let outBufferSize = 8 * textureRowStride * textureHeight

func makeBuffer(size: Int) -> MTLBuffer {
  device.makeBuffer(length: size, options: bufferOptions)!
}

// Generate buffers.
let depthBuffer = makeBuffer(size: depthBufferSize)
let countBuffer = makeBuffer(size: countBufferSize)
let outBuffer = makeBuffer(size: outBufferSize)

// Generate buffers for debugging and profiling.
let dataRacesBuffer = makeBuffer(size: 4 * 64) // Up to 64 unique error codes.

let textureDesc = MTLTextureDescriptor()
textureDesc.width = textureWidth
textureDesc.height = textureHeight
textureDesc.pixelFormat = .rg32Uint
textureDesc.resourceOptions = bufferOptions
textureDesc.textureType = .type2D
textureDesc.usage = [.shaderRead, .shaderWrite]

// Generate out texture.
let outTexture = outBuffer.makeTexture(
  descriptor: textureDesc, offset: 0, bytesPerRow: 8 * textureRowStride)!

// MARK: - Generate Random Data

struct RandomData {
    var xCoord: UInt32 = 0
    var yCoord: UInt32 = 0
    var color: Float = 0
    var depth: Float = 0
}

// Create buffer for input data.
let randomDataNumElements = numIterationsPerKernelInvocation * numKernelInvocations
let randomDataSize = randomDataNumElements * MemoryLayout<RandomData>.stride
let randomDataBuffer = device.makeBuffer(length: randomDataSize, options: bufferOptions)!

func generateRandomData(ptr: UnsafeMutablePointer<RandomData>) {
  for i in 0..<randomDataNumElements {
    let randomValues = SIMD4<UInt32>.random(in: 0..<UInt32.max)
    var data = unsafeBitCast(randomValues, to: RandomData.self)
    
    // Clamp texture coordinates to something within the texture's bounds.
    data.xCoord %= UInt32(textureWidth)
    data.yCoord %= UInt32(textureHeight)
    
    // Clamp the pixel to [0, 1].
    let color_uint = data.color.bitPattern
    data.color = Float(color_uint) / Float(UInt32.max)
    
    // Keep depths within the range [0, 1]. Otherwise, the GPU's results
    // could differ drastically from the CPU's results.
    data.depth = Float(data.depth.bitPattern) / Float(UInt32.max)
    
    ptr[i] = data
  }
}

func showBits(_ value: Float) -> String {
  let n = value.bitPattern
  return String(format: "%x", n)
}

func showBits(_ value: UInt32) -> String {
  return String(format: "%x", value) + " \(value)"
}

// Returns an array of texture rows.
func generateExpectedResults(
    ptr: UnsafeMutablePointer<RandomData>
) -> [[SIMD2<Float>]] {
  let row = [SIMD2<Float>](repeating: .zero, count: textureWidth)
  var output: [[SIMD2<Float>]] = Array(repeating: row, count: textureHeight)
  
  for i in 0..<numKernelInvocations * numIterationsPerKernelInvocation {
    let xCoord = Int(ptr[i].xCoord)
    let yCoord = Int(ptr[i].yCoord)
    
    var pixel: SIMD2<Float> = .zero
    pixel[0] = ptr[i].color
    pixel[1] = max(0, min(ptr[i].depth, 1))
    if reconstructingTexture {
      let maxDepth: Int = (1 << 24) - 1
      let clampedDepth = UInt32(pixel[1] * Float(maxDepth))
      pixel[1] = Float(bitPattern: clampedDepth)
    }
    
    // On the GPU, this would be an atomic max.
    let previousValue = unsafeBitCast(output[yCoord][xCoord], to: UInt64.self)
    let currentValue = unsafeBitCast(pixel, to: UInt64.self)
    if currentValue > previousValue {
      output[yCoord][xCoord] = pixel
    }
  }
  
  return output
}

// Takes in the texture's base address and an array of texture rows.
//
// Returns total deviation from expected value, in color and depth separately.
//
// The deviation should be zero.
func validateResults(
  ptr: UnsafeMutablePointer<SIMD2<Float>>,
    expected: [[SIMD2<Float>]]
) -> (colorDeviation: Float, depthDeviation: Float) {
  var deviation: SIMD2<Float> = .zero
  for row in 0..<outTexture.height {
    let actualPixels = ptr + row * textureRowStride
    let expectedPixels = expected[row]
    
    for i in 0..<outTexture.width {
      let actual = actualPixels[i]
      var expected = expectedPixels[i]
      if reconstructingTexture {
        let maxDepth: Int = (1 << 24) - 1
        let clampedDepth: UInt32 = expected.y.bitPattern
        let depth = Float(clampedDepth) / Float(maxDepth + 1)
        expected.y = depth
      }
      
      let difference = actual - expected
      deviation.x += abs(difference.x)
      deviation.y += abs(difference.y)
    }
  }
  return (deviation.x, deviation.y)
}

// MARK: - Perform Tests

// Test Structure:
// (1) Generate random data, zero-initialize buffers
// (2) Encode commands on GPU
// (3) While waiting on GPU to finish, calculate what should happen on the CPU.
// (4) Ensure the CPU's results match every GPU result
//
// Note: The CPU and GPU results may differ if two differs colors have the exact
// same depth. The pixels could be written to in a different order, and only the
// first written pixel gets assigned. There is around a 2^-24 chance of this
// happening for any data point.

for i in 0..<numTests {
  let start = Date()
  defer {
    let end = Date()
    let testTime = end.timeIntervalSince(start)
    let milliseconds = Int(testTime * 1000)
    
    print("Test \(i + 1) took \(milliseconds) milliseconds.")
    print()
  }
  
  // Generate random data.
  let randomContents = randomDataBuffer.contents().assumingMemoryBound(to: RandomData.self)
  generateRandomData(ptr: randomContents)
#if os(macOS)
  randomDataBuffer.didModifyRange(0..<randomDataBuffer.length)
#endif
  
  let commandBuffer = commandQueue.makeCommandBuffer()!
  
  // Zero out all buffers.
  let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
  blitEncoder.fill(buffer: depthBuffer, range: 0..<depthBuffer.length, value: 0)
  blitEncoder.fill(buffer: countBuffer, range: 0..<countBuffer.length, value: 0)
  blitEncoder.fill(buffer: outBuffer, range: 0..<outBuffer.length, value: 0)
  blitEncoder.fill(buffer: dataRacesBuffer, range: 0..<dataRacesBuffer.length, value: 0)
  blitEncoder.endEncoding()
  
  let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
  if let lockBuffer = lockBuffer {
    computeEncoder.useResource(lockBuffer, usage: [.read, .write])
  }
  computeEncoder.setComputePipelineState(atomicsTestPipeline)
  
  struct DispatchParams {
    var writesPerThread: UInt32 = 0
    var textureRowStride: UInt32 = 0
  }
  
  // Set dispatch parameters.
  var params = DispatchParams()
  params.writesPerThread = .init(numIterationsPerKernelInvocation)
  params.textureRowStride = .init(textureRowStride)
  let paramsLength = MemoryLayout<DispatchParams>.stride
  computeEncoder.setBytes(&params, length: paramsLength, index: 0)
  
  computeEncoder.setBuffer(randomDataBuffer, offset: 0, index: 1)
  computeEncoder.setBuffer(outBuffer, offset: 0, index: 4)
  if reconstructingTexture {
    computeEncoder.setBuffer(depthBuffer, offset: 0, index: 2)
    computeEncoder.setBuffer(countBuffer, offset: 0, index: 3)
    computeEncoder.setBuffer(dataRacesBuffer, offset: 0, index: 5)
  }
  do {
    let gridSize = MTLSizeMake(numKernelInvocations, 1, 1)
    let threadgroupSize = MTLSizeMake(1, 1, 1)
    computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
  }
  
  if reconstructingTexture {
    computeEncoder.setComputePipelineState(reconstructTexturePipeline)
    
    // params already bound to index 0.
    // depthBuffer already bound to index 2.
    // outBuffer already bound to index 4.
    computeEncoder.setTexture(outTexture, index: 0)
    do {
      let gridSize = MTLSizeMake(outTexture.width, outTexture.height, 1)
      let threadgroupSize = MTLSizeMake(1, 1, 1)
      computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
    }
  }
  
  computeEncoder.endEncoding()
  commandBuffer.commit()
  
  // Compute results on CPU while waiting for GPU.
  let results = generateExpectedResults(ptr: randomContents)
  commandBuffer.waitUntilCompleted()
  
  // Validate results.
  let outContents = outBuffer.contents().assumingMemoryBound(to: SIMD2<Float>.self)
  let deviation = validateResults(ptr: outContents, expected: results)
  print("Deviation: \(deviation)")
  
  let dataRacesContents = dataRacesBuffer.contents().assumingMemoryBound(to: UInt32.self)
  for i in 0..<64 {
    if dataRacesContents[i] > 0 {
      print("There were \(dataRacesContents[i]) data races with error code \(i).")
    }
  }
}

// From https://github.com/philipturner/metal-float64

// NOTE: Ensure this documentation comment stays synchronized with the C header.

/// Compile a 64-bit atomics library that embeds the lock buffer's GPU virtual
/// address into the binary. This library eliminates the need to specify a lock
/// buffer when encoding commands.
///
/// To hard-code the lock buffer's GPU virtual address into the executable, we
/// must compile some code at runtime. This mini-dylib provides a C-accessible
/// function for generating the library. It returns an opaque pointer for the
/// `MTLDynamicLibrary` object and lock buffer object (both retain count +1).
/// Each invokation generates a brand new library and lock buffer. You are
/// responsible for decrementing their reference counts upon deallocation.
///
/// During the linking stage of compilation, MetalAtomic64 needs a copy of
/// libMetalFloat64. The Atomic64 library depends on the Float64 library,
/// although this dependency is not circular. The Float64 library doesn't
/// internally depend on the Atomic64 library. Its header just exposes symbols
/// for atomic functions. To make your shaders (which import the header) link
/// correctly, they must see libMetalAtomic64 at load time. Either (a) serialize
/// libMetalAtomic64 into the same directory as libMetalFloat64 or (b) add it to
/// the `preloadedLibraries` property of your pipeline descriptor.
///
/// The lock buffer is allocated on the `MTLDevice` that generated the
/// `float64_library` object. If this device is a discrete GPU, the buffer will
/// be in the private storage mode. Otherwise, it will be in the shared storage
/// mode. The buffer comes out zero-initialized, but you are responsible for
/// resetting it upon corruption. The lock buffer could become corrupted if the
/// GPU aborts a command buffer while one thread has acquired a lock, but not
/// yet released it.
///
/// If you're using this function from C or C++, you may have to copy the dylib
/// manually. In that case, it's compiled slightly different from the SwiftPM
/// version. The build script copies the shader code into the Swift file as a
/// string literal. This means you don't have to worry about whether shader
/// files are in the same directory as "libMetalAtomic64.dylib". The C/C++
/// compile path also packages a C header for the dynamic library.
///
/// - Parameters:
///   - float64_library: The MetalFloat64 library to link against.
///   - atomic64_library: The MetalAtomic64 library your client code will call
///     into.
///   - lock_buffer: The lock buffer whose base address is encoded into
///     `atomic64_library`.
public func metal_atomic64_generate_library(
  _ float64_library: MTLDynamicLibrary
) -> (
  atomic64_library: MTLDynamicLibrary,
  lock_buffer: MTLBuffer
) {
  // Fetch the float64 library's Metal device.
  let device = float64_library.device
  
  // Actual buffer size is twice this, for reasons explained below.
  let lockBufferSize = 1 << 16 * MemoryLayout<UInt32>.stride
  let bufferStorageMode = device.hasUnifiedMemory
    ? MTLResourceOptions.storageModeShared : .storageModePrivate
  let lockBuffer = device.makeBuffer(
    length: 2 * lockBufferSize, options: bufferStorageMode)!
  
  // Align the base address so its lower bits are all zero. That way, shaders
  // only need to mask the lower bits with the hash. This saves ~3 cycles of
  // ALU time.
  var lockBufferAddress = lockBuffer.gpuAddress
  let sizeMinus1 = UInt64(lockBufferSize - 1)
  lockBufferAddress = ~sizeMinus1 & (lockBufferAddress + sizeMinus1)
  
  let options = MTLCompileOptions()
  options.libraries = [float64_library]
  options.optimizationLevel = .size
  options.preprocessorMacros = [
    "METAL_ATOMIC64_LOCK_BUFFER_ADDRESS": NSNumber(value: lockBufferAddress)
  ]
  options.libraryType = .dynamic
  options.installName = "@loader_path/libMetalAtomic64.metallib"
  let atomic64Library_raw = try! device.makeLibrary(
    source: shader_source, options: options)
  let atomic64Library = try! device.makeDynamicLibrary(
    library: atomic64Library_raw)
  
  return (atomic64Library, lockBuffer)
}

private let shader_source = """
//
//  Atomic.metal
//
//
//  Created by Philip Turner on 12/16/22.
//

#include <metal_stdlib>
using namespace metal;

// When compiling sources at runtime, your only option is to expose all symbols
// by default. Therefore, we explicitly set the EXPORT macro to nothing.
#define EXPORT
#define NOEXPORT static

// Apply this to functions that shouldn't be inlined internally.
// Place at the function definition.
#define NOINLINE __attribute__((__noinline__))

// Apply this to force-inline functions internally.
// The Metal Standard Library uses it, so it should work reliably.
#define ALWAYS_INLINE __attribute__((__always_inline__))
#define INTERNAL_INLINE NOEXPORT ALWAYS_INLINE

// MARK: - Embedded Reference to Lock Buffer

// Reference to existing implementation:
// https://github.com/kokkos/kokkos/blob/master/tpls/desul/include/desul/atomics/Lock_Array.hpp
//
// namespace desul {
// namespace Impl {
// struct host_locks__ {
//   static constexpr uint32_t HOST_SPACE_ATOMIC_MASK = 0xFFFF;
//   static constexpr uint32_t HOST_SPACE_ATOMIC_XOR_MASK = 0x5A39;
//   template <typename is_always_void = void>
//   static int32_t* get_host_locks_() {
//     static int32_t HOST_SPACE_ATOMIC_LOCKS_DEVICE[HOST_SPACE_ATOMIC_MASK + 1] = {0};
//     return HOST_SPACE_ATOMIC_LOCKS_DEVICE;
//   }
//   static inline int32_t* get_host_lock_(void* ptr) {
//     return &get_host_locks_()[((uint64_t(ptr) >> 2) & HOST_SPACE_ATOMIC_MASK) ^
//                               HOST_SPACE_ATOMIC_XOR_MASK];
//   }
// };
//
// https://github.com/kokkos/kokkos/blob/master/tpls/desul/include/desul/atomics/Generic.hpp
//
////  This is a way to avoid dead lock in a warp or wave front
// T return_val;
// int done = 0;
// #ifdef __HIPCC__
// unsigned long long int active = DESUL_IMPL_BALLOT_MASK(1);
// unsigned long long int done_active = 0;
// while (active != done_active) {
//   if (!done) {
//     if (Impl::lock_address_hip((void*)dest, scope)) {
//       atomic_thread_fence(MemoryOrderAcquire(), scope);
//       return_val = op.apply(*dest, val);
//       *dest = return_val;
//       atomic_thread_fence(MemoryOrderRelease(), scope);
//       Impl::unlock_address_hip((void*)dest, scope);
//       done = 1;
//     }
//   }
//   done_active = DESUL_IMPL_BALLOT_MASK(done);
// }

#if defined(METAL_ATOMIC64_PLACEHOLDER)
static constant size_t lock_buffer_address = 0;
#else
static constant size_t lock_buffer_address = METAL_ATOMIC64_LOCK_BUFFER_ADDRESS;
#endif

struct LockBufferAddressWrapper {
  device atomic_uint* address;
};

struct DeviceAddressWrapper {
  device atomic_uint* address;
};

// This assumes the object is aligned to 8 bytes (the address's lower 3 bits
// are all zeroes). Otherwise, behavior is undefined.
INTERNAL_INLINE device atomic_uint* get_lock(device ulong* object) {
  DeviceAddressWrapper wrapper{ (device atomic_uint*)object };
  uint lower_bits = reinterpret_cast<thread uint2&>(wrapper)[0];
  uint hash = extract_bits(lower_bits, 1, 18) ^ (0x5A39 << 2);
  
  // TODO: Explicitly, OR only the lower 32 bits (this currently sign extends).
  auto this_address = lock_buffer_address | hash;
  auto lock_ref = reinterpret_cast<thread LockBufferAddressWrapper&>
     (this_address);
  return lock_ref.address;
}

INTERNAL_INLINE bool try_acquire_lock(device atomic_uint* lock) {
  uint expected = 0;
  uint desired = 1;
  return metal::atomic_compare_exchange_weak_explicit(
    lock, &expected, desired, memory_order_relaxed, memory_order_relaxed);
}

INTERNAL_INLINE void release_lock(device atomic_uint* lock) {
  atomic_store_explicit(lock, 0, memory_order_relaxed);
}

// The address should be aligned, so simply mask the address before reading.
// That incurs (hopefully) one cycle overhead + register swap, instead of four
// cycles overhead + register swap. Not sure whether the increased register
// pressure is a bad thing.
INTERNAL_INLINE device atomic_uint* get_upper_address(device atomic_uint* lower) {
  DeviceAddressWrapper wrapper{ lower };
  auto lower_bits = reinterpret_cast<thread uint2&>(wrapper);
  uint2 upper_bits{ lower_bits[0] | 4, lower_bits[1] };
  return reinterpret_cast<thread DeviceAddressWrapper&>(upper_bits).address;
}

// Only call this while holding a lock.
INTERNAL_INLINE ulong memory_load(device atomic_uint* lower, device atomic_uint* upper) {
  uint out_lo = metal::atomic_load_explicit(lower, memory_order_relaxed);
  uint out_hi = metal::atomic_load_explicit(upper, memory_order_relaxed);
  return as_type<ulong>(uint2(out_lo, out_hi));
}

// Only call this while holding a lock.
INTERNAL_INLINE void memory_store(device atomic_uint *lower, device atomic_uint* upper, ulong desired) {
  uint in_lo = as_type<uint2>(desired)[0];
  uint in_hi = as_type<uint2>(desired)[1];
  metal::atomic_store_explicit(lower, in_lo, memory_order_relaxed);
  metal::atomic_store_explicit(upper, in_hi, memory_order_relaxed);
  
  // Validate that the written value reads what you expect.
  while (true) {
    if (desired == memory_load(lower, upper)) {
      break;
    } else {
      // This branch never happens, but it's necessary to prevent some kind of
      // compiler or runtime optimization.
    }
  }
}

// MARK: - Implementation of Exposed Functions

namespace metal_float64
{
extern uint increment(uint x);
} // namespace metal_float64

// We utilize the type ID at runtime to dynamically dispatch to different
// functions. This approach minimizes the time necessary to compile
// MetalAtomic64 from scratch at runtime, while reducing binary size. Also,
// atomic operations will be memory bound, so the ALU time for switching over
// enum cases should be hidden.
//
// Several operations are fused into common functions, reducing compile time and
// binary size by ~70%.
// - group 1: add_i/u64, add_f64, add_f59, add_f43
// - group 2: sub_i/u64, sub_f64, sub_f59, sub_f43
// - group 3: max_i64, max_u64, max_f64, max_f59, max_f43
// - group 4: min_i64, min_u64, min_f64, min_f59, min_f43
// - group 5: and_i/u64, or_i/u64, xor_i/u64
// - group 6: cmpxchg_i/u64, cmpxchg_f64, cmpxchg_f59, cmpxchg_f43
// - group 7: store, load, xchg
enum __metal_atomic64_type_id: ushort {
  i64 = 0, // signed long
  u64 = 1, // unsigned long
  f64 = 2, // IEEE double precision
  f59 = 3, // 59-bit reduced precision
  f43 = 4, // 43-bit reduced precision
  f32x2 = 5, // double-single approach
  f32 = 6, // software-emulated single precision for validation
};

// Entering an invalid operation ID causes undefined behavior at runtime.
enum __metal_atomic64_operation_id: ushort {
  store = 0, // atomic_store_explicit
  load = 1, // atomic_load_explicit
  xchg = 2, // atomic_exchange_explicit
  logical_and = 3, // atomic_fetch_and_explicit
  logical_or = 4, // atomic_fetch_or_explicit
  logical_xor = 5, // atomic_fetch_xor_explicit
};

// TODO: You can't just implement atomics through a threadgroup barrier. In
// between the barrier, two threads could still write to the same address.
// Solution: an __extremely__ slow workaround that takes the threadgroup memory
// pointer (presumably 32 bits), hashes both the upper and lower 16 bits, then
// uses the device lock buffer to synchronize.
//
// Alternatively, find some neat hack with bank conflicts that's inherently
// atomic. Perhaps stagger operations based on thread ID. We can also access
// the `SReg32` on Apple GPUs, which stores the thread's index in the
// threadgroup: https://github.com/dougallj/applegpu/blob/main/applegpu.py. Or,
// include the threadgroup's ID in the hash, minimizing conflicts over a common
// lock between threadgroups.
//
// If the threadgroup memory pointer size is truly indecipherable, and/or varies
// between Apple and AMD, try the following. Allocate 64 bits of register or
// stack memory. Write the threadgroup pointer to its base. Hash all 64 bits.
// As an optimization, also function-call into pre-compiled AIR code that
// fetches the threadgroup ID from an SReg32. Incorporate that into the hash
// too.
EXPORT void __metal_atomic64_store_explicit(threadgroup ulong* object, ulong desired) {
  // Ensuring binary dependency to MetalFloat64. TODO: Remove
  {
    uint x = 1;
    x = metal_float64::increment(x);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  object[0] = desired;
  threadgroup_barrier(mem_flags::mem_threadgroup);
}

EXPORT void __metal_atomic64_store_explicit(device ulong* object, ulong desired) {
  // Ensuring binary dependency to MetalFloat64. TODO: Remove
  {
    uint x = 1;
    x = metal_float64::increment(x);
  }
  // acquire lock
  object[0] = desired;
  // release lock
}

// TODO: Transform this into a templated function.
EXPORT ulong __metal_atomic64_fetch_add_explicit(device ulong* object, ulong operand, __metal_atomic64_type_id type) {
  device atomic_uint* lock = get_lock(object);
  auto lower_address = reinterpret_cast<device atomic_uint*>(object);
  auto upper_address = get_upper_address(lower_address);
  ulong output;
  
  // Avoids a deadlock when threads in the same simdgroup access the same memory
  // location, during the same function call.
  bool done = false;
  simd_vote active = simd_active_threads_mask();
  simd_vote done_active(0);
  using vote_t = simd_vote::vote_t;
  
  while (vote_t(active) != vote_t(done_active)) {
    if (!done) {
      if (try_acquire_lock(lock)) {
        ulong previous = memory_load(lower_address, upper_address);
        output = previous + operand;
        memory_store(lower_address, upper_address, output);
        release_lock(lock);
        done = true;
      }
    }
    done_active = simd_ballot(done);
  }
  return output;
}
"""
