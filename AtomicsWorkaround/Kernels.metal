//
//  Kernels.metal
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

#include <metal_stdlib>
using namespace metal;

struct DispatchParams {
    uint writesPerThread;
    uint textureRowStride;
};

struct RandomData {
    uint xCoord;
    uint yCoord;
    float color;
    float depth;
};

// Records every time a certain data race happens.
class DataRaces {
  device atomic_uint *atomics;
  
public:
  DataRaces(device atomic_uint *atomics) {
    this->atomics = atomics;
  }
  
  void recordEvent(int code, int value) {
    atomic_fetch_add_explicit(atomics + code, value, memory_order_relaxed);
  }
};

constant uint MAX_DEPTH = (1 << 24) - 1;

ushort test_depth(uint index,
                  float depth,
                  device atomic_uint *depthBuffer,
                  device atomic_uint *countBuffer,
                  DataRaces dataRaces);

// Must zero-initialize lock, count, and out buffers beforehand.
// Tracks data races to help you profile it; do not include `data_races` in the
// final Unreal Engine implementation.
kernel void atomicsTestOriginal(constant DispatchParams &params [[buffer(0)]],
                                device RandomData *randomData [[buffer(1)]],
                                device atomic_uint *depthBuffer [[buffer(2)]],
                                device atomic_uint *countBuffer [[buffer(3)]],
                                device atomic_uint *outBuffer [[buffer(4)]],
                                device atomic_uint *data_races [[buffer(5)]],
                                uint tid [[thread_position_in_grid]])
{
  uint startIndex = tid * params.writesPerThread;
  uint endIndex = startIndex + params.writesPerThread;
  DataRaces dataRaces(data_races);
  
  for (uint i = startIndex; i < endIndex; ++i)
  {
    auto data = randomData[i];
    uint index = data.yCoord * params.textureRowStride + data.xCoord;
    ushort counter = test_depth(
      index, data.depth, depthBuffer, countBuffer, dataRaces);
    if (counter == 0) {
      continue;
    }
    
    ushort2 color_parts = as_type<ushort2>(data.color);
    uint atomic_words[2] = {
      as_type<uint>(ushort2(color_parts[0], counter)),
      as_type<uint>(ushort2(color_parts[1], counter)),
    };
    
    device atomic_uint *out_ptr = outBuffer + (index * 2);
    atomic_fetch_max_explicit(out_ptr + 0, atomic_words[0], memory_order_relaxed);
    atomic_fetch_max_explicit(out_ptr + 1, atomic_words[1], memory_order_relaxed);
  }
}

#if defined(__HAVE_ATOMIC_ULONG_MIN_MAX__)
kernel void atomicsTestApple8(constant DispatchParams &params [[buffer(0)]],
                              device RandomData *randomData [[buffer(1)]],
                              device atomic_ulong *outBuffer [[buffer(4)]],
                              uint tid [[thread_position_in_grid]])
{
  uint startIndex = tid * params.writesPerThread;
  uint endIndex = startIndex + params.writesPerThread;
  
  for (uint i = startIndex; i < endIndex; ++i)
  {
    auto data = randomData[i];
    uint index = data.yCoord * params.textureRowStride + data.xCoord;
    auto pixel = as_type<ulong>(uint2{
      as_type<uint>(data.color),
      as_type<uint>(data.depth),
    });
    
    atomic_max_explicit(outBuffer + index, pixel, memory_order_relaxed);
  }
}
#endif

ulong __metal_atomic64_fetch_max_explicit(device ulong* object, ulong operand);

kernel void atomicsTestMetalFloat64(constant DispatchParams &params [[buffer(0)]],
                                    device RandomData *randomData [[buffer(1)]],
                                    device ulong *outBuffer [[buffer(4)]],
                                    uint tid [[thread_position_in_grid]])
{
  uint startIndex = tid * params.writesPerThread;
  uint endIndex = startIndex + params.writesPerThread;
  
  for (uint i = startIndex; i < endIndex; ++i)
  {
    auto data = randomData[i];
    uint index = data.yCoord * params.textureRowStride + data.xCoord;
    auto pixel = as_type<ulong>(uint2{
      as_type<uint>(data.color),
      as_type<uint>(data.depth),
    });
    
    __metal_atomic64_fetch_max_explicit(outBuffer + index, pixel);
  }
}

// Thread dispatch size must equal texture dimensions.
kernel void reconstructTexture(constant DispatchParams &params [[buffer(0)]],
                               device uint *depthBuffer [[buffer(2)]],
                               device uint2 *outBuffer [[buffer(4)]],
                               texture2d<uint, access::read_write> outTexture [[texture(0)]],
                               uint2 tid [[thread_position_in_grid]])
{
  uint index = tid.y * params.textureRowStride + tid.x;
  
  // The converted float is clamped to 0.99999999. In the Nanite
  // implementation with 64-bit atomics, the maximum possible depth is 1.0.
  // That's because `asuint` takes the float's bitpattern, which can exceed
  // 24 bits.
  uint clamped_depth = depthBuffer[index] >> 8;
  float depth = float(clamped_depth) / float(MAX_DEPTH + 1);
  
  uint2 read_values = outBuffer[index];
  ushort2 color_parts = {
    as_type<ushort2>(read_values[0])[0],
    as_type<ushort2>(read_values[1])[0],
  };
  float color = as_type<float>(color_parts);
  
  uint4 pixel{ as_type<uint>(color), as_type<uint>(depth) };
  outTexture.write(pixel, tid);
}

