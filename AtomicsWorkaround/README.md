# Atomics Workaround Test

This thread-safe workaround enables Nanite on any platform with 32-bit buffer atomics. It requires neither image atomics nor 64-bit atomics.

> This directory is a work in progress. Both source code files are a work in progress.

Create a new Xcode project with the template <b>macOS > Command Line Tool</b>. Replace the Swift file with `main.swift` from this repository. Then, copy the Metal shader file into the project. Click <b>Menu Bar > Product > Run</b> to execute the test.
