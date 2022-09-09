//
//  Kernels.metal
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

#include <metal_stdlib>
using namespace metal;

struct RandomData {
    uint xCoord;
    uint yCoord;
    float pixel;
    float depth;
};

// Must zero-initialize lock, count, out buffers beforehand.
kernel void atomicsTest(constant uint &writesPerThread [[buffer(0)]],
                        device RandomData *randomData [[buffer(1)]],
						device atomic_uint *depthBuffer [[buffer(2)]],
						device atomic_uint *countBuffer [[buffer(3)]],
                        device atomic_uint *outBuffer [[buffer(4)]],
                        texture2d<uint, access::read_write> outTexture [[texture(0)]],
                        uint tid [[thread_position_in_grid]])
{
    uint startIndex = tid * writesPerThread;
    uint endIndex = startIndex + writesPerThread;
    
    for (uint i = startIndex; i < endIndex; ++i)
    {
        auto data = randomData[i];
        
        // Represent depth as 24-bit normalized integer.
        constexpr uint MAX_DEPTH = (1 << 24) - 1;
        float clamped_depth = saturate(data.depth);
        uint depth = clamped_depth * float(MAX_DEPTH);
        
        // Compute buffer index from texture coordinates.
        uint index = data.yCoord * outTexture.get_width() + data.xCoord;
        bool succeeded = false;
        ushort counter;
        {
            // Masks the lower 8 bits with zeroes. This means it can't be
            // considered "larger" than another value with the same depth, but a
            // different lower 8 bits.
            uint comparison_depth = depth << 8;
            device atomic_uint* depth_ptr = depthBuffer + index;
            
            // Loop in a spin-lock until the atomic value has been accessed in
            // a sanitized way.
            while (true) {
                uint current_depth = atomic_load_explicit(depth_ptr, memory_order_relaxed);
                if (comparison_depth <= current_depth) {
                    break;
                }
                
                uchar current_counter(current_depth);
                uchar next_counter = current_counter + 1;
                
                uint next_depth = comparison_depth | next_counter;
                bool atomic_succeeded = atomic_compare_exchange_weak_explicit(
                    depth_ptr, &current_depth, next_depth, memory_order_relaxed, memory_order_relaxed);
                if (!atomic_succeeded) {
                    // If there's a data race, atomic cmpxchg fails.
                    continue;
                }
                
                // Each word contains 2 atomic counts.
                device atomic_uint *word_ptr = countBuffer + (index / 2);
                uint increment = (index & 1) << 16;
                uint previous_word = atomic_fetch_add_explicit(word_ptr, increment, memory_order_relaxed);
                if (index & 1) {
                    previous_word >>= 16;
                }
                
                // An overflow in the lower counter would leak into the upper
                // counter, making it always off by one. The check directly below
                // this would always fail for some random thread on the GPU, causing
                // an infinite loop.
                //
                // This workaround shrinks dynamic range from 65536 to 49152,
                // providing a 16384-pixel grace period to reset the counter.
                // This should never be exceeded in practice.
                //
                // After resetting the counter, it decreases to something close
                // to 0. That will cause a graphical glitch, but it's better
                // than freezing the application. Furthermore, there's an almost
                // zero possibility that 49152 triangles will have a unique
                // depth value and all test the same pixel in ascending order.
                bool is_lower = (index & 1) == 0;
                constexpr ushort MAX_COUNTER = (1 << 14) * 3;
                if (is_lower && (previous_word >= MAX_COUNTER)) {
                    // Always reset the counter, even if depths do not match.
                    constexpr uint RESET_MASK = 0xFFFF00FF;
                    atomic_fetch_and_explicit(word_ptr, RESET_MASK, memory_order_relaxed);
                }
                
                if ((previous_word & 255) != current_depth) {
                    // If there's a data race, atomic count isn't what you expect.
                    continue;
                }
                
                // Exit the loop with a success.
                succeeded = true;
                counter = previous_word + 1;
                break;
            }
        }
        
    }
}
