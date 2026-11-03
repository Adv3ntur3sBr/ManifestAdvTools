local m_utils = require("utils")
local millennium = require("millennium")
local fs = require("fs")
local logger = require("plugin_logger")
local paths = require("paths")
local cjson = require("json")

local steam_utils = {}

local STEAM_INSTALL_PATH = nil

local IGNORED_APPIDS = {
    [228980]  = true, -- Steamworks Common Redistributables
    [250820]  = true, -- SteamVR
    [1070560] = true, -- Steam Linux Runtime
    [1391110] = true, -- Steam Linux Runtime - Soldier
    [1628350] = true, -- Steam Linux Runtime - Sniper
    [1493710] = true, -- Proton Experimental
    [1887720] = true, -- Proton 7.0
    [2180100] = true, -- Proton Hotfix
    [2348590] = true, -- Proton 8.0
    [2805730] = true, -- Proton 9.0
}

function steam_utils.detect_steam_install_path()
    if STEAM_INSTALL_PATH then return STEAM_INSTALL_PATH end
    local success, path = pcall(millennium.steam_path)
    if success and path then
        STEAM_INSTALL_PATH = path
        logger.log("ManifestAdvTools: Steam install path set to " .. tostring(STEAM_INSTALL_PATH))
        return STEAM_INSTALL_PATH
    end
    return ""
end

function steam_utils.has_lua_for_app(appid)
    local base_path = steam_utils.detect_steam_install_path()
    if not base_path or base_path == "" then return false end

    local stplug_path = fs.join(base_path, "config", "stplug-in")
    local lua_file = fs.join(stplug_path, tostring(appid) .. ".lua")
    local disabled_file = fs.join(stplug_path, tostring(appid) .. ".lua.disabled")

    return fs.exists(lua_file) or fs.exists(disabled_file)
end

function steam_utils.get_all_library_paths()
    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then return {} end

    local seen = {}
    local all_library_paths = {}
    local function add_path(p)
        if not p or p == "" then return end
        p = p:gsub("\\\\", "\\")
        local key = p:lower():gsub("[/\\]+$", "")
        if not seen[key] then
            seen[key] = true
            table.insert(all_library_paths, p)
        end
    end

    local candidates = {
        fs.join(steam_path, "config", "libraryfolders.vdf"),
        fs.join(steam_path, "steamapps", "libraryfolders.vdf")
    }
    for _, vdf_path in ipairs(candidates) do
        if fs.exists(vdf_path) then
            local vdf_content = m_utils.read_file(vdf_path)
            if vdf_content then
                for path in vdf_content:gmatch('"path"%s+"([^"]+)"') do
                    add_path(path)
                end
            end
        end
    end
    add_path(steam_path)
    return all_library_paths
end

function steam_utils.get_game_install_path_response(appid)
    appid = tostring(appid)
    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then
        return { success = false, error = "Could not find Steam installation path" }
    end

    local all_library_paths = steam_utils.get_all_library_paths()
    if #all_library_paths == 0 then
        return { success = false, error = "Could not find libraryfolders.vdf" }
    end

    local library_path = nil
    local appmanifest_path = nil

    for _, lib_path in ipairs(all_library_paths) do
        local candidate = fs.join(lib_path, "steamapps", "appmanifest_" .. appid .. ".acf")
        if fs.exists(candidate) then
            library_path = lib_path
            appmanifest_path = candidate
            break
        end
    end

    if not library_path or not appmanifest_path then
        return { success = false, error = "menu.error.notInstalled" }
    end

    local manifest_content = m_utils.read_file(appmanifest_path)
    if not manifest_content then
        return { success = false, error = "Failed to parse appmanifest" }
    end

    local install_dir = manifest_content:match('"installdir"%s+"([^"]+)"')
    if not install_dir then
        return { success = false, error = "Install directory not found" }
    end

    local full_install_path = fs.join(library_path, "steamapps", "common", install_dir)
    if not fs.exists(full_install_path) then
        return { success = false, error = "Game directory not found" }
    end

    return {
        success = true,
        installPath = full_install_path,
        installDir = install_dir,
        libraryPath = library_path,
        path = full_install_path
    }
end

