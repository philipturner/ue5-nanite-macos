# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to macOS.

## Usage

I have not added Nanite to UE5 yet; these steps show my progress so far.

<details>
<summary>Prerequisites</summary>

---

- Install [Homebrew](https://brew.sh)
- Install Git. This can be accomplished using Homebrew: `brew install git`.
- Install Xcode 13<sup>1</sup> from the Mac App Store.
- Install Xcode 14 beta from [developer.apple.com](https://developer.apple.com/xcode/resources). Rename the app `Xcode-beta` and place it in `~/Applications`.
- [Create](https://www.epicgames.com/id/register) an Epic Games account and [link](https://www.epicgames.com/help/en-US/epic-accounts-c5719348850459/connect-accounts-c5719351300507/how-do-i-link-my-unreal-engine-account-with-my-github-account-a5720369784347) it to your GitHub account.

> <sup>1</sup>Xcode 14 should be released in September 2022. This information may become outdated soon.

To repeat my steps and investigate bugs, you will switch between Xcode 13 and Xcode 14 beta often. Perform the following in a new Terminal window, then close the window.

```
>>> sudo xcode-select --switch ~/Applications/Xcode-beta.app
(prompt to enter password)
>>> swift --version
(Swift 5.7 should appear in the output)
>>> sudo xcode-select --switch ~/Applications/Xcode.app
(prompt to enter password)
>>> swift --version
(Swift 5.6.1 should appear in the output)
```

</details>
<details>
<summary>Sign in to Git and download 'EpicGames/UnrealEngine'</summary>

---

Sign into Git through Xcode. Launch the "Xcode" app and go to <b>Menu Bar > Xcode > Preferences > Accounts</b>. Click the "+" button on the bottom left, then select the "GitHub" account type. A popup prompts you for a GitHub [access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). Generate one with the following scopes. <ins>Do not</ins> close the browser window showing that token's letters/digits until you've cloned the UE5 repository.

- admin:public_key
- write:discussion
- repo
- user

Enter your GitHub account username and the access token. Click "Sign In", then quit and restart Xcode. Create a folder called `UnrealEngine` in `~/Documents`. Right-click it in Finder and click "New Terminal at Folder". Enter these commands into the new Terminal window:

```
>>> pwd
/Users/<your username>/Documents/UnrealEngine
>>> git clone --single-branch -b ue5-main https://github.com/EpicGames/UnrealEngine
```

While cloning the UE5 repository, it may ask for your credentials. Enter the access token from above instead of your account password. The download may take an hour with average internet speeds, so `git clone` has flags that minimize the amount of downloaded commits.

</details>
<details>
<summary>Compile the unmodified 'ue5-main' branch</summary>

---

Follow [this guide](https://docs.unrealengine.com/5.0/en-US/downloading-unreal-engine-source-code) starting with step 3 of "Downloading the Source Code". Then, follow [this guide](https://docs.unrealengine.com/5.0/en-US/building-unreal-engine-from-source). Building should take on the order of 10 - 30 minutes. Unreal Editor will not launch from <b>Product > Run</b>, so navigate to the following URL in finder.

```
/Users/<your username>/Documents/UnrealEngine/UnrealEngine/Engine/Binaries/Mac
```

Click on the `UnrealEditor` application. After some time, the "Unreal Project Browser" window appears.

</details>
<details>
<summary>Recompile with Xcode 14 beta</summary>

<!-- Delete the "UnrealEditor" application from binaries -->

<!-- Compiling with Xcode 14 beta requires choosing "Open With" on the .xcworkspace -->

<!-- Attempt build > Error > Navigator??? > UE5 > Build Settings > Search Bar; generate info; Change "Generate Info.plist File" from "No" to "Yes"-->

<!-- Let it access your documents folder -->

</details>
