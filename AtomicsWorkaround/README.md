# Atomics Workaround Test

This thread-safe workaround enables Nanite on any platform with 32-bit buffer atomics. It requires neither image atomics nor 64-bit atomics. The test script creates a heavily congested environment where 100 different threads compete to access pixels in a 2x2 texture. Each thread has 20 different random values to write. Finally, results are checked against a CPU reference implementation.

With the parameters currently present in the script, around 100 "type 1" data races occur for each shader dispatch. There are data races where (explain).

## Usage

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.
