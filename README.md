# Phosphene

[English](README.md) · [简体中文](README.zh-CN.md)

> **This is a vibe-coded fork** of [kageroumado/phosphene](https://github.com/kageroumado/phosphene),
> written with an AI coding agent for one person's Mac. It adds one feature: a **separate desktop
> wallpaper**. The Phosphene video plays on the lock screen, and once you unlock, the desktop
> crossfades to an image or a second video of your choice. It is not affiliated with or supported
> by the upstream project; report problems here, not there.
>
> - **Use it:** in the menu bar, set Playback to **Lock Screen**, then **Desktop → Choose…** and
>   pick an image or a video. **Remove** goes back to the paused video on the desktop.
> - **How it works:** macOS has one wallpaper surface for both the lock screen and the desktop.
>   Each surface gets a second display layer above the video
>   ([`DesktopOverlay.swift`](PhospheneExtension/DesktopOverlay.swift)); it fades out for the lock
>   screen and back in when the agent presents the desktop again.
> - **Lock screen stays lit:** macOS turns a locked display off after about 30 seconds. While the
>   screen is locked, the app keeps the display on until your normal display-off time
>   ([`LockScreenAwake.swift`](Phosphene/LockScreenAwake.swift)). It never keeps the Mac awake.
> - **Scripts and agents:** `scripts/phosphenectl` does the same without the menu bar:
>   `desktop <file>`, `desktop --clear`, `playback everywhere|lockscreen|paused`,
>   `add-video <file>`, `restart-agent`, `status`, `log`. Each prints the app's answer.
> - **Build and install:** `scripts/build-local.sh --install` (ad-hoc signed, this Mac only). The
>   fork uses its own bundle IDs (`io.github.minomat180.phosphene`), so it never touches the
>   upstream app's library or updates, and its updater checks this fork's releases.
>
> Everything below is the upstream README.

Phosphene adds your videos to System Settings → Wallpaper through the same wallpaper pipeline as Apple’s Aerials. macOS plays them on the desktop and lock screen, even after you quit the app. It also turns **Wallpaper Engine** wallpapers from the Steam Workshop into video wallpapers.

<a href="https://kagerou.glass/get/phosphene?from=readme"><img src=".github/download.svg" alt="Download Phosphene for Mac" width="360" height="80"></a>

![Phosphene videos in System Settings → Wallpaper](.github/phosphene-settings.png)

## Highlights

- Use Wallpaper Engine wallpapers from the Steam Workshop: subscribe in Steam, and Phosphene makes a looping video of each.
- Select personal videos alongside Apple’s wallpapers in System Settings.
- Keep desktop and lock-screen playback running after quitting Phosphene.
- Pause playback under covered desktops and adjust decoding to power and thermal conditions.

<details>
<summary>Full feature list</summary>

- Import videos in the **Library** window and select them in **System Settings → Wallpaper**.
- Wallpaper selection per display or Space, plus a **Lock Screen**-only playback mode.
- Desktop and lock-screen playback through the macOS wallpaper pipeline.
- MP4, MOV, and other AVFoundation-readable inputs; gapless looping and lock/unlock transitions.
- Menu-bar preview, pause, display switching, and launch at login.
- Visibility, power, and thermal-aware playback; optional lower-resolution variants.
- **Restart Wallpaper Agent** from the menu bar for stuck playback.
- A **Wallpaper Engine** section: Steam Workshop downloads from Sevoflurane, CrossOver or Whisky become looping videos.

</details>

## Wallpaper Engine

![Phosphene’s library at its Wallpaper Engine section, with Steam Workshop downloads ready to become videos](.github/phosphene-library.png)

The Steam Workshop has hundreds of thousands of animated wallpapers made for Wallpaper Engine, a Windows program. Phosphene turns them into video wallpapers: subscribe in Steam, pick them in the library's Wallpaper Engine section, and choose Make Videos.

Wallpaper Engine runs in Windows Steam. [Sevoflurane](https://kagerou.glass/sevoflurane/?from=phosphene-readme) brings that Steam to your Mac, free, from the same developer. What a video keeps and what it leaves out: [WALLPAPER-ENGINE.md](WALLPAPER-ENGINE.md).

Wallpaper Engine is a trademark of Wallpaper Engine Team; Steam is a trademark of Valve Corporation. Phosphene is an independent app.

## Counting

Nothing is sent unless you say so. The menu bar asks once whether to count this Mac; if you count yourself in, Phosphene sends one anonymous check-in on each day you use it: the Phosphene and macOS versions, chip family and memory size, language and date, how many of the last 7 days you used it, whether you have your own videos, and how many displays. It never includes which videos you use, and nothing in it names you. A second tier adds a scrubbed report when Phosphene itself crashes. Turning it off deletes everything this Mac sent. Every field is listed in the [Digoxin reference](https://github.com/kageroumado/digoxin/blob/main/REFERENCE.md).

## Notes

- macOS 26+ · Apple silicon or Intel.
- Homebrew: `brew install --cask phosphene`.
- Uses private `WallpaperExtensionKit` APIs, which macOS updates can change. [Troubleshooting and implementation](REFERENCE.md).
