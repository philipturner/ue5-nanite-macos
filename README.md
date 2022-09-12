# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to Apple platforms. Read over [this forum thread](https://forums.unrealengine.com/t/lumen-nanite-on-macos/508411) for more context.

## How it Works

Nanite can run entirely through 32-bit atomics, without creating data races. The [AtomicsWorkaround](./AtomicsWorkaround) directory provides source code demonstrating this workaround. Eventually, `ue5-nanite-macos` will use the workaround to make Nanite run without graphical glitches.

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

Look at [`Sources/RenderUtils_Changes.h`](./Sources/RenderUtils_Changes.h) in this repository. In UE source code, navigate to the path (1) below. Replace the body of `NaniteAtomicsSupported()` with my changes. At path (2), add `bSupportsNanite=true` underneath `[ShaderPlatform METAL_SM5]`. This only enables Nanite on macOS, not iOS or tvOS yet. The engine now crashes at runtime.

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

To fix the crash above, set the persistent thread group count for MetalRHI to 1440 - the same value as DirectX and Vulkan. Navigate to the path below and change `FMetalDynamicRHI::Init()` to the contents of [`Sources/MetalRHI_Changes.cpp`](./Sources/MetalRHI_Changes.cpp). The engine now crashes because it cannot find `FInstanceCull_CS`. The GPU had a soft fault before UE crashed, so something is going very wrong.

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

