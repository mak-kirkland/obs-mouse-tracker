# OBS Linux Mouse Follower

A lightweight Lua script for OBS Studio on Linux that automatically pans a video source to keep your mouse cursor centered within the viewport.

This tool supports **vertical (9:16) content**, **square crops**, or **arbitrary 2D tracking**, allowing you to create any size "viewport" around your cursor.

## Support

If you find this script useful, please consider supporting me on Patreon:

❤️ [Support on Patreon](https://patreon.com/MichaelKirkland)

## Features

-   **Native Linux Support:** Uses LuaJIT FFI to interface directly with X11 (`libX11`).
-   **2D Tracking:** Follows the mouse in both X and Y axes.
-   **Auto-Centering:** Optionally centers the tracking viewport within your OBS scene (great for recording small crops on a large canvas).
-   **Automatic Axis Locking:** If your Target dimension matches your Source dimension, that axis automatically locks (prevents movement).
-   **Smooth Tracking:** Adjustable tracking speed with interpolation.

## Installation

1.  Download `obs-mouse-tracker.lua`.
2.  Open OBS Studio -> **Tools** -> **Scripts**.
3.  Click **+** and select the file.

## Configuration & Use Cases

### 1. Vertical (9:16) TikTok/Shorts
*Recording a vertical slice of a wide monitor.*
* **OBS Video Settings:** Set Base Resolution to `608x1080`.
* **Script Settings:**
    * Source Width/Height: `1920` / `1080` (or your actual source resolution)
    * Target Width/Height: `608` / `1080`
    * Center Viewport: `Unchecked` (Usually not needed if canvas is already vertical)

### 2. The "Focus Box" (Square Crop)
*Recording a zoomed-in 800x800 box around the cursor, centered on a 1080p canvas.*
* **OBS Video Settings:** Base Resolution `1920x1080`.
* **Script Settings:**
    * Source Width/Height: `1920` / `1080`
    * Target Width/Height: `800` / `800`
    * Center Viewport: `Checked` (This keeps the box in the middle of your screen)

## Settings Guide

* **Source to Pan:** Select your Screen Capture (XSHM) source.
* **Tracking Speed:**
    * `0.1` = Cinematic / Slow
    * `1.0` = Instant
* **Center Viewport:** If checked, forces the tracking window to stay in the center of the OBS preview. If unchecked, the window defaults to the top-left (0,0).
* **Source Dimensions:** Input the **current size of your source inside OBS**.
    * *Important:* If you resized your source (e.g., "Fit to Screen" on a 1440p monitor onto a 1080p canvas), use the scaled size (1920x1080), not the physical monitor size.
* **Target Dimensions:** The size of the "window" you want to see around the mouse.
* **Offsets:** Use these if you have multiple monitors and the mouse coordinates are shifted.

## Troubleshooting

### The source is shrinking or showing black bars?
Check your **Source Dimensions**. If this setting is larger than the actual source in OBS, the script will try to scroll past the edge of the image. Ensure "Source Width/Height" matches the source's properties in OBS.

### Camera moves when I don't want it to?
The script moves the source *only* if the Target size is smaller than the Source size. If you want to lock the Y-axis, ensure **Target Height** is set to the same value as **Source Height**.

### "Error: Could not load libX11"
Install development headers:
```bash
sudo apt install libx11-dev
```

### The camera is stuck or drifts to the wrong side

* Ensure **Monitor Width** matches your screen resolution (e.g., 1920).
* Ensure **Canvas Width** matches your OBS Video Settings (e.g., 608).
* If you have monitors to the left of your main screen, you may need to adjust the **X Offset**.
