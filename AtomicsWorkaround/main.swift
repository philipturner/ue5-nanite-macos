//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Metal

let numIterationsPerShader = 20
let textureSize = 3
let numIterationsPerDataset = 3

// Loop:
// (1) Generate random data, zero-initialize buffers
// (2) Encode commands on GPU, repeated several times because it might be
//     non-deterministic
// (3) While waiting on GPU to finish, calculate what should happen on the CPU.
//     You can also generate the next set of random data while waiting on the GPU.
// (4) Compare the CPU's results to every GPU result
// (5) Show the number of slots that didn't match for each iteration
//
// Recommendation:
// Compile this Xcode project in release mode so the CPU can determine results
// as quickly as possible. Also, disable Metal API validation.

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let library = device.makeDefaultLibrary()!
var pipelines: [MTLComputePipelineState] = []

for i in 0..<UInt32(3) {
    let constants = MTLFunctionConstantValues()
    var value = i
    constants.setConstantValue(&value, type: .uint, index: 0)
    
    let function = try! library.makeFunction(name: "atomicsTest", constantValues: constants)
    let pipeline = try! device.makeComputePipelineState(function: function)
    pipelines.append(pipeline)
}

struct RandomData {
    var xCoord: UInt32
    var yCoord: UInt32
    var pixel: Float
    var depth: UInt32
};

let numDatasetElements = numIterationsPerShader * textureSize * textureSize
let datasetMemSize = numDatasetElements * 16
let datasetBuffer = device.makeBuffer(length: datasetMemSize, options: .storageModeManaged)!

var lockBuffers: [MTLBuffer] = []
var outBuffers: [MTLBuffer] = []
var outTextures: [MTLTexture] = []
for i in 0..<numIterationsPerDataset {
    let lockBufferSize = textureSize * textureSize * 4
    let outBufferSize = textureSize * textureSize * 8
}

// Don't forget to free this pointer.
func generateRandomData() -> UnsafeMutableRawPointer {
    let pointer = malloc(datasetMemSize)!
    let casted = pointer.assumingMemoryBound(to: RandomData.self)
    
    for i in 0..<numDatasetElements {
        let randomValues = SIMD4<UInt32>.random(in: 0..<UInt32.max)
        let depthMask = UInt32(1 << 24) - 1 // Limit to 24 bits of precision.
        
        let data = RandomData(
            xCoord: randomValues[0] % UInt32(textureSize),
            yCoord: randomValues[1] % UInt32(textureSize),
            pixel: Float(randomValues[2]) / Float(UInt32.max),
            depth: randomValues[3] & depthMask)
    }
    fatalError()
}