[UE5NanitePort](https://github.com/gladhu/UE5NanitePort) enabled Nanite through a special shader execution path on Apple platforms. The path replaced 32-bit texture atomics with unsafe reads and writes. Depths could register incorrectly, causing hidden objects to appear in front of objects that occlude them. This may explain the graphical glitches in the associated Reddit post. Metal supports 32-bit buffer atomics, so a better solution replaces the textures with buffers. This takes more time to implement, but reduces/eliminates graphical glitches.
 
Since that port, Epic permanently disabled Nanite on platforms that lack 64-bit atomics. [This commit](https://github.com/EpicGames/UnrealEngine/commit/9b68f6b76686b3fabe1c8513efcf95dd74dea1c3#) removed the lock-based control path that used 32-bit atomics. Therefore, my shader modifications heavily diverge from UE5NanitePort. [`Sources`](./Sources) contains the entire contents of each modified shader. Overwrite the files below with their counterparts from `ue5-nanite-macos`:
 
```
Engine/Shaders/Private/Nanite/NaniteRasterizer.usf
Engine/Shaders/Private/Nanite/NaniteWritePixel.ush
Engine/Shaders/Private/ShadowDepthPixelShader.usf
```

At the path below, the shader compiler checks for 64-bit image atomic support. The check happens in 5 different locations and fails each time. 
Use the preprocessor directive in [`Sources/NaniteCullRaster_Changes.cpp`](./Sources/NaniteCullRaster_Changes.cpp) to disable each check.

```
Engine/Source/Runtime/Renderer/Private/Nanite/NaniteCullRaster.cpp
```

Now, Nanite debug views appear in the editor. Rendering any Nanite-enabled object causes a crash.

<details>
<summary>Crash description</summary>

```
[UE] [2022.09.09-17.56.48:845][ 12]LogMaterial: Display: Material /Game/StarterContent/Materials/M_Basic_Wall.M_Basic_Wall needed to have new flag set bUsedWithNanite !
[UE] [2022.09.09-17.57.01:471][129]LogEditorViewport: Clicking Background
[UE] [2022.09.09-17.57.04:933][441]LogSlate: Took 0.000082 seconds to synchronously load lazily loaded font '../../../Engine/Content/Slate/Fonts/Roboto-Regular.ttf' (155K)
[UE] [2022.09.09-17.57.12:041][858]LogActorFactory: Actor Factory attempting to spawn StaticMesh /Game/StarterContent/Shapes/Shape_Sphere.Shape_Sphere
[UE] [2022.09.09-17.57.12:041][858]LogActorFactory: Actor Factory attempting to spawn StaticMesh /Game/StarterContent/Shapes/Shape_Sphere.Shape_Sphere
[UE] [2022.09.09-17.57.12:042][858]LogActorFactory: Actor Factory spawned StaticMesh /Game/StarterContent/Shapes/Shape_Sphere.Shape_Sphere as actor: StaticMeshActor /Temp/Untitled_0.Untitled:PersistentLevel.StaticMeshActor_0
[UE] Ensure condition failed: 0 [File:./Runtime/Apple/MetalRHI/Private/MetalStateCache.cpp] [Line: 1958] 
Mismatched texture type: EMetalShaderStages 1, Index 0, ShaderTextureType 2 != TexTypes 9
```

</details>

## Change 4

The crash occured while validating resource bindings for a render command. One texture was `.type2D` (raw value 2) and the other was `.typeTextureBuffer` (raw value 9). In the fragment shader source below, one argument is a `texture_buffer`. A 2D texture was bound in the location of this resource.

<details>
<summary>Vertex shader</summary>

```metal
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct type_Globals
{
    float DownsampleFactor;
    float2 InvViewSize;
};

constant float2 _44 = {};

struct RasterizeToRectsVS_out
{
    float2 out_var_TEXCOORD0 [[user(locn0)]];
    float2 out_var_TEXCOORD1 [[user(locn1)]];
    float out_var_RECT_INDEX [[user(locn2)]];
    float4 gl_Position [[position, invariant]];
};

vertex RasterizeToRectsVS_out Main_0000092b_c6f0736c(
    constant type_Globals& _Globals [[buffer(0)]], 
    texture_buffer<uint> RectCoordBuffer [[texture(0)]], 
    uint gl_InstanceIndex [[instance_id]], 
    uint gl_VertexIndex [[vertex_id]], 
    uint gl_BaseVertex [[base_vertex]], 
    uint gl_BaseInstance [[base_instance]])
{
    RasterizeToRectsVS_out out = {};
    uint4 _49 = RectCoordBuffer.read(uint((gl_InstanceIndex - gl_BaseInstance)));
    float4 _50 = float4(_49);
    float4 _53 = _50 * _Globals.DownsampleFactor;
    uint4 _54 = uint4(_53);
    bool _55 = (gl_VertexIndex - gl_BaseVertex) == 1u;
    bool _56 = (gl_VertexIndex - gl_BaseVertex) == 2u;
    bool _57 = _55 || _56;
    bool _58 = (gl_VertexIndex - gl_BaseVertex) == 4u;
    bool _59 = _57 || _58;
    bool _60 = _56 || _58;
    bool _61 = (gl_VertexIndex - gl_BaseVertex) == 5u;
    bool _62 = _60 || _61;
    uint _63 = _54.z;
    uint _64 = _54.x;
    uint _65 = _59 ? _63 : _64;
    uint _66 = _54.w;
    uint _67 = _54.y;
    uint _68 = _62 ? _66 : _67;
    uint2 _69 = uint2(_65, _68);
    float4 _74 = float4(_54) * _Globals.InvViewSize.xyxy;
    float2 _82 = float2(_69);
    float2 _83 = _82 * _Globals.InvViewSize;
    float2 _84 = _83 * float2(2.0, -2.0);
    float2 _85 = _84 + float2(-1.0, 1.0);
    float _86 = _85.x;
    float _87 = _85.y;
    float4 _88 = float4(_86, _87, 0.0, 1.0);
    float2 _90 = _44;
    _90.x = float(_59);
    float2 _92 = _90;
    _92.y = float(_62);
    out.gl_Position = _88;
    out.out_var_TEXCOORD0 = float2(_59 ? _74.z : _74.x, _62 ? _74.w : _74.y);
    out.out_var_TEXCOORD1 = _92;
    out.out_var_RECT_INDEX = float((gl_InstanceIndex - gl_BaseInstance));
    return out;
}
```

</details>

<details>
<summary>Fragment shader</summary>

```metal
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Identity function as workaround for bug in Metal compiler
template<typename T>
T spvIdentity(T x)
{
    return x;
}

struct type_Globals
{
    uint4 ClearValue;
};

fragment void Main_0000030f_ba464dd8(
    constant type_Globals& _Globals [[buffer(1)]], 
    texture_buffer<uint, access::write> ClearResource [[texture(0)]], 
    float4 gl_FragCoord [[position]])
{
    ClearResource.write(
        spvIdentity(_Globals.ClearValue), 
        uint(uint(gl_FragCoord.x)));
}
```

</details>
 
The fragment shader was transpiled from an HLSL shader, located at path (1) below. `RESOURCE_TYPE` was set to either 0 or 5, making `ClearResource` a `RWBuffer`. I'll swapping the fragment shader with another one, where `RESOURCE_TYPE` was set to 1. That should change the clear resource to a `RWTexture2D`.

The command in question began in some other portion of the code base, and on another thread, which I can't see from the stack trace. During the command's creation, all of the Metal shader pipelines and resources were assigned. At the crash site, it read the mismatched pipeline and resource, then failed to encode them into a `MTLCommandBuffer`.

At path (2) below, around line 526, it registers a 2D texture as the clear replacement resource. This happens before any render commands are encoded. Next, `FRHICommandListExecutor` encodes around 100 render commands (path 3, circa line 511). `FMetalRHICommandContext` sets a new graphics PSO (path 4, circa line 258) which I presume uses the vertex/fragment shaders shown above. After encoding a few more commands, the assertion failure happens (path 5, circa line 2066).

```
(1) Engine/Shaders/Private/ClearReplacementShaders.usf
(2) Engine/Source/Runtime/Apple/MetalRHI/Private/MetalUAV.cpp
(3) Engine/Source/Runtime/RHI/Private/RHICommandList.cpp
(4) Engine/Source/Runtime/Apple/MetalRHI/Private/MetalCommands.cpp
(5) Engine/Source/Runtime/Apple/MetalRHI/Private/MetalStateCache.cpp
```

During the crash, the current `GraphicsPSO` does not match anything set at (path 4, circa line 258). I don't know whether it's because `UE_LOG` always fails to flush before the crash, or the graphics pipeline was modified at a different call site. I could not force `UE_LOG` to flush, and they only way I could reliaby print information before the crash was in the crash message itself (`ensureMsgf`).

## Attribution

This repo sources some information from [UE5NanitePort](https://github.com/gladhu/UE5NanitePort). By linking to the repository, I hereby give the creator attribution for their work.

I also reused ideas found on the "Lumen & Nanite on MacOS" thread from Epic Dev Community forums.
