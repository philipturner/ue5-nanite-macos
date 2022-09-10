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
let textureWidth = 2
let textureHeight = 2

// High ratio of (numIterationsPerKernelInvocation * numKernelInvocations) /
// (textureWidth * textureHeight) creates heavy congestion, and likely many data
// races.
//
// If the ratio > 256, you can test what happens when the lower 8 bits of a
// depth lock wrap around to 0.
let numIterationsPerKernelInvocation = 20
let numKernelInvocations = 100
let numTests = 5

// Right now, this flag doesn't do anything. In the future, it will enable
// testing 64-bit atomics on the A15 GPU.
let emulating64BitAtomics: Bool = false
let enableDebugMode = false

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
let atomicsTestPipeline = try! device.makeComputePipelineState(
    function: library.makeFunction(name: "atomicsTest")!)
let reconstructTexturePipeline = try! device.makeComputePipelineState(
    function: library.makeFunction(name: "reconstructTexture")!)

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

// Generate buffers for debugging and profiling.
let __debug_depthBuffer = makeBuffer(size: depthBufferSize)
let __debug_countBuffer = makeBuffer(size: countBufferSize)
let dataRacesBuffer = makeBuffer(size: 4 * 64) // Up to 64 unique error codes.

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
precondition(MemoryLayout<RandomData>.stride == 16)

// Create buffer for input data.
let randomDataNumElements = numIterationsPerKernelInvocation * numKernelInvocations
let randomDataSize = randomDataNumElements * MemoryLayout<RandomData>.stride
let randomDataBuffer = device.makeBuffer(length: randomDataSize, options: bufferOptions)!

func linearInterpolate(min: Float, max: Float, t: Float) -> Float {
    max * t + min * (1 - t)
}

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
        
        // Test what happens when depth values are outside [0, 1].
        data.depth = Float(data.depth.bitPattern) / Float(UInt32.max)
