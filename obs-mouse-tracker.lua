-- OBS Studio Lua Script: Vertical Mouse Follower for Linux (X11)
-- Designed for Debian/Xfce to create 9:16 TikTok reels from 16:9 monitors.
--
-- Author: Michael Kirkland (mak.kirkland@proton.me)
-- Requirements: Linux X11 environment (standard on Xfce)

local obs = obslua
local ffi = require("ffi")

-- Define X11 structures and functions for FFI
ffi.cdef[[
    typedef unsigned long XID;
    typedef XID Window;
    typedef struct _XDisplay Display;

    Display *XOpenDisplay(const char *display_name);
    int XCloseDisplay(Display *display);
    Window XDefaultRootWindow(Display *display);

    typedef int Bool;

    Bool XQueryPointer(
        Display *display,
        Window w,
        Window *root_return,
        Window *child_return,
        int *root_x_return,
        int *root_y_return,
        int *win_x_return,
        int *win_y_return,
        unsigned int *mask_return
    );
]]

-- Script Settings
local settings = {
    source_name = "",
    smoothness = 0.1, -- 0.01 (slow) to 1.0 (instant)
    monitor_width = 1920,
    canvas_width = 608, -- 1080 * (9/16) ~= 608
    x_offset = 0 -- Adjust if you have multiple monitors left of main
}

-- Runtime State
local x11_display = nil
local current_x = 0
local target_x = 0

-- Description shown in OBS
function script_description()
    return [[
LINUX X11 MOUSE FOLLOWER

Automatically pans a source to follow the mouse cursor.
Designed for recording vertical (9:16) video on a horizontal monitor.

Ensure your OBS Video Base Resolution is set to 608x1080.
]]
end

-- Define default settings (Fixes the issue where OBS defaults to min slider value)
function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "source_name", "")
    obs.obs_data_set_default_double(settings, "smoothness", 0.1)
    obs.obs_data_set_default_int(settings, "monitor_width", 1920)
    obs.obs_data_set_default_int(settings, "canvas_width", 608)
    obs.obs_data_set_default_int(settings, "x_offset", 0)
end

-- Properties menu in OBS
function script_properties()
    local props = obs.obs_properties_create()

    -- Dropdown to select the source
    local p = obs.obs_properties_add_list(props, "source_name", "Source to Pan", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local name = obs.obs_source_get_name(source)
            obs.obs_property_list_add_string(p, name, name)
        end
        obs.source_list_release(sources)
    end

    obs.obs_properties_add_float_slider(props, "smoothness", "Smoothness", 0.01, 1.0, 0.01)
    obs.obs_properties_add_int(props, "monitor_width", "Monitor Width", 800, 7680, 1)
    obs.obs_properties_add_int(props, "canvas_width", "Canvas Width (Target)", 100, 4000, 1)
    obs.obs_properties_add_int(props, "x_offset", "X Offset (Multimonitor)", -5000, 5000, 1)

    return props
end

-- Update settings values
function script_update(s)
    settings.source_name = obs.obs_data_get_string(s, "source_name")
    settings.smoothness = obs.obs_data_get_double(s, "smoothness")
    settings.monitor_width = obs.obs_data_get_int(s, "monitor_width")
    settings.canvas_width = obs.obs_data_get_int(s, "canvas_width")
    settings.x_offset = obs.obs_data_get_int(s, "x_offset")
end

-- Initialize X11 connection
function script_load(settings)
    -- List of library names to try.
    -- Debian usually requires 'libX11.so.6' if the dev package isn't installed.
    local lib_candidates = {
        "X11",
        "libX11.so",
        "libX11.so.6",
        "/usr/lib/x86_64-linux-gnu/libX11.so.6",
        "/usr/lib/libX11.so.6"
    }

    local success = false
    local lib = nil

    for _, lib_name in ipairs(lib_candidates) do
        success, lib = pcall(ffi.load, lib_name)
        if success then
            obs.script_log(obs.LOG_INFO, "Loaded X11 library via: " .. lib_name)
            break
        end
    end

    if not success then
        obs.script_log(obs.LOG_WARNING, "CRITICAL: Could not load libX11. Tried: X11, libX11.so, libX11.so.6")
        return
    end

    x11_display = lib.XOpenDisplay(nil)
    if x11_display == nil then
        obs.script_log(obs.LOG_WARNING, "Could not open X Display.")
        return
    end

    obs.script_log(obs.LOG_INFO, "X11 Display Opened Successfully.")
end

-- Cleanup
function script_unload()
    if x11_display ~= nil then
        ffi.C.XCloseDisplay(x11_display)
    end
end

-- Linear Interpolation helper
function lerp(a, b, t)
    return a + (b - a) * t
end

-- The main loop (runs every frame)
function script_tick(seconds)
    if x11_display == nil then return end

    -- 1. Get Mouse Position from X11
    local root = ffi.new("Window[1]")
    local child = ffi.new("Window[1]")
    local root_x = ffi.new("int[1]")
    local root_y = ffi.new("int[1]")
    local win_x = ffi.new("int[1]")
    local win_y = ffi.new("int[1]")
    local mask = ffi.new("unsigned int[1]")

    local default_root = ffi.C.XDefaultRootWindow(x11_display)
    local result = ffi.C.XQueryPointer(x11_display, default_root, root, child, root_x, root_y, win_x, win_y, mask)

    if result == 0 then return end -- Mouse query failed

    local mouse_x_raw = root_x[0] - settings.x_offset

    -- 2. Calculate Target Position for the Source
    -- Logic: We want the mouse_x to be in the center of the canvas_width.
    -- If Canvas is 608px wide, Center is 304.
    -- If Mouse is at 1000px on screen.
    -- Source Position + 1000 = 304  =>  Source Position = 304 - 1000 = -696.

    local center_target = settings.canvas_width / 2
    local desired_source_x = center_target - mouse_x_raw

    -- 3. Clamp the movement
    -- We don't want the source to drift off into the void.
    -- Max X is 0 (Left edge of source aligned with left edge of canvas)
    -- Min X is CanvasWidth - MonitorWidth (Right edge of source aligned with right edge of canvas)

    local min_x = settings.canvas_width - settings.monitor_width
    local max_x = 0

    if desired_source_x > max_x then desired_source_x = max_x end
    if desired_source_x < min_x then desired_source_x = min_x end

    -- 4. Apply Smoothing (Lerp)
    -- Adjust framerate dependency roughly
    local fps_mult = seconds * 60
    current_x = lerp(current_x, desired_source_x, settings.smoothness * fps_mult)

    -- 5. Apply to OBS Scene Item
    local source = obs.obs_get_source_by_name(settings.source_name)
    if source ~= nil then
        local scene_source = obs.obs_frontend_get_current_scene()
        if scene_source ~= nil then
            local scene = obs.obs_scene_from_source(scene_source)
            if scene ~= nil then
                local scene_item = obs.obs_scene_find_source(scene, settings.source_name)
                if scene_item ~= nil then
                    local pos = obs.vec2()
                    pos.x = current_x
                    pos.y = 0 -- Keep top aligned
                    obs.obs_sceneitem_set_pos(scene_item, pos)
                end
            end
            obs.obs_source_release(scene_source)
        end
        obs.obs_source_release(source)
    end
end