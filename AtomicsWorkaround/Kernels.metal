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
    uint textureWidth;
};

struct RandomData {
    uint xCoord;
    uint yCoord;
    float color;
    float depth;
};

// Keeps track of every time a certain data race happens.
class DataRaces {
    device atomic_uint *atomics;
    
public:
    DataRaces(device atomic_uint *atomics) {
        this->atomics = atomics;
    }
    
    void recordEvent(int code) {
        atomic_fetch_add_explicit(atomics + code, 1, memory_order_relaxed);
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
kernel void atomicsTest(constant DispatchParams &params [[buffer(0)]],
                        device RandomData *randomData [[buffer(1)]],
						device atomic_uint *depthBuffer [[buffer(2)]],
						device atomic_uint *countBuffer [[buffer(3)]],
                        device atomic_uint *outBuffer [[buffer(4)]],
                        device atomic_uint *data_races [[buffer(5)]],
                        uint tid [[thread_position_in_grid]])
{
    static_assert(sizeof(RandomData) == 16, "Size not expected.");
    uint startIndex = tid * params.writesPerThread;
    uint endIndex = startIndex + params.writesPerThread;
    DataRaces dataRaces(data_races);
    
    for (uint i = startIndex; i < endIndex; ++i)
    {
        auto data = randomData[i];
        uint index = data.yCoord * params.textureWidth + data.xCoord;
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

// Thread dispatch size must equal texture dimensions.
kernel void reconstructTexture(device uint *depthBuffer [[buffer(2)]],
                               device uint2 *outBuffer [[buffer(4)]],
                               texture2d<uint, access::read_write> outTexture [[texture(0)]],
                               uint2 tid [[thread_position_in_grid]])
{
    uint index = tid.y * outTexture.get_width() + tid.x;
    
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
            depth_ptr, &current_depth, next_depth, memory_order_relaxed, memory_order_relaxed);
        if (!atomic_succeeded) {
            // If there's a data race, the atomic cmpxchg fails.
            num_data_races_1 += 1;
            continue;
        }
        
        // Each word contains 2 atomic counts.
        device atomic_uint *word_ptr = countBuffer + (index / 2);
        uint increment = 1;
        if (index & 1) {
            increment = 1 << 16;
        }
        uint previous_word = atomic_fetch_add_explicit(word_ptr, increment, memory_order_relaxed);
        if (index & 1) {
            previous_word >>= 16;
        }
        
        if ((previous_word & 255) != current_counter) {
            // If there's a data race, the counter isn't what you expect.
            num_data_races_2 += 1;
            continue;
        }
        
        // Exit the loop with a success.
        output = previous_word + 1;
        break;
    }
    
    if (num_data_races_1 > 0) {
        dataRaces.recordEvent(1);
    }
    if (num_data_races_2 > 0) {
        dataRaces.recordEvent(2);
    }
    
    return output;
}
