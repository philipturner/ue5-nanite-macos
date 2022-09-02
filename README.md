# Nanite on macOS

Brings the Nanite feature from Unreal Engine 5 to macOS.

## Usage

I am currently experimenting with UE5. You can follow these instructions to replicate what I've done.

<details>
<summary>Prerequisites</summary>

---

- At least 165 GB of free disk space, after installing everything described below.
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
>>> git clone --depth 1 --no-single-branch -b ue5-main https://github.com/EpicGames/UnrealEngine
```

While cloning the UE5 repository, it may ask for your credentials. Enter the access token from above instead of your account password. The download may take an hour with average internet speeds, so `git clone` has flags that minimize the amount of downloaded commits.

</details>
<details>
<summary>Compile unmodified 'ue5-main'</summary>

---

On [this guide](https://docs.unrealengine.com/5.0/en-US/downloading-unreal-engine-source-code), follow steps 3 and 4 of "Downloading the Source Code". Right-click `UE5.xcworkspace` and select <b>Open With > Xcode-beta</b>. The instructions below are adapted from [another guide](https://docs.unrealengine.com/5.0/en-US/building-unreal-engine-from-source), which is slightly outdated; no `UE4Editor` or `UE5Editor` scheme exists. Do not run through the latter guide.
  
Click <b>Menu Bar > Product > Build</b>. The command fails\* because an `Info.plist` is not generated. In the project navigator, select <b>Engine > UE5</b>. Click the <b>Build Settings</b> tab, then look at <b>TARGETS</b> on the left. Select <b>UE5</b>, which has a gray (not blue) App Store icon next to it. In the build settings search bar, type "generate info". Only one setting pops up: "Generate Info.plist File". Change its value from "No" to "Yes".

> \*This failure only happens on Xcode 14 beta.

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

In GitHub, fork [`EpicGames/UnrealEngine`](https://github.com/EpicGames/UnrealEngine). Check the box for cloning only the `release` branch; this minimizes the fork's size. Verify that a repo exists at `https://github.com/<username>/UnrealEngine`.

> Throughout this section, `<username>` refers to your GitHub username.

In Finder, go to `~/Documents/UnrealEngine/UnrealEngine` and click "New Terminal at Folder". Enter the following commands:

```
>>> git branch
* ue5-main
>>> git remote add <username> https://github.com/<username>/UnrealEngine
>>> git checkout -b modifications
>>> git add .
>>> git commit -m "Test Commit"
[modifications db644854a9] Test Commit
 2 files changed, 98 insertions(+)
 create mode 100644 Engine/Config/DefaultEngine.ini
 create mode 100644 Engine/Config/DefaultInput.ini
>>> git push <username> modifications
...
To https://github.com/<username>/UnrealEngine
 ! [remote rejected]       modifications -> modifications (shallow update not allowed)
error: failed to push some refs to 'https://github.com/<username>/UnrealEngine'
```

The push fails because you originally cloned a lightweight snapshot of UE5's repo. This made it shallow, prohibiting pushes to new remotes. The command below enables pushing to your fork, but may take an hour to complete.

> Skip the rest of this section, unless you want to save custom modifications to the cloud. Waiting for this `git fetch` is not fun and consumes lots of disk space (~30 GB). It might have been faster to omit `--depth 1` from the original `git clone` command and use `--single-branch`.

```
>>> git fetch --unshallow <username>
remote: Enumerating objects: 4186481, done.
remote: Counting objects: 100% (3987147/3987147), done.
remote: Compressing objects: 100% (1202630/1202630), done.
Receiving objects:  16% (634782/3922823), 1.77 GiB | 9.64 MiB/s
```

Finally, try pushing again. It should succeed this time.

```
>>> git push <username> modifications
[Something that isn't an error message]
```

</details>
<details>
<summary>'Hello World' modifications to UE5</summary>

---

<!-- Modify both the Unreal Editor and a product app using Unreal Engine -->

TODO

</details>

## Notes

After compiling the Unreal Engine from source, you may get random popups saying "XCBBuildService crashed". Ignore them; they do not mean the compilation of UE5 failed.
