//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Metal

let textureWidth = 2
let textureHeight = 2

#if os(macOS)
// A buffer-backed texture must have rows aligned to 16 bytes. Accomplish this
// by setting stride to an even number of 8-bit elements. Align depth/count
// buffers to this stride, so that one index can address into all buffers.
let textureRowStride = ~1 & (1 + textureWidth)
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
let numKernelInvocations = 100
let numTests = 5

// Whether to test 64-bit atomics on an A15 or M2 GPU.
let emulating64BitAtomics: Bool = false
let atomicsPipelineName = emulating64BitAtomics ? "atomicsTestApple8" : "atomicsTest"

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
let atomicsTestPipeline = try! device.makeComputePipelineState(
	function: library.makeFunction(name: atomicsPipelineName)!)
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
            if !emulating64BitAtomics {
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
	if !emulating64BitAtomics {
		computeEncoder.setBuffer(depthBuffer, offset: 0, index: 2)
		computeEncoder.setBuffer(countBuffer, offset: 0, index: 3)
		computeEncoder.setBuffer(dataRacesBuffer, offset: 0, index: 5)
	}
    do {
        let gridSize = MTLSizeMake(numKernelInvocations, 1, 1)
        let threadgroupSize = MTLSizeMake(1, 1, 1)
        computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
    }
    
	if !emulating64BitAtomics {
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
