# Atomics Workaround Test

This is a workaround for 64-bit UInt64 atomic max on Apple7 GPUs. This GPU family include A14 and M1/Pro/Max/Ultra. Apple chips produced after these have native instructions for UInt64 atomic max, and don't require the workaround.

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.
