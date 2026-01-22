# OBS Linux Mouse Follower

A lightweight Lua script for OBS Studio on Linux that automatically pans a video source to keep your mouse cursor centered.

This tool is designed for content creators on Linux (X11) who want to record **vertical (9:16) TikTok/Reels/Shorts** on a standard **horizontal (16:9) monitor**. Instead of cropping your screen to a static area, this script smoothly follows your cursor movement.

## Features

-   **Native Linux Support:** Uses LuaJIT FFI to interface directly with X11 (`libX11`); no external Python scripts or background processes required.
-   **Smooth Tracking:** Implements adjustable Linear Interpolation (Lerp) for cinematic, non-jittery camera movement.
-   **Dynamic Panning:** Automatically calculates offsets to keep the mouse centered within a defined vertical viewport.

## Prerequisites

-   **OBS Studio** (v21.0 or newer recommended).
-   **Desktop Environment:** Must be running **X11** (Xorg).
    -   *Note: This script relies on `XQueryPointer` and will not work natively on Wayland sessions unless running via XWayland with specific permissions, which is not guaranteed.*
-   **Dependencies:** Standard X11 libraries (usually installed by default on Debian/Ubuntu/Fedora).

## Installation

1.  Download the `mouse_follow_linux.lua` file.
2.  Open OBS Studio.
3.  Go to **Tools** -> **Scripts**.
4.  Click the **+** (Plus) icon in the bottom left.
5.  Select the `mouse_follow_linux.lua` file.

## Configuration

### 1. OBS Video Settings
To create vertical content, you must set your OBS Canvas to a vertical aspect ratio.
1.  Go to **Settings** -> **Video**.
2.  Set **Base (Canvas) Resolution** to `608x1080` (This is the 9:16 slice of a 1080p monitor).
3.  Set **Output (Scaled) Resolution** to match (`608x1080`).
4.  Set **FPS** to `60`.

### 2. Scene Setup
1.  Add a **Screen Capture (XSHM)** source.
2.  Ensure it is capturing your full desktop (e.g., 1920x1080).
3.  **Do not crop** the source manually. Let it extend past the edges of the canvas.

### 3. Script Settings
In the **Tools -> Scripts** window, click on `mouse_follow_linux.lua` to access the settings panel:

* **Source to Pan:** Select your Screen Capture (XSHM) source.
* **Smoothness:** Controls the camera lag/follow speed.
    * `0.1` = Cinematic/Slow
    * `0.5` = Fast/Gaming
    * `1.0` = Instant (No smoothing)
* **Monitor Width:** Set to your physical monitor width (default `1920`).
* **Canvas Width:** Set to your OBS Canvas width (default `608`).
* **X Offset:** Adjust this if you have a multi-monitor setup and the cursor tracking is offset (e.g., if your main monitor is the second screen).

## Troubleshooting

### "Error: Could not load libX11"
The script attempts to load `libX11.so`, `libX11.so.6`, or `X11`. On some systems (like Debian/Ubuntu), the base `.so` file is part of the developer packages.

If the script fails to load, try installing the development headers:

```bash
sudo apt install libx11-dev
```

### The camera is stuck or drifts to the wrong side

* Ensure **Monitor Width** matches your screen resolution (e.g., 1920).
* Ensure **Canvas Width** matches your OBS Video Settings (e.g., 608).
* If you have monitors to the left of your main screen, you may need to adjust the **X Offset**.
