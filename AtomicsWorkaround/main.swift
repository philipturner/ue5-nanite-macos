//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Metal

// A buffer-backed texture must have rows aligned to 16 bytes. If the texture
// has odd width, and outBuffer/outTexture share the same underlying allocation,
// the runtime throws an error.
//
// Instead, use a common buffer to sub-allocate depthBuffer and counterBuffer,
// recycling the memory for outTexture. This creates a working set of memory
// that's (2 * numPixels) bytes larger during the Nanite pass. However, using
// the same storage mechanism for odd and even textures makes the codebase more
// maintainable.
let textureWidth = 3
let textureHeight = 3
let numIterationsPerKernelInvocation = 20
let numKernelInvocations = 10

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
let function = library.makeFunction(name: "atomicsTest")!
let pipeline = try! device.makeComputePipelineState(function: function)

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
let depthBufferSize = 4 * textureWidth * textureHeight
let countBufferSize = 2 * textureWidth * textureHeight
let outBufferSize = 8 * textureWidth * textureHeight

var outTextureRowWidth = 8 * textureWidth
outTextureRowWidth = ~15 & (15 + outTextureRowWidth)
let outTextureSize = outTextureRowWidth * textureHeight

// Determine size and internal offsets of recycled buffer.
precondition(depthBufferSize + countBufferSize <= outTextureSize)
let recycledBufferSize = outTextureSize
let depthBufferOffset = 0
let countBufferOffset = depthBufferOffset + depthBufferSize

func makeBuffer(size: Int) -> MTLBuffer {
    device.makeBuffer(length: size, options: bufferOptions)!
}

// Generate buffers.
let recycledBuffer = makeBuffer(size: recycledBufferSize)
let outBuffer = makeBuffer(size: outBufferSize)

let textureDesc = MTLTextureDescriptor()
textureDesc.width = textureWidth
textureDesc.height = textureHeight
textureDesc.pixelFormat = .rg32Uint
textureDesc.resourceOptions = bufferOptions
textureDesc.textureType = .type2D
textureDesc.usage = [.shaderRead, .shaderWrite]

// Generate out texture.
let outTexture = recycledBuffer.makeTexture(
    descriptor: textureDesc, offset: 0, bytesPerRow: outTextureRowWidth)!

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

func linearInterpolate(min: Float, max: Float, t: Float) -> Float {
    max * t + min * (1 - t)
}

func generateRandomData() -> [RandomData] {
    var output = [RandomData](repeating: .init(), count: randomDataNumElements)
    for i in 0..<randomDataNumElements {
        let randomValues = SIMD4<UInt32>.random(in: 0..<UInt32.max)
        var data = unsafeBitCast(randomValues, to: RandomData.self)
        
        // Clamp texture coordinates to something within the texture's bounds.
        data.xCoord %= UInt32(textureWidth)
        data.yCoord %= UInt32(textureHeight)
        
        // Clamp the pixel to [0, 1].
        let color_uint = data.color.bitPattern
        data.color = Float(color_uint) / Float(UInt32.max)
        
        // Test what happens when depth values are outside [0, 1].
        let depth_uint = data.color.bitPattern
        data.depth = Float(depth_uint) / Float(UInt32.max)
        data.depth = linearInterpolate(min: -0.1, max: 1.1, t: data.depth)
        
        output[i] = data
    }
    return output
}

// MARK: - Perform Tests

// Test Structure:
// (1) Generate random data, zero-initialize buffers
// (2) Encode commands on GPU
// (3) While waiting on GPU to finish, calculate what should happen on the CPU.
// (4) Ensure the CPU's results match every GPU result
