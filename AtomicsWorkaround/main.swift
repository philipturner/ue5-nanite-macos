//
//  main.swift
//  AtomicsWorkaround
//
//  Created by Philip Turner on 9/5/22.
//

import Foundation

print("Hello, World!")

// Loop:
// (1) Generate random data
// (2) Encode commands on GPU, repeated several times because it might be
//     non-deterministic
// (3) While waiting on GPU to finish, calculate what should happen on the CPU
// (4) Compare the CPU's results to every GPU result
// (5) Show the number of slots that didn't match for each iteration
