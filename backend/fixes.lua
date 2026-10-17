local m_utils     = require("utils")
local fs          = require("fs")
local http_client = require("http_client")
local logger      = require("plugin_logger")
local utils       = require("plugin_utils")
local paths       = require("paths")
local cjson       = require("json")
local bg_job      = require("bg_job")

local fixes = {}

local INSTALLED_FIXES_FILE = paths.backend_path("data/installed_fixes.json")
local IN_FLIGHT_FIXES = {}
local UNFIX_STATES = {}

local function _load_installed_fixes()
    if not fs.exists(INSTALLED_FIXES_FILE) then return {} end
    local data = utils.read_json(INSTALLED_FIXES_FILE)
    if type(data) == "table" and type(data.fixes) == "table" then
        return data.fixes
    end
    return {}
end

local function _save_installed_fixes(list)
    local dir = fs.parent_path(INSTALLED_FIXES_FILE)
    if not fs.exists(dir) then fs.create_directories(dir) end
    utils.write_json(INSTALLED_FIXES_FILE, { fixes = list })
end

function fixes.check_for_fixes(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local result = {
        success = true,
        appid = appid,
        gameName = "Unknown Game (" .. tostring(appid) .. ")",
        genericFix = { status = 0, available = false },
        onlineFix = { status = 0, available = false }
    }

    local FIXES_INDEX_URL = "https://index.luatools.work/fixes-index.json"
    local resp = http_client.get(FIXES_INDEX_URL, { timeout = 10 })
    if resp and resp.status == 200 and resp.body then
        local data = utils.decode_json(resp.body)
        if type(data) == "table" then
            local generic_url = "https://files.luatools.work/GameBypasses/" .. tostring(appid) .. ".zip"
            local online_url  = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip"

            local has_generic = false
            for _, v in ipairs(data.genericFixes or {}) do
                if tonumber(v) == appid then has_generic = true; break end
            end
            if has_generic then
                result.genericFix.status = 200
                result.genericFix.available = true
                result.genericFix.url = generic_url
            else
                result.genericFix.status = 404
            end

            local has_online = false
            for _, v in ipairs(data.onlineFixes or {}) do
                if tonumber(v) == appid then has_online = true; break end
            end
            if has_online then
                result.onlineFix.status = 200
                result.onlineFix.available = true
                result.onlineFix.url = online_url
            else
                result.onlineFix.status = 404
            end
        end
    end

    return result
end

function fixes.apply_game_fix(appid, download_url, install_path, fix_type, game_name)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    if not download_url or download_url == "" then
        return { success = false, error = "Missing downloadUrl" }
    end
    if not install_path or install_path == "" then
        return { success = false, error = "Missing installPath" }
    end

    logger.log("fixes: Applying " .. tostring(fix_type) .. " for " .. tostring(appid) .. " to " .. tostring(install_path))

    local job_id = "fix_" .. tostring(appid)
    IN_FLIGHT_FIXES[appid] = {
        appid = appid,
        gameName = (game_name and game_name ~= "") and game_name or ("Game (" .. appid .. ")"),
        fixType = (fix_type and fix_type ~= "") and fix_type or "Generic Fix",
        installPath = install_path,
        url = download_url,
        date = os.date("%Y-%m-%d"),
    }

    local ok, err = pcall(bg_job.launch, {
        id = job_id,
        url = download_url,
        extract_dir = install_path,
        record_files = true,
        user_agent = "ManifestAdvTools"
    })

    if not ok then
        logger.warn("fixes: Failed to launch bg_job: " .. tostring(err))
        return { success = false, error = tostring(err) }
    end

    return { success = true }
end

function fixes.get_apply_status(appid)
    appid = tonumber(appid)
    if not appid then return { success = true, state = { status = "done" } } end

    local job_id = "fix_" .. tostring(appid)
    local state = bg_job.read_state(job_id)
    if not state.status then
        return { success = true, state = { status = "done" } }
    end

    if state.status == "extracted" then
        -- Finalize fix registration
        local recorded_files = bg_job.read_file_list(job_id)
        local meta = IN_FLIGHT_FIXES[appid] or {}
        local list = _load_installed_fixes()

        -- Remove existing record for this appid if replacing
        local new_list = {}
        for _, f in ipairs(list) do
            if f.appid ~= appid then
                table.insert(new_list, f)
            end
        end

        table.insert(new_list, {
            appid       = appid,
            gameName    = meta.gameName or ("Game (" .. appid .. ")"),
            fixType     = meta.fixType or "Generic Fix",
            date        = meta.date or os.date("%Y-%m-%d"),
            installPath = meta.installPath or "",
            filesCount  = #recorded_files,
            files       = recorded_files
        })
        _save_installed_fixes(new_list)

        bg_job.cleanup(job_id, false)
        IN_FLIGHT_FIXES[appid] = nil

        return { success = true, state = { status = "done" } }
    elseif state.status == "failed" then
        local err = state.error or "fix download/extract failed"
        bg_job.cleanup(job_id, false)
        IN_FLIGHT_FIXES[appid] = nil
        return { success = true, state = { status = "failed", error = err } }
    elseif state.status == "cancelled" then
        bg_job.cleanup(job_id, false)
        IN_FLIGHT_FIXES[appid] = nil
        return { success = true, state = { status = "cancelled", error = state.error or "Cancelled by user" } }
    end

    return { success = true, state = state }
end

function fixes.cancel_apply_fix(appid)
    appid = tonumber(appid)
    if appid then
        bg_job.cancel("fix_" .. tostring(appid), "Cancelled by user")
        IN_FLIGHT_FIXES[appid] = nil
    end
    return { success = true }
end

function fixes.get_installed_fixes()
    local list = _load_installed_fixes()
    return { success = true, fixes = list }
end

function fixes.unfix_game(appid, install_path, fix_date)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end

    UNFIX_STATES[appid] = { status = "removing", progress = "Removing fix files..." }

    local list = _load_installed_fixes()
    local found = nil
    local remaining = {}

    for _, fix_item in ipairs(list) do
        if fix_item.appid == appid then
            found = fix_item
        else
            table.insert(remaining, fix_item)
        end
    end

    local path = (install_path and install_path ~= "") and install_path or (found and found.installPath or "")
    local removed_count = 0

    if found and type(found.files) == "table" and path ~= "" and fs.exists(path) then
        for _, rel_file in ipairs(found.files) do
            local full_path = fs.join(path, rel_file)
            if fs.exists(full_path) then
                local ok = pcall(fs.remove, full_path)
                if ok then removed_count = removed_count + 1 end
            end
        end
    end

    _save_installed_fixes(remaining)

    UNFIX_STATES[appid] = {
        status = "done",
        success = true,
        filesRemoved = removed_count
    }

    return { success = true, filesRemoved = removed_count }
end

function fixes.uninstall_fix(appid)
    return fixes.unfix_game(appid)
end

function fixes.get_unfix_status(appid)
    appid = tonumber(appid)
    local state = UNFIX_STATES[appid] or { status = "done", success = true, filesRemoved = 0 }
    return { success = true, state = state }
end

return fixes
