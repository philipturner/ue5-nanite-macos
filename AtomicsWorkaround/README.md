# Atomics Workaround Test

This thread-safe workaround enables Nanite on any platform with 32-bit buffer atomics. It requires neither image atomics nor 64-bit atomics. The test script creates a heavily congested environment where 100 different threads compete to access pixels in a 2x2 texture. Each thread has 20 different random values to write. Finally, results are checked against a CPU reference implementation.

With the script's current configuration, around 100 data races occur for each shader dispatch. All data races occur during this series of events:

- A thread loads a lock's 32-bit value.
- The thread increments the value's 8-bit counter.
- The thread updates the value's 24-bit depth.
- The thread compare-exchanges the lock's new value with its previous value.

I tested this on an Apple M1 Max, and you may get slightly different results on other GPUs. The script has a special execution path for Intel Macs with discrete GPUs, ensuring it uses GPU-private memory to store buffer data. Not doing this would tank performance and drastically change how atomics work.

## Usage

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.
