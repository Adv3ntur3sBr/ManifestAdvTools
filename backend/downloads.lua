local m_utils          = require("utils")
local fs               = require("fs")
local http_client      = require("http_client")
local config           = require("config")
local logger           = require("plugin_logger")
local paths            = require("paths")
local steam_utils      = require("steam_utils")
local utils            = require("plugin_utils")
local api_manifest     = require("api_manifest")
local settings_manager = require("settings.manager")
local cjson            = require("json")
local bg_job           = require("bg_job")
local fixes            = require("fixes")

local downloads = {}
local DOWNLOAD_STATE = {}

local function _set_download_state(appid, update)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return end
    if not DOWNLOAD_STATE[appid] then DOWNLOAD_STATE[appid] = {} end
    for k, v in pairs(update) do
        DOWNLOAD_STATE[appid][k] = v
    end
end

local function _get_download_state(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return {} end
    local state = DOWNLOAD_STATE[appid] or {}
    local copy = {}
    for k, v in pairs(state) do copy[k] = v end
    return copy
end

function downloads._finalize_install_lua(appid, extract_dir, dest_path, api_name)
    _set_download_state(appid, { status = "processing" })
    local base_path = steam_utils.detect_steam_install_path()
    local target_dir = fs.join(base_path, "config", "stplug-in")
    if not fs.exists(target_dir) then fs.create_directories(target_dir) end

    local depot_cache = fs.join(base_path, "depotcache")
    if not fs.exists(depot_cache) then fs.create_directories(depot_cache) end

    local target_lua = fs.join(target_dir, tostring(appid) .. ".lua")
    local extracted_lua_path = nil

    local success_list, files = pcall(fs.list_recursive, extract_dir)
    if success_list and files then
        for _, entry in ipairs(files) do
            if entry.is_directory then goto continue end
            if entry.name:match("%.manifest$") then
                local dest_man = fs.join(depot_cache, entry.name)
                local content = m_utils.read_file(entry.path)
                if content then m_utils.write_file(dest_man, content) end
            end
            if entry.name == tostring(appid) .. ".lua" then
                extracted_lua_path = entry.path
            elseif not extracted_lua_path and entry.name:match("^%d+%.lua$") then
                extracted_lua_path = entry.path
            end
            ::continue::
        end
    end

    if extracted_lua_path and fs.exists(extracted_lua_path) then
        local text = m_utils.read_file(extracted_lua_path)
        if text then
            local new_lines = {}
            for line in text:gmatch("([^\n]*)\n?") do
                if line:match("^%s*setManifestid%(") then
                    line = line:gsub("^(%s*)(setManifestid)", "%1-- %2")
                end
                table.insert(new_lines, line)
            end
            if new_lines[#new_lines] == "" then table.remove(new_lines) end
            text = table.concat(new_lines, "\n")
            m_utils.write_file(target_lua, text)
            _set_download_state(appid, { installedPath = target_lua })
        end
    end

    pcall(fs.remove_all, extract_dir)
    pcall(fs.remove, dest_path)
    _set_download_state(appid, { status = "done", success = true, api = api_name })
end

function downloads.get_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = true, state = { status = "done" } } end

    local job_id = tostring(appid)
    local state = bg_job.read_state(job_id)

    if state.status then
        _set_download_state(appid, { status = state.status, error = state.error })

        if state.status == "extracted" then
            local dest_root = utils.ensure_temp_download_dir()
            local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
            local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
            local apiName = _get_download_state(appid).currentApi or "Unknown"

            local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
            if not ok then
                _set_download_state(appid, { status = "failed", error = tostring(res) })
            end
            bg_job.cleanup(job_id, false)
        elseif state.status == "failed" or state.status == "cancelled" then
            bg_job.cleanup(job_id, false)
        end
    end

    return { success = true, state = _get_download_state(appid) }
end

function downloads.cancel_add(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = true } end

    bg_job.cancel(tostring(appid), "Cancelled by user")
    bg_job.cancel("fix_" .. tostring(appid), "Cancelled by user")
    _set_download_state(appid, { status = "cancelled", error = "Cancelled by user" })
    return { success = true }
end

function downloads.start_add_via_luatools_from_url(appid, url, apiName)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    if not url or url == "" then
        url, apiName = downloads.find_manifest_url_for_app(appid)
        if not url or url == "" then
            _set_download_state(appid, { status = "failed", error = "Manifesto não encontrado para este jogo" })
            return { success = false, error = "Manifesto não encontrado para este jogo em nenhuma das APIs ativas" }
        end
    end
    apiName = apiName or "ManifestAdvTools"

    logger.log("downloads: start_add_via_luatools_from_url appid=" .. tostring(appid) .. " api=" .. tostring(apiName))
    _set_download_state(appid, { status = "downloading", currentApi = apiName, bytesRead = 0, totalBytes = 0 })

    local dest_root = utils.ensure_temp_download_dir()
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))

    local ok, err = pcall(bg_job.launch, {
        id = tostring(appid),
        url = url,
        extract_dir = extract_dir,
        record_files = false,
        user_agent = "ManifestAdvTools"
    })

    if not ok then
        logger.warn("downloads: launch failed: " .. tostring(err))
        _set_download_state(appid, { status = "failed", error = tostring(err) })
        return { success = false, error = tostring(err) }
    end

    return { success = true }