function steam_utils.get_installed_games_for_verify(owned_json)
    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then
        return { success = false, error = "Steam path not found" }
    end

    local owned_map = {}
    if type(owned_json) == "string" and owned_json ~= "" then
        local ok, arr = pcall(cjson.decode, owned_json)
        if ok and type(arr) == "table" then
            for _, id in ipairs(arr) do
                local n = tonumber(id)
                if n then owned_map[n] = true end
            end
        end
    elseif type(owned_json) == "table" then
        for _, id in ipairs(owned_json) do
            local n = tonumber(id)
            if n then owned_map[n] = true end
        end
    end

    local all_library_paths = steam_utils.get_all_library_paths()
    local depot_cache = fs.join(steam_path, "depotcache")
    local games = {}
    local seen_apps = {}

    for _, lib_path in ipairs(all_library_paths) do
        local steamapps_dir = fs.join(lib_path, "steamapps")
        if fs.exists(steamapps_dir) then
            local ok_l, entries = pcall(fs.list, steamapps_dir)
            if ok_l and type(entries) == "table" then
                for _, entry in ipairs(entries) do
                    local fname = type(entry) == "table" and (entry.name or "") or tostring(entry or "")
                    fname = fname:match("([^/\\]+)$") or fname
                    local appid_str = fname:match("^appmanifest_(%d+)%.acf$")
                    if appid_str then
                        local appid_num = tonumber(appid_str)
                        if appid_num and not IGNORED_APPIDS[appid_num] and not seen_apps[appid_num] and not owned_map[appid_num] then
                            local acf_path = type(entry) == "table" and entry.path or fs.join(steamapps_dir, fname)
                            local content = m_utils.read_file(acf_path)
                            if content then
                                local name = content:match('"name"%s+"([^"]+)"') or ("App " .. appid_str)
                                local install_dir = content:match('"installdir"%s+"([^"]+)"')
                                local lower_name = name:lower()
                                local is_tool = lower_name:find("^proton ") ~= nil
                                    or lower_name:find("^steam linux runtime") ~= nil
                                    or lower_name:find("redistributable") ~= nil

                                if not is_tool and install_dir and install_dir ~= "" then
                                    local common_dir = fs.join(steamapps_dir, "common", install_dir)
                                    if fs.exists(common_dir) then
                                        seen_apps[appid_num] = true
                                        local has_lua = steam_utils.has_lua_for_app(appid_num)
                                        local total_manifests = 0
                                        local missing_manifests = 0
                                        local installed_depots_block = content:match('"InstalledDepots"%s*(%b{})')
                                        if installed_depots_block then
                                            for depot_id, depot_body in installed_depots_block:gmatch('"(%d+)"%s*(%b{})') do
                                                local man_id = depot_body:match('"manifest"%s+"(%d+)"')
                                                if man_id then
                                                    total_manifests = total_manifests + 1
                                                    local man_file = fs.join(depot_cache, depot_id .. "_" .. man_id .. ".manifest")
                                                    if not fs.exists(man_file) then
                                                        missing_manifests = missing_manifests + 1
                                                    end
                                                end
                                            end
                                        end

                                        table.insert(games, {
                                            appid = appid_num,
                                            name = name,
                                            installDir = install_dir,
                                            libraryPath = lib_path,
                                            hasLua = has_lua,
                                            totalManifests = total_manifests,
                                            missingManifests = missing_manifests,
                                            needsRestore = (not has_lua) or (missing_manifests > 0)
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(games, function(a, b)
        if a.needsRestore ~= b.needsRestore then
            return a.needsRestore == true
        end
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)

    return {
        success = true,
        games = games
    }
end

function steam_utils.try_synthesize_local_lua(appid)
    appid = tonumber(appid)
    if not appid then return false end
    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then return false end

    local all_library_paths = steam_utils.get_all_library_paths()
    local acf_content = nil
    for _, lib_path in ipairs(all_library_paths) do
        local candidate = fs.join(lib_path, "steamapps", "appmanifest_" .. tostring(appid) .. ".acf")
        if fs.exists(candidate) then
            acf_content = m_utils.read_file(candidate)
            if acf_content then break end
        end
    end
    if not acf_content then return false end

    local depots = {}
    local installed_depots_block = acf_content:match('"InstalledDepots"%s*(%b{})')
    if installed_depots_block then
        for depot_id, depot_body in installed_depots_block:gmatch('"(%d+)"%s*(%b{})') do
            local man_id = depot_body:match('"manifest"%s+"(%d+)"')
            table.insert(depots, { depotId = depot_id, manifestId = man_id })
        end
    end
    if #depots == 0 then return false end

    local depot_keys = {}
    local config_vdf = fs.join(steam_path, "config", "config.vdf")
    if fs.exists(config_vdf) then
        local cfg_text = m_utils.read_file(config_vdf)
        if cfg_text then
            for d_id, d_body in cfg_text:gmatch('"(%d+)"%s*(%b{})') do
                local d_key = d_body:match('"[Dd]ecryption[Kk]ey"%s+"([0-9a-fA-F]+)"')
                if d_key and #d_key == 64 then
                    depot_keys[d_id] = d_key
                end
            end
        end
    end

    local lines = { string.format("addappid(%d)", appid) }
    for _, d in ipairs(depots) do
        local k = depot_keys[d.depotId]
        if k then
            table.insert(lines, string.format('addappid(%s, 1, "%s")', d.depotId, k))
        else
            table.insert(lines, string.format("addappid(%s)", d.depotId))
        end
        if d.manifestId then
            table.insert(lines, string.format('-- setManifestid(%s, "%s", 0)', d.depotId, d.manifestId))
        end
    end

    local target_dir = fs.join(steam_path, "config", "stplug-in")
    if not fs.exists(target_dir) then pcall(fs.create_directories, target_dir) end
    local target_lua = fs.join(target_dir, tostring(appid) .. ".lua")
    m_utils.write_file(target_lua, table.concat(lines, "\n") .. "\n")
    return fs.exists(target_lua)
end

function steam_utils.open_game_folder(path)
    if not path or path == "" or not fs.exists(path) then return false end

    -- In Windows, explorer accepts backslashes
    path = path:gsub("/", "\\")
    local cmd = 'explorer "' .. path .. '"'
    m_utils.exec(cmd)
    return true
end

return steam_utils
