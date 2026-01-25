-- OBS Studio Lua Script: Mouse Follower for Linux (X11)
-- Automatically pans a source to keep the mouse centered in the viewport.
-- Supports Horizontal, Vertical, Box tracking, and Auto-Centering.
--
-- Author: Michael Kirkland (mak.kirkland@proton.me)
-- Requirements: Linux X11 environment

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
    tracking_speed = 0.1, -- 0.01 (slow) to 1.0 (instant)
    source_width = 1920,
    source_height = 1080,
    canvas_width = 608,
    canvas_height = 1080,
    center_viewport = false, -- Centers the tracking box in the OBS scene
    x_offset = 0,
    y_offset = 0
}

-- Runtime State
local x11_display = nil
local current_x = 0
local current_y = 0
local cached_scene_item = nil -- Cache for performance optimization

-- Description shown in OBS
function script_description()
    return [[
LINUX X11 MOUSE FOLLOWER (2D + Centering)

Pans a source to keep the mouse cursor centered.

IMPORTANT: "Source Width/Height" must match the source's size inside OBS!
If you scaled your source (e.g. Fit to Screen), use those dimensions here.
]]
end

-- Define default settings
function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "source_name", "")
    obs.obs_data_set_default_double(settings, "tracking_speed", 0.1)
    obs.obs_data_set_default_int(settings, "source_width", 1920)
    obs.obs_data_set_default_int(settings, "source_height", 1080)
    obs.obs_data_set_default_int(settings, "canvas_width", 608)
    obs.obs_data_set_default_int(settings, "canvas_height", 1080)
    obs.obs_data_set_default_bool(settings, "center_viewport", false)
    obs.obs_data_set_default_int(settings, "x_offset", 0)
    obs.obs_data_set_default_int(settings, "y_offset", 0)
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

    obs.obs_properties_add_float_slider(props, "tracking_speed", "Tracking Speed", 0.01, 1.0, 0.01)

    obs.obs_properties_add_bool(props, "center_viewport", "Center Viewport in Scene")

    -- Renamed to Source Width/Height to avoid confusion with physical monitors
    local p_mon = obs.obs_properties_create()
    obs.obs_properties_add_group(props, "monitor_settings", "Source Dimensions (Input)", obs.OBS_GROUP_NORMAL, p_mon)
    obs.obs_properties_add_int(p_mon, "source_width", "Source Width (in OBS)", 100, 7680, 1)
    obs.obs_properties_add_int(p_mon, "source_height", "Source Height (in OBS)", 100, 4320, 1)
    obs.obs_properties_add_int(p_mon, "x_offset", "Cursor X Offset", -5000, 5000, 1)
    obs.obs_properties_add_int(p_mon, "y_offset", "Cursor Y Offset", -5000, 5000, 1)

    local p_can = obs.obs_properties_create()
    obs.obs_properties_add_group(props, "canvas_settings", "Viewport/Target Settings", obs.OBS_GROUP_NORMAL, p_can)
    obs.obs_properties_add_int(p_can, "canvas_width", "Target Width", 100, 7680, 1)
    obs.obs_properties_add_int(p_can, "canvas_height", "Target Height", 100, 4320, 1)

    return props
end

-- Update settings values
function script_update(s)
    settings.source_name = obs.obs_data_get_string(s, "source_name")
    settings.tracking_speed = obs.obs_data_get_double(s, "tracking_speed")
    settings.source_width = obs.obs_data_get_int(s, "source_width")
    settings.source_height = obs.obs_data_get_int(s, "source_height")
    settings.canvas_width = obs.obs_data_get_int(s, "canvas_width")
    settings.canvas_height = obs.obs_data_get_int(s, "canvas_height")
    settings.center_viewport = obs.obs_data_get_bool(s, "center_viewport")
    settings.x_offset = obs.obs_data_get_int(s, "x_offset")
    settings.y_offset = obs.obs_data_get_int(s, "y_offset")

    -- Invalidate cache when settings change
    cached_scene_item = nil
end

-- Event handler to invalidate cache on scene changes
function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED or
       event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED or
       event == obs.OBS_FRONTEND_EVENT_STUDIO_MODE_ENABLED or
       event == obs.OBS_FRONTEND_EVENT_STUDIO_MODE_DISABLED or
       event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED then
        cached_scene_item = nil
    end
end

-- Initialize X11 connection
function script_load(settings)
    -- Add event callback for cache management
    obs.obs_frontend_add_event_callback(on_event)

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
        obs.script_log(obs.LOG_WARNING, "CRITICAL: Could not load libX11.")
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

    if result == 0 then return end

    local mouse_x_raw = root_x[0] - settings.x_offset
    local mouse_y_raw = root_y[0] - settings.y_offset

    -- 2. Calculate Target Position (Relative to 0,0 of the Viewport)
    local desired_source_x = (settings.canvas_width / 2) - mouse_x_raw
    local desired_source_y = (settings.canvas_height / 2) - mouse_y_raw

    -- 3. Clamp the movement (Ensure source covers the viewport)
    local min_x = settings.canvas_width - settings.source_width
    local max_x = 0
    if desired_source_x > max_x then desired_source_x = max_x end
    if desired_source_x < min_x then desired_source_x = min_x end

    local min_y = settings.canvas_height - settings.source_height
    local max_y = 0
    if desired_source_y > max_y then desired_source_y = max_y end
    if desired_source_y < min_y then desired_source_y = min_y end

    -- 4. Apply Smoothing (Lerp)
    -- If the camera is practically already there, skip the update logic to save CPU
    if math.abs(current_x - desired_source_x) < 0.5 and math.abs(current_y - desired_source_y) < 0.5 then
        return
    end

    local fps_mult = seconds * 60
    local t = math.min(1.0, settings.tracking_speed * fps_mult)

    current_x = lerp(current_x, desired_source_x, t)
    current_y = lerp(current_y, desired_source_y, t)

    -- 5. Calculate Final Position (Add Scene Centering Offset if enabled)
    local final_x = current_x
    local final_y = current_y

    if settings.center_viewport then
        local video_info = obs.obs_video_info()
        if obs.obs_get_video_info(video_info) then
            local base_width = video_info.base_width
            local base_height = video_info.base_height

            -- Offset so the target viewport is centered in the base canvas
            final_x = final_x + (base_width - settings.canvas_width) / 2
            final_y = final_y + (base_height - settings.canvas_height) / 2
        end
    end

    -- 6. Apply to OBS Scene Item

    -- If we have a cached item, verify it's still valid
    if cached_scene_item then
        if obs.obs_sceneitem_get_source(cached_scene_item) == nil then
            cached_scene_item = nil -- Item was deleted or became invalid
        end
    end

    -- If no valid cache, find the item
    if not cached_scene_item then
        local scene_source = nil

        -- Support for Studio Mode: Prefer Preview scene if active
        if obs.obs_frontend_preview_program_mode_active() then
            scene_source = obs.obs_frontend_get_current_preview_scene()
        else
            scene_source = obs.obs_frontend_get_current_scene()
        end

        if scene_source ~= nil then
            local scene = obs.obs_scene_from_source(scene_source)
            if scene ~= nil then
                -- Direct scene lookup (removed redundant obs_get_source_by_name)
                local item = obs.obs_scene_find_source(scene, settings.source_name)
                if item ~= nil then
                    cached_scene_item = item
                end
            end
            obs.obs_source_release(scene_source)
        end
    end

    -- Apply movement if item is found
    if cached_scene_item then
        local pos = obs.vec2()
        pos.x = final_x
        pos.y = final_y
        obs.obs_sceneitem_set_pos(cached_scene_item, pos)
    end
end