//        data.depth = linearInterpolate(min: -0.1, max: 1.1, t: data.depth)
        
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
        if !emulating64BitAtomics {
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
    ptr: UnsafeMutableRawPointer,
    expected: [[SIMD2<Float>]]
) -> (colorDeviation: Float, depthDeviation: Float) {
    var deviation: SIMD2<Float> = .zero
    for row in 0..<outTexture.height {
        let basePtr = ptr + row * outTextureRowWidth
        let actualPixels = basePtr.assumingMemoryBound(to: SIMD2<Float>.self)
        let expectedPixels = expected[row]
        
        for i in 0..<outTexture.width {
            let actual = actualPixels[i]
            var expected = expectedPixels[i]
            if !emulating64BitAtomics {
                let maxDepth: Int = (1 << 24) - 1
                let clampedDepth: UInt32 = expected.y.bitPattern
                let depth = Float(clampedDepth) / Float(maxDepth + 1)
                expected.y = depth
            }
            
            if enableDebugMode {
                print("(actual) \(showBits(actual.x)) \(showBits(actual.y)) (expected) \(showBits(expected.x)) \(showBits(expected.y))")
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
    }
    
    // Generate random data.
    var randomDataPtr: UnsafeMutablePointer<RandomData>
    do {
        let contents = randomDataBuffer.contents()
        randomDataPtr = contents.assumingMemoryBound(to: RandomData.self)
        generateRandomData(ptr: randomDataPtr)
        #if os(macOS)
        randomDataBuffer.didModifyRange(0..<randomDataBuffer.length)
        #endif
    }
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    
    // Zero out all buffers.
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.fill(buffer: recycledBuffer, range: 0..<recycledBuffer.length, value: 0)
    blitEncoder.fill(buffer: outBuffer, range: 0..<outBuffer.length, value: 0)
    if enableDebugMode {
        blitEncoder.fill(buffer: __debug_depthBuffer, range: 0..<__debug_depthBuffer.length, value: 0)
        blitEncoder.fill(buffer: __debug_countBuffer, range: 0..<__debug_countBuffer.length, value: 0)
    }
    blitEncoder.fill(buffer: dataRacesBuffer, range: 0..<dataRacesBuffer.length, value: 0)
    blitEncoder.endEncoding()
    
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    computeEncoder.setComputePipelineState(atomicsTestPipeline)
    
    struct DispatchParams {
        var writesPerThread: UInt32 = 0
        var textureWidth: UInt32 = 0
    }
    
    // Set dispatch parameters.
    var params = DispatchParams()
    params.writesPerThread = .init(numIterationsPerKernelInvocation)
    params.textureWidth = .init(outTexture.width)
    let paramsLength = MemoryLayout<DispatchParams>.stride
    computeEncoder.setBytes(&params, length: paramsLength, index: 0)
    
    computeEncoder.setBuffer(randomDataBuffer, offset: 0, index: 1)
    if enableDebugMode {
        computeEncoder.setBuffer(__debug_depthBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(__debug_countBuffer, offset: 0, index: 3)
    } else {
        computeEncoder.setBuffer(recycledBuffer, offset: depthBufferOffset, index: 2)
        computeEncoder.setBuffer(recycledBuffer, offset: countBufferOffset, index: 3)
    }
    computeEncoder.setBuffer(outBuffer, offset: 0, index: 4)
    computeEncoder.setBuffer(dataRacesBuffer, offset: 0, index: 5)
    do {
        let gridSize = MTLSizeMake(numKernelInvocations, 1, 1)
        let threadgroupSize = MTLSizeMake(1, 1, 1)
        computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
    }
    
    computeEncoder.setComputePipelineState(reconstructTexturePipeline)
    
    // depthBuffer already bound to index 2.
    // outBuffer already bound to index 4.
    computeEncoder.setTexture(outTexture, index: 0)
    do {
        let gridSize = MTLSizeMake(outTexture.width, outTexture.height, 1)
        let threadgroupSize = MTLSizeMake(1, 1, 1)
        computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
    }
    
    computeEncoder.endEncoding()
    commandBuffer.commit()
    
    // Compute results on CPU while waiting for GPU.
    let results = generateExpectedResults(ptr: randomDataPtr)
    commandBuffer.waitUntilCompleted()
    
    // Validate results.
    let deviation = validateResults(ptr: recycledBuffer.contents(), expected: results)
    print("Deviation: \(deviation)")
    
    let dataRacesContents = dataRacesBuffer.contents().assumingMemoryBound(to: UInt32.self)
    for i in 0..<64 {
        if dataRacesContents[i] > 0 {
            print("There were \(dataRacesContents[i]) data races with error code \(i).")
        }
    }
    print()
    
    guard enableDebugMode else {
        continue
    }
    
    for i in 0..<randomDataNumElements {
        let data = randomDataPtr[i]
        print("xCoord: \(data.xCoord), yCoord: \(data.yCoord), color: \(showBits(data.color)), depth: \(showBits(data.depth))")
    }
    
    print("Depth buffer:")
    let depthBufferContents = __debug_depthBuffer.contents().assumingMemoryBound(to: UInt32.self)
    for i in 0..<textureWidth * textureHeight {
        let depth = depthBufferContents[i]
        print("depth: \(showBits(depth))")
    }
    
    print("Count buffer:")
    let countBufferContents = __debug_countBuffer.contents().assumingMemoryBound(to: UInt16.self)
    for i in 0..<textureWidth * textureHeight {
        let count = UInt32(countBufferContents[i])
        print("count: \(showBits(count))")
    }
    
    print("Out buffer:")
    let outBufferContents = outBuffer.contents().assumingMemoryBound(to: SIMD2<UInt32>.self)
    for i in 0..<textureWidth * textureHeight {
        let pixel = outBufferContents[i]
        print("lower part: \(showBits(pixel.x)), upper part: \(showBits(pixel.y))")
    }
    print()
}
