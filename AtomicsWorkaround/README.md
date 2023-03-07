# Atomics Workaround

This thread-safe workaround enables Nanite on any platform with 32-bit buffer atomics. It requires neither image atomics nor 64-bit atomics. The test script creates a heavily congested environment where 100 different threads compete to access pixels in a 2x2 texture. Each thread has 20 different random values to write. Finally, results are checked against a CPU reference implementation.

With the script's current configuration, around 150 data races occur for each shader dispatch. All data races occur during this series of events:

- A thread loads a lock's 32-bit value.
- The thread increments the value's 8-bit counter.
- The thread updates the value's 24-bit depth.
- The thread compare-exchanges the lock's new value with its previous value.

I tested this on an Apple M1 Max, and you may get slightly different results on other GPUs. The script has a special execution path for Intel Macs with discrete GPUs, ensuring it uses GPU-private memory to store buffer data. Not doing this would tank performance and drastically alter how atomics work.

## Tested Devices

| GPU | Original Nanite Workaround | MetalFloat64 Approach | Metal `ULONG_MIN_MAX` |
| --- | ----- | ---- | ---- |
| AMD GCN 5 | ✅ | n/a | ❌ |
| M1 Max | ✅ | ❌\* | ❌ |
| A15 | ✅ | n/a | ❌ |
| A16 | ✅ | n/a | ❌ |

> \* Currently failing due to a software bug. I probably won't have time to fix it in the near future.

## Usage

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.

The script has a variable for testing 64-bit atomics on Apple 8 GPUs. You must execute it on a device running macOS 13 or iOS 16, or else it fails at runtime. Because of this limitation, I have not verified that the 64-bit atomic version works.

> My inference may have been wrong here. I now suspect that Apple 8 GPUs lack any hardware instruction for 64-bit atomics. Rather, Apple exposed one of AMD's many 64-bit atomic instructions, just so that Intel Macs could theoretically run Nanite. This explains why they silently added the feature to MSL, and never listed it in the Metal Feature Set Tables.
