# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to Apple platforms. Read over [this forum thread](https://forums.unrealengine.com/t/lumen-nanite-on-macos/508411) for more context.

## Usage

Thorough instructions for how to compile UE5 from source and replicate what I've done:

<details>
<summary>Prerequisites</summary>

---

- At least 200 GB of free disk space, after installing everything described below.
- Install [Homebrew](https://brew.sh).
- Install Git. This can be accomplished using Homebrew: `brew install git`.
- Install Xcode 14 beta from [developer.apple.com](https://developer.apple.com/xcode/resources). Place the unzipped `Xcode-beta` app in `~/Applications`.
- [Create](https://www.epicgames.com/id/register) an Epic Games account and [link](https://www.epicgames.com/help/en-US/epic-accounts-c5719348850459/connect-accounts-c5719351300507/how-do-i-link-my-unreal-engine-account-with-my-github-account-a5720369784347) it to your GitHub account.

> <sup>1</sup>Xcode 14 should be released in September 2022. When it is no longer in beta, Xcode from the Mac App Store will work.

Perform the following in a new Terminal window, then close the window. This ensures\* that UnrealBuildTool uses Xcode beta instead of regular Xcode.

```
>>> sudo xcode-select --switch ~/Applications/Xcode-beta.app
[Prompt to enter password]
>>> swift --version
[Swift 5.7 should appear in the output]
```

> \*I'm not 100% sure this is necessary, but it's better to play it safe.

</details>
<details>
<summary>Sign in and download 'EpicGames/UnrealEngine'</summary>

---

Launch the `Xcode-beta` app and go to <b>Menu Bar > Xcode > Preferences > Accounts</b>. Click the "+" button on the bottom left, then select the "GitHub" account type. A popup prompts you for a GitHub [access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). Generate one with the scopes listed below. <ins>Do not</ins> close the browser window showing that token's letters/digits until you've cloned the UE5 repository.

- admin:public_key
- write:discussion
- repo
- user

Enter your GitHub account username and the access token. Click "Sign In", then quit and restart Xcode beta. Create a folder called `UnrealEngine` in `~/Documents`. Right-click it in Finder and click "New Terminal at Folder". Enter these commands into the new Terminal window:

```
>>> pwd
/Users/<your username>/Documents/UnrealEngine
>>> git clone --single-branch -b ue5-main https://github.com/EpicGames/UnrealEngine
```

While cloning the UE5 repository, it may ask for your credentials. Enter the access token from above instead of your account password. The download takes over 10 minutes with average internet speeds, so `git clone` has flags that minimize the amount of downloaded commits.

</details>
<details>
<summary>Compile unmodified 'ue5-main'</summary>

---

On [this guide](https://docs.unrealengine.com/5.0/en-US/downloading-unreal-engine-source-code), follow steps 3 and 4 of "Downloading the Source Code". Right-click `UE5.xcworkspace` and select <b>Open With > Xcode-beta</b>. The instructions below are adapted from [another guide](https://docs.unrealengine.com/5.0/en-US/building-unreal-engine-from-source), which is slightly outdated; no `UE4Editor` or `UE5Editor` scheme exists. Do not run through the latter guide.

Click <b>Menu Bar > Product > Build</b>. The command fails\* because an `Info.plist` is not generated. In the project navigator, select <b>Engine > UE5</b>. Click the <b>Build Settings</b> tab, then look at <b>PROJECT</b> on the left. Select <b>UE5</b>, which has a blue App Store icon next to it. In the build settings search bar, type "generate info". Only one setting pops up: "Generate Info.plist File". Change its value from "No" to "Yes". Repeat these steps for <b>Build Settings > TARGETS > UE5</b>.

> \*This failure only happens on Xcode 14 beta. You must repeat this workaround for all Unreal C++ projects, going through <b>Games > ProjectName > Build Settings</b> instead.

Click <b>Menu Bar > Product > Build</b>. Compilation should take on the order of 10 - 30 minutes. Open the `Activity Monitor` application, and 8-10 `clang` processes\* should create ~100% CPU load\** after the build starts. If they max out at ~50% CPU load, something is going wrong.

> \*Sort by <b>% CPU</b> in descending order to see the `clang` processes.
>
> \**Refer to the graph at the bottom of the window for CPU load, <ins>not</ins> the number(s) below <b>% CPU</b>.

Click <b>Menu Bar > Product > Run</b>. Give Unreal Editor permission to access `Documents`. The application shuts down\* after accessing a nonexistent `YES/YES.uproject`; check the Xcode console to validate that the failure happens. Now, navigate to this path in Finder and double-click the `UnrealEditor` application:

```
/Users/<your username>/Documents/UnrealEngine/UnrealEngine/Engine/Binaries/Mac
```

> \*This failure happens on both Xcode 13 (from the Mac App Store) and Xcode 14 beta.

After some time, the "Unreal Project Browser" window appears.

</details>
<details>
<summary>Fork 'EpicGames/UnrealEngine'</summary>

---

> Throughout this section, `<username>` refers to your GitHub username.

On the GitHub website, fork [`EpicGames/UnrealEngine`](https://github.com/EpicGames/UnrealEngine). Check the box for cloning only the `release` branch; this minimizes the fork's size. Verify that a private repo exists at `https://github.com/<username>/UnrealEngine`.

In Finder, go to `~/Documents/UnrealEngine/UnrealEngine` and click "New Terminal at Folder". Enter these commands:

```
>>> git branch
* ue5-main
>>> git remote
origin
>>> git remote add <username> https://github.com/<username>/UnrealEngine
>>> git checkout -b modifications
>>> git add .
>>> git commit -m "Test Commit"
[modifications db644854a9] Test Commit
 2 files changed, 98 insertions(+)
 create mode 100644 Engine/Config/DefaultEngine.ini
 create mode 100644 Engine/Config/DefaultInput.ini
>>> git push <username> modifications
[Push should succeed]
```

Open your `modifications` branch on GitHub and view the commit history. Click the commit titled "Test Commit". It should add two new files to `Engine/Config`.

</details>
<details>
<summary>First Unreal Project</summary>

---

Open the Unreal Editor app from `Engine/Binaries/Mac` inside the UE5 source folder. Right-click it in Dock and select <b>Options > Keep in Dock</b>. This removes the need to search through Finder when launching the editor.

In the Unreal Project Browser, go to <b>GAMES > First Person > Project Defaults > C++</b>. Do not choose <b>BLUEPRINT</b>. Blueprint projects launch seamlessly with a custom UE5 build, but C++ projects require the troubleshooting detailed in this section. Set <b>Project Name</b> to `UnrealProject1` and click <b>Create</b>.

The Unreal Editor automatically quits, then opens an Xcode project titled `UnrealProject1`. Relaunch the Unreal Editor app go to <b>RECENT PROJECTS > UnrealProject1 > Open</b>. A popup says certain modules are missing; click <b>Yes</b> to rebuild them. A few seconds later, another popup says the modules cannot compile. Dismiss it and click on the Xcode window for UnrealProject1.

Click <b>Menu Bar > Product > Build</b>. The command fails just like when building UE5 from source. Scroll up to the section above that describes the workaround. Go through <b>Games > ProjectName > Build Settings</b> in the Xcode project navigator, instead of <b>Engine > UE5 > Build Settings</b>. The latter path does not affect this project and may cause Xcode to recompile UE5 from scratch.

Build the project again. It should succeed\*, taking only a minute. If it takes longer than 10 minutes, locate it in Finder (`~/Documents/Unreal Projects/UnrealProject1`) and validate that it is not rebuilding UE5 from scratch. Right-click the folder and select <b>Get Info</b>; its size should be on the order of 1 GB.

> \*Ignore the warning stating "Run script build phase 'Sign Manual Frameworks' will be run during every build".

Launch the Unreal Editor and open UnrealProject1. This time, the 3D graphical user interface should appear.
</details>
<details>
<summary>Revert to Xcode 13</summary>

---

On a local machine, I force-enabled [`NaniteAtomicsSupported()`](https://github.com/EpicGames/UnrealEngine/blob/07cf5345692d0c6ce80a748c001efea5eee16eb1/Engine/Source/Runtime/RenderCore/Public/RenderUtils.h#L713-L743) and the build system acted strangely. `XCBBuildService` crashed in the middle of every build, making UnrealBuildTool execute in the background. I could not track UnrealBuildTool's progress in Xcode to estimate when it would finish. The second time this happened, I noticed that Clang was still consuming 100% CPU and `XCBBuildService` had silently respawned in Activity Monitor. 
 
Disk space started getting eaten up and I could not find which folder was consuming increasingly more disk space. `~/Documents/UnrealEngine` stayed constant at 199 GB, while <b>Menu Bar >  > About This Mac > Storage</b> showed a gigabyte being consumed every ~10 seconds. I had to reboot my Mac, reset the `UnrealEngine` directory, and recompile with Xcode 13. Nanite doesn't require Metal 3 functionality, so Xcode 14 beta is not necessary.

To debug `UnrealEditor.app` when it crashes, you must launch it from Xcode. This requires a pre-existing project that the Unreal Editor can open by default. Open the unmodified Unreal Editor app from Dock, and the Unreal Project Browser appears. Go to <b>GAMES > First Person > Project Defaults > BLUEPRINT</b>. Using Blueprints instead of C++ prevents UnrealBuildTool from creating unwanted popups. Set the name to `YES` and click <b>Create</b>.
 
Copy the `YES` project folder from `~/Documents/Unreal Projects` to `~/Documents/UnrealEngine/UnrealEngine`. This lets Unreal Editor automatically detect it when launched from inside Xcode. Finally, open `UE5.xcworkspace` and select <b>Menu Bar > Product > Run</b>. Open the editor this way after incorporating the code changes described below.

</details>

<details>
<summary>Facing extremely long build times</summary>

---

UnrealBuildTool performs poorly with incremental builds of Unreal Engine, and each full recompilation takes about an hour with Xcode 13. I haven't validated whether it ran faster with Xcode 14 beta. I am trying to debug certain changes to the code because some results are unexpected. Here is a grid of all the combinations of conditions, along with the observed behavior.

- `NaniteAtomicsSupported()`: [RenderUtils.h](https://github.com/EpicGames/UnrealEngine/blob/07cf5345692d0c6ce80a748c001efea5eee16eb1/Engine/Source/Runtime/RenderCore/Public/RenderUtils.h#L713-L743)
- `GRHISupportsAtomicUInt64`: [RHI.cpp](https://github.com/EpicGames/UnrealEngine/blob/07cf5345692d0c6ce80a748c001efea5eee16eb1/Engine/Source/Runtime/RHI/Private/RHI.cpp#L1391)

|   | `GRHISupportsAtomicUInt64` is false | `GRHISupportsAtomicUInt64` is true |
| - | ----------------------------------- | ---------------------------------- |
| `NaniteAtomicsSupported()` left as-is | Runs smoothly with Nanite disabled. <ins>Build time: unknown</ins> | Observations unusable; `bSupportsNanite=true` was unset. <ins>Build time: 55 minutes</ins> (from scratch, 3600 actions, 8 processes) |
| `NaniteAtomicsSupported()` always returns true, only when `PLATFORM_APPLE` is defined | Crashes<sup>[1]</sup> after rendering anything. <ins>Build time: 44 minutes</ins> (using cached build products, 2400 actions, 10 processes) | |
| `NaniteAtomicsSupported()` always returns true; its original code is commented out | | Did not finish compilation. <ins>Build time: aborted</ins> |

<details>
<summary><sup>1</sup>Crash description</summary>

```
[UE] Assertion failed: GRHIPersistentThreadGroupCount > 0 [File:./Runtime/Renderer/Private/Nanite/NaniteCullRaster.cpp] [Line: 1738] 
GRHIPersistentThreadGroupCount must be configured correctly in the RHI.
```

</details>

I figured out the bug. I did not set `bSupportsNanite=true` in `DataDrivenPlatformInfo.ini`. After setting that, the editor crashes as expected. My next step is cleaning up the UnrealEngine fork. Heads up for anyone compiling my fork: Git corrupted the `YES/YES.uproject`. It's sufficient to launch Unreal Editor from within Xcode, but the scene is empty. Navigate to <b>Menu Bar > File</b> in the editor and open a different project.

Next, I tried forcing UE5 to perform unity builds. These supposedly decrease compile time but allow for mistakes where you forget an `#include` directive. Under `~/.config/Unreal Engine/UnrealBuildTool/BuildConfiguration.xml`, I set the following XML tags to `true`: "bUseUnityBuild", "bForceUnityBuild", and "bUseUBTMakefiles". There's no way to validate whether this hack works, but incremental builds seem to be running faster now.

</details>

## Modifications to UE5

[This link](https://github.com/philipturner/UnrealEngine/commits/modifications) shows my most recent modifications to Unreal Engine. Sign into your Epic Games-licensed GitHub account to view it. I also post raw source code in `ue5-nanite-macos`, explaining it below.

### Change 1

Look at `Sources/RenderUtils_Changes.cpp` in this repository. In UE source code, navigate to the path (1) below. Replace the body of `NaniteAtomicsSupported()` with my changes. At path (2), add `bSupportsNanite=true` underneath `[ShaderPlatform METAL_SM5]`. This only enables Nanite on macOS, not iOS or tvOS yet. The engine now crashes at runtime.

```
(1) Engine/Source/Runtime/RenderCore/Public/RenderUtils.h
(2) Engine/Config/Mac/DataDrivenPlatformInfo.ini
```

<details>
<summary>Crash description</summary>

```
[UE] Assertion failed: GRHIPersistentThreadGroupCount > 0 [File:./Runtime/Renderer/Private/Nanite/NaniteCullRaster.cpp] [Line: 1738] 
GRHIPersistentThreadGroupCount must be configured correctly in the RHI.
```

</details>

### Change 2

To fix the crash above, set the persistent thread group count for MetalRHI to 1440 - the same value as DirectX and Vulkan. Navigate to the path below and change `FMetalDynamicRHI::Init()` to the contents of `Sources/MetalRHI_Changes.cpp`. The engine now crashes because it cannot find `FInstanceCull_CS`. The GPU had a soft fault before UE crashed, so something is going very wrong.

```
Engine/Source/Runtime/Apple/MetalRHI/Private/MetalRHI.cpp
```

<details>
<summary>Crash description</summary>

```
GPU Soft Fault count: 1
2022-09-05 09:50:10.761740-0400 UnrealEditor[68890:538318] [UE] Assertion failed: Shader.IsValid() [File:Runtime/RenderCore/Public/GlobalShader.h] [Line: 201] 
Failed to find shader type FInstanceCull_CS in Platform SF_METAL_SM5
```

</details>

### Change 3

[UE5NanitePort](https://github.com/gladhu/UE5NanitePort) enabled Nanite through a special shader execution path on Apple platforms. The path replaced 32-bit texture atomics with thread-unsafe memory accesses. Depths might register incorrectly, causing hidden objects to appear in front of objects that occlude them. This may explain the graphical glitches in the associated Reddit post. Metal supports 32-bit buffer atomics, so a better solution replaces texture arguments with buffers. This takes more time to implement, but reduces/eliminates graphical glitches.
 
Since that port, Nanite was permantently disabled on platforms that lack 64-bit atomics. [This commit](https://github.com/EpicGames/UnrealEngine/commit/9b68f6b76686b3fabe1c8513efcf95dd74dea1c3#) removed the lock-based control path that enabled Nanite through 32-bit atomics. I added a new execution path that works around this removal, but does not add a lock buffer. These changes are too numerous to practically describe, so I included the entirety ot each file in `Sources`. Copy and paste these files' contents into the following directories:
 
```
Engine/Shaders/Private/Nanite/NaniteRasterizer.usf
Engine/Shaders/Private/Nanite/NaniteWritePixel.ush
Engine/Shaders/Private/ShadowDepthPixelShader.usf
```

At the path below, there are 5 locations where the shader compiler checks for 64-bit image atomic support. The check currently fails on Apple platforms, so elide the change. Replicate `Sources/NaniteCullRaster_Changes.cpp`, which demonstrated excluding these checks. All Nanite shaders should now compile.

```
Engine/Source/Runtime/Renderer/Private/Nanite/NaniteCullRaster.cpp
```

Debug views now appear; explain the crash.

> Warning: The text in this section is poorly written, so it may be difficult to understand.

TODO: Clean up changes to shaders, consolidate change 3 to only describe those changes.

I got Nanite to activate, but it crashes whenever the Unreal Editor touches it. This will require a lot of work to fix. Furthermore, Epic made [this commit](https://github.com/EpicGames/UnrealEngine/commit/9b68f6b76686b3fabe1c8513efcf95dd74dea1c3#) which removed support for Nanite on devices without UInt64 image atomics. I will need to undo the changes in that commit.

Another issue: the previous (now removed) 32-bit atomic workaround still performed operations on textures. Metal only supports atomics on buffers. This is not a big deal, because I can make the lock buffer into a buffer, not a texture. I have to know the color texture's width, then give each thread an independent index by multiplying (Y * width + X).

Alternatively, I could create a common buffer and texture that stores 64-bit data. Create the texture by sub-allocating the resource from a buffer, then pass in the resources as both texture and buffer form into the shader. Atomic operations would happen on the same data that's being written to. Perhaps I can pull off a few more tricks that exploit Apple silicon's memory coherency traits, creating a robust lock-based workaround to UInt64 atomics.
 
For example, reads and writes to 64-bit chunks of data might be naturally atomic if aligned to 8 bytes. I could do a compare-and-swap to validate that any accesses did not have a data race. Also, Metal Shading Language has texture synchronization functions that ensure if one thread writes to a texture, then reads from the same position, the read value reflects the written value. This might trigger some synchronization mechanism in hardware that helps with the UInt64 image atomics workaround.

Finally, there's the issue of whether Epic will accept this hack. They might accept it if I restrict it to Apple8 GPUs, which have a hardware instruction for UInt64 min/max atomics. Other GPUs (like the Apple7 M1) would use a hack or even non-atomic operations just for the purpose of creating Nanite support. Once that is developed, we remove the hack version from Apple7 and only enable such atomics on Apple8.

---

Another idea: you don't need all 32 bits of the depth; 30 would be fine. What if you could split up 62 bits of data into two 32-bit chunks, each prefixed with one bit that states whether it's in use? Then an external lock (separate buffer of 32-bit data) coordinates thread accesses, and you do a bunch of spin lock-like atomic loads/stores to sanitize accesses to each half of the 64-bit texture/buffer slot. This might have low performance, but could have zero data races on Apple7. Then, we use native 64-bit UInt64 min/max on Apple8 for better performance. This could be enough for Epic to merge the Nanite port into UE5.

> I could try prototyping this workaround for Apple7 GPUs in an isolated Xcode project. There should be intense testing to detect any theoretically possible data races.

Another idea: the depth originates from a normalized floating point number, which can only store 24 bits of information. Break up the pixel from 32 bits into 8 bits, then you can distribute each chunk along with the depth (8 + 24 = 32). You would have 4 times as many atomic operations as with 64-bit atomics, but it would work and be 100% thread safe!

## Attribution

This repo sources some information from [UE5NanitePort](https://github.com/gladhu/UE5NanitePort). By linking to the repository, I hereby give the creator attribution for their work.

I also reused ideas found on the "Lumen & Nanite on MacOS" thread from Epic Dev Community forums.