// Returns 0 if the test failed. Otherwise, the return value must be >= 1
// because we first increment the pixel's counter, then return it.
inline ushort test_depth(uint index,
                         float depth,
                         device atomic_uint *depthBuffer,
                         device atomic_uint *countBuffer,
                         DataRaces dataRaces) {
  // Represent depth as 24-bit normalized integer.
  uint clamped_depth( saturate(depth) * float(MAX_DEPTH) );
  
  // Masks the lower 8 bits with zeroes. This means it can't be
  // considered "larger" than another value with the same depth, but a
  // different lower 8 bits.
  uint comparison_depth = clamped_depth << 8;
  device atomic_uint* depth_ptr = depthBuffer + index;
  
  // Spin until you access the atomic value in a sanitized way.
  ushort output;
  ushort num_data_races_1 = 0; // for profiling
  ushort num_data_races_2 = 0; // for profiling
  while (true) {
    uint current_depth = atomic_load_explicit(depth_ptr, memory_order_relaxed);
    if (comparison_depth <= current_depth) {
      output = 0;
      break;
    }
    
    uchar current_counter(current_depth);
    uchar next_counter = current_counter + 1;
    
    uint next_depth = comparison_depth | next_counter;
    bool atomic_succeeded = atomic_compare_exchange_weak_explicit(
      depth_ptr, &current_depth, next_depth,
      memory_order_relaxed, memory_order_relaxed);
    if (!atomic_succeeded) {
      // If there's a data race, the atomic cmpxchg fails.
      num_data_races_1 += 1;
      continue;
    }
    
    // Although we could pack two 16-bit counters into one word, that
    // creates a theoretical possibility to overflow the lower half, leaking
    // into the upper half. A thread accessing the upper half would be
    // thrown into an infinite loop because the 16-bit counter is always 1
    // ahead of the lock's 8-bit counter.
    //
    // Since it's 32-bit instead, we could store the lock and count
    // contiguously in memory. That decreases bandwidth utilization in the
    // texture reconstruction pass, so it's not a good idea.
    device atomic_uint* count_ptr = countBuffer + index;
    uint current_count = atomic_fetch_add_explicit(
      count_ptr, 1, memory_order_relaxed);
    if ((current_count & 255) != current_counter) {
      // If there's a data race, the counter isn't what you expect.
      num_data_races_2 += 1;
      continue;
    }
    
    // Exit the loop with a success.
    output = ushort(current_count + 1);
    break;
  }
  
  if (num_data_races_1 > 0) {
    dataRaces.recordEvent(1, num_data_races_1);
  }
  if (num_data_races_2 > 0) {
    dataRaces.recordEvent(2, num_data_races_2);
  }
  
  return output;
}

// From https://github.com/philipturner/metal-float64
// Permalink https://github.com/philipturner/metal-float64/blob/4d09870419793ce49990c0ff989ddd8e4a8c6e0e/Sources/MetalAtomic64/src/Atomic.metal#L1-L253

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

static constant size_t lock_buffer_address [[function_constant(0)]];

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
INTERNAL_INLINE device atomic_uint* get_upper_address(
  device atomic_uint* lower
) {
  DeviceAddressWrapper wrapper{ lower };
  auto lower_bits = reinterpret_cast<thread uint2&>(wrapper);
  uint2 upper_bits{ lower_bits[0] | 4, lower_bits[1] };
  return reinterpret_cast<thread DeviceAddressWrapper&>(upper_bits).address;
}

// Only call this while holding a lock.
INTERNAL_INLINE ulong memory_load(
  device atomic_uint* lower, device atomic_uint* upper
) {
  uint out_lo = metal::atomic_load_explicit(lower, memory_order_relaxed);
  uint out_hi = metal::atomic_load_explicit(upper, memory_order_relaxed);
  return as_type<ulong>(uint2(out_lo, out_hi));
}

// Only call this while holding a lock.
INTERNAL_INLINE void memory_store(
  device atomic_uint *lower, device atomic_uint* upper, ulong desired
) {
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


EXPORT ulong __metal_atomic64_fetch_max_explicit(
  device ulong* object, ulong operand
) {
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
        output = max(previous, operand);
        memory_store(lower_address, upper_address, output);
        release_lock(lock);
        done = true;
      }
    }
    done_active = simd_ballot(done);
  }
  return output;
}
