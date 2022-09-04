# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to Apple platforms. Read over [this forum thread](https://forums.unrealengine.com/t/lumen-nanite-on-macos/508411) for more context.

## Usage

I am currently experimenting with UE5. You can follow these instructions to replicate what I've done.

<details>
<summary>Prerequisites</summary>

---

- At least 185 GB of free disk space, after installing everything described below.
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

On a local machine, I force-enabled [`NaniteAtomicsSupported()`](https://github.com/EpicGames/UnrealEngine/blob/07cf5345692d0c6ce80a748c001efea5eee16eb1/Engine/Source/Runtime/RenderCore/Public/RenderUtils.h#L713-L743) and the build system acted strangely. `XCBBuildService` crashed in the middle of every build, making `UnrealBuildTool` execute in the background. I could not track `UnrealBuildTool`'s progress in Xcode to estimate when it would finish. The second time this happened, I noticed that Clang was still consuming 100% CPU and `XCBBuildService` had silently respawned in Activity Monitor. 
 
Disk space started getting eaten up and I could not find which folder was consuming increasingly more disk space. `~/Documents/UnrealEngine` stayed constant at 199 GB, while <b>Menu Bar >  > About This Mac > Storage</b> showed a gigabyte being consumed every ~10 seconds. I had to reboot my Mac, reset the `UnrealEngine` directory, and recompile with Xcode 13. Nanite doesn't require Metal 3 functionality, so Xcode 14 beta is not necessary.

To launch the Unreal Editor inside Xcode (where you can debug it when it crashes), repeat the process for creating `UnrealProject1`. Go through <b>GAMES > First Person > Project Defaults > BLUEPRINT</b> and name it `UnrealProject2`. `UnrealProject1` was difficult to work with because I created it with Xcode 14 beta. Switching to Xcode 13 caused a popup that requested to recompile missing modules. Blueprint projects are easier to work with, so I recommend using them from now on.
 
In Finder, copy the project from `~/Documents/Unreal Projects` to `~/Documents/UnrealEngine/UnrealEngine`. Rename its encapsulating folder from `UnrealProject2` to `YES` and its project file to `YES.uproject`. This bypasses the `YES/YES.uproject` failure described in "Compile unmodified 'ue5-main'".

</details>

## Modifications to UE5

[philipturner/UnrealEngine/commits/modifications](https://github.com/philipturner/UnrealEngine/commits/modifications) (private to Epic Games licensees) shows my most recent modifications to Unreal Engine.

### Explanation of Modifications

n/a

## Attribution

After compiling the Unreal Engine from source, you may get random popups saying "XCBBuildService crashed". Ignore them; they do not mean the compilation of UE5 failed. I have no idea why they appear.

This repo sources some information from [UE5NanitePort](https://github.com/gladhu/UE5NanitePort). By linking to the repository, I hereby give the creator attribution for their work.