end

function downloads.find_manifest_url_for_app(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return nil, nil end

    local check_res = downloads.check_apis_for_app(appid)
    if check_res and check_res.results then
        for _, r in ipairs(check_res.results) do
            if r.available and r.url and r.url ~= "" then
                return r.url, r.name
            end
        end
    end
    return nil, nil
end

function downloads.start_add_via_luatools(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    logger.log("downloads: start_add_via_luatools appid=" .. tostring(appid))
    _set_download_state(appid, { status = "queued", bytesRead = 0, totalBytes = 0 })

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        _set_download_state(appid, { status = "failed", error = "No APIs available" })
        return { success = true }
    end

    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    local target_url = nil
    local target_name = nil

    for _, api in ipairs(apis) do
        local name = api.name or "Unknown"
        local template = api.url or ""
        local success_code = tonumber(api.success_code) or 200

        if string.find(template, "<moapikey>") then
            if not morrenus_api_key or morrenus_api_key == "" then goto continue end
            template = template:gsub("<moapikey>", morrenus_api_key)
        end
        if string.find(template, "<apikey>") then
            if not api.api_key or api.api_key == "" then goto continue end
            template = template:gsub("<apikey>", api.api_key)
        end

        local url = template:gsub("<appid>", tostring(appid))
        local success = false

        if string.lower(name) == "morrenus" then
            local status_url = "https://hubcapmanifest.com/api/v1/status/" .. tostring(appid) .. "?api_key=" .. tostring(morrenus_api_key)
            local s_resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
            if s_resp and s_resp.status == success_code then
                success = true
            end
        else
            local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
            if resp and resp.status == success_code then
                success = true
            else
                local get_resp = http_client.get(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
                if get_resp and get_resp.status == success_code then
                    success = true
                end
            end
        end

        if success then
            target_url = url
            target_name = name
            break
        end
        ::continue::
    end

    if not target_url then
        _set_download_state(appid, { status = "failed", error = "Not available on any API" })
        return { success = false, error = "Not available on any API" }
    end

    return downloads.start_add_via_luatools_from_url(appid, target_url, target_name)
end

function downloads.check_apis_for_app(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        return { success = true, results = {} }
    end

    local results = {}
    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    for _, api in ipairs(apis) do
        local name = api.name or "Unknown"
        local template = api.url or ""
        local success_code = tonumber(api.success_code) or 200

        if string.find(template, "<moapikey>") then
            if not morrenus_api_key or morrenus_api_key == "" then
                goto continue
            end
            template = template:gsub("<moapikey>", morrenus_api_key)
        end
        if string.find(template, "<apikey>") then
            if not api.api_key or api.api_key == "" then
                goto continue
            end
            template = template:gsub("<apikey>", api.api_key)
        end

        local url = template:gsub("<appid>", tostring(appid))
        local available = false

        if string.lower(name) == "morrenus" then
            local status_url = "https://hubcapmanifest.com/api/v1/status/" .. tostring(appid) .. "?api_key=" .. tostring(morrenus_api_key)
            local resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
            if resp and resp.status == success_code then
                available = true
            end
        else
            local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
            if resp and resp.status == success_code then
                available = true
            else
                local get_resp = http_client.get(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
                if get_resp and get_resp.status == success_code then
                    available = true
                end
            end
        end

        table.insert(results, {
            name = name,
            available = available,
            url = available and url or nil
        })

        ::continue::
    end

    return { success = true, results = results }
end

function downloads.start_add_with_online_fix(appid, manifest_url, api_name, install_path)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    if not manifest_url or manifest_url == "" then
        manifest_url, api_name = downloads.find_manifest_url_for_app(appid)
        if not manifest_url or manifest_url == "" then
            return { success = false, error = "Manifesto não encontrado para este jogo em nenhuma das APIs ativas" }
        end
    end
    api_name = api_name or "ManifestAdvTools"

    logger.log("downloads: Bundle download appid=" .. tostring(appid) .. " manifest=" .. tostring(manifest_url))
    _set_download_state(appid, { status = "downloading", currentApi = api_name, isBundleDownload = true })

    local dest_root = utils.ensure_temp_download_dir()
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))

    -- Check for OnlineFix availability
    local ONLINE_FIX_BASE = "https://files.luatools.work/OnlineFix1/"
    local candidate_urls = {
        ONLINE_FIX_BASE .. tostring(appid) .. ".zip",
        "https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/onlinefix/" .. tostring(appid) .. ".zip"
    }

    local fix_url = nil
    for _, curl in ipairs(candidate_urls) do
        local fix_resp = http_client.get(curl, { timeout = 5, method = "HEAD" })
        if fix_resp and (fix_resp.status == 200 or fix_resp.status == 301 or fix_resp.status == 302) then
            fix_url = curl
            break
        end
    end

    local fix_install = install_path or fs.join(
        steam_utils.detect_steam_install_path(), "steamapps", "common", tostring(appid)
    )

    -- Launch manifest download
    bg_job.launch({
        id = tostring(appid),
        url = manifest_url,
        extract_dir = extract_dir,
        record_files = false,
        user_agent = "ManifestAdvTools"
    })

    if fix_url then
        fixes.apply_game_fix(appid, fix_url, fix_install, "Online Fix", "")
        return { success = true, isBundleDownload = true, fixUrl = fix_url }
    else
        bg_job.write_state("fix_" .. tostring(appid), { status = "not_available" })
        return { success = true, isBundleDownload = true, fixAvailable = false }
    end
end

function downloads.get_bundle_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = true, state = { status = "done" } } end

    local job_id = tostring(appid)
    local fix_job_id = "fix_" .. tostring(appid)

    local ms = bg_job.read_state(job_id)
    local fs_ = bg_job.read_state(fix_job_id)

    local m_status = ms.status or "done"
    local f_status = fs_.status or "done"

    if m_status == "extracted" then
        local dest_root  = utils.ensure_temp_download_dir()
        local dest_path  = fs.join(dest_root, tostring(appid) .. ".zip")
        local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
        local apiName = _get_download_state(appid).currentApi or "OnlineFix Bundle"

        local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
        if not ok then
            _set_download_state(appid, { status = "failed", error = tostring(res) })
        end
        bg_job.cleanup(job_id, false)
        m_status = "done"
    elseif m_status == "failed" then
        bg_job.cleanup(job_id, false)
    end

    if f_status == "extracted" then
        fixes.get_apply_status(appid) -- registers the fix
        f_status = "done"
    elseif f_status == "failed" then
        bg_job.cleanup(fix_job_id, false)
    end

    local combined
    if m_status == "failed" then
        combined = "failed"
    elseif m_status == "cancelled" or f_status == "cancelled" then
        combined = "cancelled"
    elseif m_status == "done" and (f_status == "done" or f_status == "not_available") then
        combined = "done"
        _set_download_state(appid, { status = "done", success = true, hadOnlineFix = (f_status == "done") })
    elseif m_status == "extracting" or f_status == "extracting" then
        combined = "extracting"
    else
        combined = "downloading"
    end

    return {
        success = true,
        state = {
            status = combined,
            manifest = m_status,
            fix = f_status
        }
    }
end

return downloads
