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
    uint depth;
};

constant uint testMode [[function_constant(0)]];

// Lock buffer and out buffer must be initialized to zero.
kernel void atomicsTest(constant uint &writesPerThread [[buffer(0)]],
                        device RandomData *randomData [[buffer(1)]],
                        device atomic_uint *lockBuffer [[buffer(2)]],
                        device ulong *outBuffer [[buffer(3)]],
                        texture2d<uint, access::read_write> outTexture [[texture(0)]],
                        uint tid [[thread_position_in_grid]])
{
    uint startIndex = tid * writesPerThread;
    uint endIndex = startIndex + writesPerThread;
    
    for (uint i = startIndex; i < endIndex; ++i)
    {
        auto currentData = randomData[i];
        uint pixelMask = as_type<uint>(currentData.pixel);
        uint depth = currentData.depth;
        ulong currentValue64 = as_type<ulong>(uint2(pixelMask, depth));
        
        if (testMode == 0)
        {
            uint2 coords{ currentData.xCoord, currentData.yCoord };
            uint2 readValue = outTexture.read(coords).xy;
            ulong readValue64 = as_type<ulong>(readValue);
            
            if (readValue64 < currentValue64)
            {
                outTexture.write(uint4{ pixelMask, depth }, coords);
            }
        }
        if (testMode == 1)
        {
            uint index = currentData.yCoord * outTexture.get_width() + currentData.xCoord;
            uint prevDepth = atomic_fetch_max_explicit(
                lockBuffer + index, currentData.depth, memory_order_relaxed);
            
            if (currentData.depth > prevDepth)
            {
                uint2 coords{ currentData.xCoord, currentData.yCoord };
                outTexture.write(uint4{ pixelMask, depth }, coords);
            }
        }
        if (testMode == 2)
        {
            uint index = currentData.yCoord * outTexture.get_width() + currentData.xCoord;
            auto object = reinterpret_cast<device atomic_uint*>(outBuffer + index);
            uint prevDepth = atomic_fetch_max_explicit(
                object + 1, currentData.depth, memory_order_relaxed);
            
            if (currentData.depth > prevDepth)
            {
                reinterpret_cast<device float*>(object)[0] = currentData.pixel;
            }
        }
    }
}
