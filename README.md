# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to macOS.

## Usage

I am currently experimenting with UE5. You can follow these instructions to replicate what I've done.

<details>
<summary>Prerequisites</summary>

---

- At least 155 GB of free disk space, after installing everything described below.
- Install [Homebrew](https://brew.sh).
- Install Git. This can be accomplished using Homebrew: `brew install git`.
- Install Xcode 14 beta from [developer.apple.com](https://developer.apple.com/xcode/resources). Rename the app `Xcode-beta` and place it in `~/Applications`.
- [Create](https://www.epicgames.com/id/register) an Epic Games account and [link](https://www.epicgames.com/help/en-US/epic-accounts-c5719348850459/connect-accounts-c5719351300507/how-do-i-link-my-unreal-engine-account-with-my-github-account-a5720369784347) it to your GitHub account.

> <sup>1</sup>Xcode 14 should be released in September 2022. When it is no longer in beta, Xcode from the Mac App Store will work.

Perform the following in a new Terminal window, then close the window. This ensures\* that UnrealBuildTool uses Xcode beta instead of regular Xcode.

```
>>> sudo xcode-select --switch ~/Applications/Xcode-beta.app
(prompt to enter password)
>>> swift --version
(Swift 5.7 should appear in the output)
```

> \*I'm not 100% sure this is necessary, but it's better to play it safe.

</details>
<details>
<summary>Sign in to Git and download 'EpicGames/UnrealEngine'</summary>

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

While cloning the UE5 repository, it may ask for your credentials. Enter the access token from above instead of your account password. The download may take an hour with average internet speeds, so `git clone` has flags that minimize the amount of downloaded commits.

</details>
<details>
<summary>Compile unmodified 'ue5-main'</summary>

---

Follow [this guide](https://docs.unrealengine.com/5.0/en-US/downloading-unreal-engine-source-code), starting with step 3 of "Downloading the Source Code". The instructions below are adapted from [another guide](https://docs.unrealengine.com/5.0/en-US/building-unreal-engine-from-source), which is slightly outdated. Do not run through the latter guide.
  
Click <b>Menu Bar > Product > Build</b>. The command fails because an `Info.plist` is not generated. In the project navigator, select <b>Engine > UE5</b>. Click the <b>Build Settings</b> tab, then look at <b>TARGETS</b> on the left. Select <b>UE5</b>, which has a gray (not blue) App Store icon next to it. In the build settings search bar, type "generate info". Only one setting pops up: "Generate Info.plist File". Change its value from "No" to "Yes".

Click <b>Menu Bar > Product > Build</b>. Building should take on the order of 10 - 30 minutes. In the activity monitor, 8-10 `clang` processes should use 100% of the CPU for several minutes. If they max out at 50% of the CPU, something is going wrong.

Click <b>Menu Bar > Product > Run</b>. Give Unreal Editor permission to access `Documents`. The application will shut down after accessing a nonexistent `YES/YES.uproject`; check the Xcode console to validate that the failure happens. Now, navigate to this path in Finder and double-click the `UnrealEditor` application.

```
/Users/<your username>/Documents/UnrealEngine/UnrealEngine/Engine/Binaries/Mac
```

After some time, the "Unreal Project Browser" window appears.

</details>
<details>
<summary>Create your 'EpicGames/UnrealEngine' fork and branch</summary>
  
<!-- Git add + commit should not show any changes -->

</details>
