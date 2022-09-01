# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to macOS.

## Usage

I have not added Nanite to UE5 yet; these steps show my progress so far.

Prerequisites:
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

Create a folder called `UnrealEngine` in `~/Documents`. Right-click the folder in Finder and click "New Terminal at Folder". Enter this command into Terminal:

```
>>> pwd
/Users/<your username>/Documents/UnrealEngine
```

<!--
Use xcode-select, query `swift --version` to prove with Xcode you're using.

To start, download Unreal Engine's GitHub repository. You must have an Epic Games account and access to the private GitHub organization. This can take an hour with average internet speeds, so minimize the amount of branches you pull. The command below only

```
git clone --single-branch -b ue5-main https://github.com/EpicGames/UnrealEngine
```


-->
