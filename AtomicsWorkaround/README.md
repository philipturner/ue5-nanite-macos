# Atomics Workaround

This thread-safe workaround enables Nanite on any platform with 32-bit buffer atomics. It requires neither image atomics nor 64-bit atomics. The test script creates a heavily congested environment where 100 different threads compete to access pixels in a 2x2 texture. Each thread has 20 different random values to write. Finally, results are checked against a CPU reference implementation.

With the script's current configuration, around 150 data races occur for each shader dispatch. All data races occur during this series of events:

- A thread loads a lock's 32-bit value.
- The thread increments the value's 8-bit counter.
- The thread updates the value's 24-bit depth.
- The thread compare-exchanges the lock's new value with its previous value.

I tested this on an Apple M1 Max, and you may get slightly different results on other GPUs. The script has a special execution path for Intel Macs with discrete GPUs, ensuring it uses GPU-private memory to store buffer data. Not doing this would tank performance and drastically alter how atomics work.

## Tested Devices

| GPU | Original Nanite Workaround | [MetalFloat64](https://github.com/philipturner/metal-float64) Approach | Metal `ULONG_MIN_MAX` |
| --- | ----- | ---- | ---- |
| AMD GCN 4 | ✅ | n/a | ❌ |
| M1 Max | ✅ | ❌\* | ❌ |
| A15 | ✅ | n/a | ❌ |
| A16 | ✅ | n/a | ❌ |
| M2 Max | ✅ | n/a | ✅ |

> \* Currently failing due to a software bug. I probably won't have time to fix it in the near future.

## Usage

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.

<s>The script has a variable for testing 64-bit atomics on Apple 8 GPUs. You must execute it on a device running macOS 13 or iOS 16, or else it fails at runtime. Because of this limitation, I have not verified that the 64-bit atomic version works.

> My inference may have been wrong here. I now suspect that Apple 8 GPUs lack any hardware instruction for 64-bit atomics. Rather, Apple exposed one of AMD's many 64-bit atomic instructions, just so that Intel Macs could theoretically run Nanite. This explains why they silently added the feature to MSL, and never listed it in the Metal Feature Set Tables.</s>

Apple added hardware acceleration for Nanite to the M2 series of GPUs, but not to the entire Apple 8 family. Hopefully the A17 will gain support in the next series of chips. Proving existence of such support took significant effort, and I thank all the people who helped me by running tests.

![d01df8388fbab8ee24d81dcf058a6131a3d932f5_2_1380x910](https://user-images.githubusercontent.com/71743241/224036245-4e2783e1-c1bd-4300-adee-f33856e68030.jpeg)

> Screenshot taken on March 9, 2023. Configuration: 38-core M2 Max, macOS 13.2.1, Xcode 14.2. Courtesy of [@jelmer3000](https://github.com/jelmer3000).


