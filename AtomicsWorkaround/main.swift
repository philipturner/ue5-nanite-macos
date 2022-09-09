//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Metal

// A buffer-backed texture have rows aligned to 16 bytes. If texture has odd
// width, and outBuffer/outTexture share the same underlying allocation, the
// runtime throws an error.
//
// So, use a common buffer to sub-allocate depthBuffer and counterBuffer, and
// recycle the memory for outTexture. This creates a working set of memory
// that's (2 * numPixels) byte larger than the other implementation. However,
// using the same mode for odd and even textures makes the code base more
// maintainable.
let textureWidth = 3
let textureHeight = 3
let numTrials = 3
let numIterationsPerKernelInvocation = 20
let numKernelInvocations = 10

// Loop:
// (1) Generate random data, zero-initialize buffers
// (2) Encode commands on GPU, repeated several times because it might be
//     non-deterministic
// (3) While waiting on GPU to finish, calculate what should happen on the CPU.
// (4) Ensure the CPU's results match every GPU result

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
let function = library.makeFunction(name: "atomicsTest")!
let pipeline = try! device.makeComputePipelineState(function: function)

struct RandomData {
    var xCoord: UInt32 = 0
    var yCoord: UInt32 = 0
    var color: Float = 0
    var depth: Float = 0
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

let randomDataNumElements = numIterationsPerKernelInvocation * numKernelInvocations
let randomDataSize = randomDataNumElements * MemoryLayout<RandomData>.stride
let randomDataBuffer = device.makeBuffer(length: randomDataSize, options: bufferOptions)!

let numPixels = textureWidth * textureHeight
let depthBufferSize = 4 * numPixels
let countBufferSize = 2 * numPixels
let outBufferSize = 8 * numPixels

var depthBuffers: [MTLBuffer] = []
var countBuffers: [MTLBuffer] = []
var outBuffers: [MTLBuffer] = []
var outTextures: [MTLTexture] = []

for _ in 0..<numTrials {
    func makeBuffer(size: Int) -> MTLBuffer {
        device.makeBuffer(length: size, options: bufferOptions)!
    }
    
    depthBuffers.append(makeBuffer(size: depthBufferSize))
    countBuffers.append(makeBuffer(size: countBufferSize))
    
    let outBuffer = makeBuffer(size: outBufferSize)
    depthBuffers.append(outBuffer)
    
    let desc = MTLTextureDescriptor()
    desc.width = textureWidth
    desc.height = textureHeight
    desc.pixelFormat = .rg32Uint
    desc.resourceOptions = bufferOptions
    desc.textureType = .type2D
    desc.usage = [.shaderRead, .shaderWrite]
    
    let bytesPerRow = 2 * MemoryLayout<UInt32>.stride * textureWidth
    let outTexture = outBuffer.makeTexture(
        descriptor: desc, offset: 0, bytesPerRow: bytesPerRow)!
    outTextures.append(outTexture)
}

// MARK: - Perform Tests

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
