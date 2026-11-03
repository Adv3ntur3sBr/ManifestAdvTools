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
local CANCELLED_APPS = {}

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

-- Validate HTTP response so soft-404 HTML pages, Cloudflare challenges, or JSON errors
-- returning HTTP 200 are never treated as valid manifest archives.
-- Returns: is_valid (bool), resolved_url (string)
local function _validate_manifest_response(resp, url)
    if not resp then return false, url end

    if type(resp.headers) == "table" then
        for hk, hv in pairs(resp.headers) do
            if tostring(hk):lower() == "content-type" then
                local ct = tostring(hv):lower()
                if ct:find("text/html", 1, true) or ct:find("application/json", 1, true) or ct:find("application/problem", 1, true) then
                    return false, url
                end
            end
        end
    end

    local body = resp.body
    if type(body) == "string" and #body > 0 then
        -- Git LFS pointer check
        if #body < 512 and body:sub(1, 40):find("version https://git-lfs.github.com", 1, true) then
            local owner, repo, branch, path = url:match("^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/(?:refs/heads/)?([^/]+)/(.+)$")
            if not owner then
                owner, repo, branch, path = url:match("^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/refs/heads/([^/]+)/(.+)$")
            end
            if not owner then
                owner, repo, branch, path = url:match("^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
            end
            if owner and repo and branch and path then
                return true, "https://media.githubusercontent.com/media/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. path
            end
            return false, url
        end

        -- Magic bytes: ZIP ("PK"), Gzip (\31\139), 7z ("7z\188\175"), RAR ("Rar!")
        local b2 = body:sub(1, 2)
        local b4 = body:sub(1, 4)
        if b2 == "PK" or b2 == "\31\139" or b4 == "7z\188\175" or b4 == "Rar!" then
            return true, url
        end

        -- Raw .lua script check
        local head_lower = body:sub(1, 512):lower()
        if not head_lower:find("<!doctype", 1, true) and not head_lower:find("<html", 1, true) then
            if body:find("addappid%s*%(") or body:find("setManifestid%s*%(") then
                return true, url
            end
        end

        -- Non-empty body that isn't a valid archive or .lua script (e.g. HTML/JSON/text error)
        return false, url
    end

    return true, url
end

function downloads._finalize_install_lua(appid, extract_dir, dest_path, api_name)
    _set_download_state(appid, { status = "processing" })
    local base_path = steam_utils.detect_steam_install_path()
    local target_dir = fs.join(base_path, "config", "stplug-in")
    if not fs.exists(target_dir) then pcall(fs.create_directories, target_dir) end

    local depot_cache = fs.join(base_path, "depotcache")
    if not fs.exists(depot_cache) then pcall(fs.create_directories, depot_cache) end

    local target_lua = fs.join(target_dir, tostring(appid) .. ".lua")

    if not fs.exists(target_lua) then
        local extracted_lua_path = nil
        local success_list, files = pcall(fs.list_recursive, extract_dir)
        if success_list and files then
            for _, entry in ipairs(files) do
                if entry.is_directory then goto continue end
                if entry.name:match("%.manifest$") then
                    local dest_man = fs.join(depot_cache, entry.name)
                    if not fs.exists(dest_man) then
                        local content = m_utils.read_file(entry.path)
                        if content then m_utils.write_file(dest_man, content) end
                    end
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
            end
        end
    end

    if fs.exists(target_lua) then
        _set_download_state(appid, { installedPath = target_lua })
    end

    pcall(fs.remove_all, extract_dir)
    pcall(fs.remove, dest_path)
    _set_download_state(appid, {
        status = "done",
        success = true,
        api = api_name,
        currentApi = api_name,
        bytesRead = 100,
        totalBytes = 100
    })
end

function downloads.get_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = true, state = { status = "done" } } end

    local job_id = tostring(appid)
    local state = bg_job.read_state(job_id)

    if state.status then
        local upd = {
            status = state.status,
            error = state.error,
            bytesRead = state.bytesRead or 50,
            totalBytes = state.totalBytes or 100
        }
        if state.currentApi and state.currentApi ~= "" then
            upd.currentApi = state.currentApi
        end
        _set_download_state(appid, upd)

        if state.status == "extracted" then
            local dest_root = utils.ensure_temp_download_dir()
            local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
            local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
            local apiName = (state.currentApi and state.currentApi ~= "") and state.currentApi or (_get_download_state(appid).currentApi or "Unknown")

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

    CANCELLED_APPS[appid] = true
    bg_job.cancel(tostring(appid), "Cancelled by user")
    bg_job.cancel("fix_" .. tostring(appid), "Cancelled by user")
    _set_download_state(appid, { status = "cancelled", error = "Cancelled by user" })
    return { success = true }
end

function downloads.start_add_via_luatools_from_url(appid, url, apiName)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end
    CANCELLED_APPS[appid] = nil

    if not url or url == "" then
        url, apiName = downloads.find_manifest_url_for_app(appid)
        if not url or url == "" then
            _set_download_state(appid, { status = "failed", error = "Manifesto não encontrado para este jogo" })
            return { success = false, error = "Manifesto não encontrado para este jogo em nenhuma das APIs ativas" }
        end
    end
    apiName = (apiName and apiName ~= "") and apiName or "ManifestAdvTools"

    -- Build ordered candidate sources list (primary selected URL first, followed by cached available sources)
    local candidate_sources = { { name = apiName, url = url } }
    local seen_urls = { [url] = true }
    local cur_state = _get_download_state(appid)
    if type(cur_state.availableSources) == "table" then
        for _, src in ipairs(cur_state.availableSources) do
            if src and src.url and not seen_urls[src.url] then
                table.insert(candidate_sources, { name = src.name or "Fallback", url = src.url })
                seen_urls[src.url] = true
            end
        end
    end

    logger.log("downloads: start_add_via_luatools_from_url appid=" .. tostring(appid) .. " api=" .. tostring(apiName) .. " candidates=" .. tostring(#candidate_sources))
    _set_download_state(appid, {
        status = "downloading",
        currentApi = apiName,
        bytesRead = 35,
        totalBytes = 100,
        error = nil
    })

    local dest_root = utils.ensure_temp_download_dir()
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local base_path = steam_utils.detect_steam_install_path() or ""
    local depot_cache = base_path ~= "" and fs.join(base_path, "depotcache") or ""
    local target_lua = base_path ~= "" and fs.join(base_path, "config", "stplug-in", tostring(appid) .. ".lua") or ""

    local ok, err = pcall(bg_job.launch, {
        id = tostring(appid),
        url = url,
        sources = candidate_sources,
        extract_dir = extract_dir,
        record_files = false,
        user_agent = "ManifestAdvTools",
        appid = appid,
        depot_cache = depot_cache,
        target_lua = target_lua
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
    _set_download_state(appid, { status = "queued", bytesRead = 15, totalBytes = 100 })

    local target_url, target_name = downloads.find_manifest_url_for_app(appid)

    if not target_url then
        -- Fallback for already-installed games: try synthesizing <appid>.lua from appmanifest + config.vdf
        local ok_syn, syn_done = pcall(steam_utils.try_synthesize_local_lua, appid)
        if ok_syn and syn_done then
            _set_download_state(appid, {
                status = "done",
                success = true,
                api = "Cache Local",
                currentApi = "Cache Local",
                bytesRead = 100,
                totalBytes = 100
            })
            return { success = true }
        end

        _set_download_state(appid, { status = "failed", error = "Not available on any API" })
        return { success = false, error = "Not available on any API" }
    end

    return downloads.start_add_via_luatools_from_url(appid, target_url, target_name)
end

function downloads.check_apis_for_app(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end
    CANCELLED_APPS[appid] = nil

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        return { success = true, results = {} }
    end

    local results = {}
    local available_sources = {}
    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    for _, api in ipairs(apis) do
        if CANCELLED_APPS[appid] then
            return { success = false, cancelled = true, error = "Cancelled by user" }
        end

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
            local resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 2 })
            if resp and resp.status == success_code then
                available = true
            end
        elseif string.find(url, "codeload%.github%.com") then
            -- Fast check for GitHub branch-per-appid repos: probe <appid>.lua via raw.githubusercontent.com first
            local owner, repo, branch = url:match("codeload%.github%.com/([^/]+)/([^/]+)/zip/refs/heads/([^/?#]+)")
            local probe_status = 0
            if owner and repo and branch then
                local probe_url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. tostring(appid) .. ".lua"
                local p_resp = http_client.head(probe_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 2 })
                probe_status = p_resp and tonumber(p_resp.status) or 0
                if probe_status == 200 then
                    available = true
                end
            end
            if not available and probe_status ~= 404 then
                local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 2 })
                if resp and resp.status == success_code then
                    local ok_v, res_u = _validate_manifest_response(resp, url)
                    if ok_v then
                        available = true
                        url = res_u
                    end
                end
            end
        else
            local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 2 })
            if resp and resp.status == success_code then
                local ok_v, res_u = _validate_manifest_response(resp, url)
                if ok_v then
                    available = true
                    url = res_u
                end
            else
                local st = resp and tonumber(resp.status) or 0
                if st == 0 or st == 405 or st == 501 then
                    local get_resp = http_client.get(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 2 })
                    if get_resp and get_resp.status == success_code then
                        local ok_v, res_u = _validate_manifest_response(get_resp, url)
                        if ok_v then
                            available = true
                            url = res_u
                        end
                    end
                end
            end
        end

        if available then
            table.insert(available_sources, { name = name, url = url })
        end

        table.insert(results, {
            name = name,
            available = available,
            url = available and url or nil
        })

        -- Once we have 3 verified available sources, stop blocking on remaining slow APIs
        if #available_sources >= 3 then
            break
        end

        ::continue::
    end

    _set_download_state(appid, { availableSources = available_sources })
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
    api_name = (api_name and api_name ~= "") and api_name or "ManifestAdvTools"

    local candidate_sources = { { name = api_name, url = manifest_url } }
    local seen_urls = { [manifest_url] = true }
    local cur_state = _get_download_state(appid)
    if type(cur_state.availableSources) == "table" then
        for _, src in ipairs(cur_state.availableSources) do
            if src and src.url and not seen_urls[src.url] then
                table.insert(candidate_sources, { name = src.name or "Fallback", url = src.url })
                seen_urls[src.url] = true
            end
        end
    end

    logger.log("downloads: Bundle download appid=" .. tostring(appid) .. " manifest=" .. tostring(manifest_url))

    local dest_root = utils.ensure_temp_download_dir()
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local base_path = steam_utils.detect_steam_install_path() or ""
    local depot_cache = base_path ~= "" and fs.join(base_path, "depotcache") or ""
    local target_lua = base_path ~= "" and fs.join(base_path, "config", "stplug-in", tostring(appid) .. ".lua") or ""

    -- Check for OnlineFix availability
    local ONLINE_FIX_BASE = "https://files.luatools.work/OnlineFix1/"
    local candidate_urls = {
        ONLINE_FIX_BASE .. tostring(appid) .. ".zip",
        "https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/onlinefix/" .. tostring(appid) .. ".zip",
        "https://raw.githubusercontent.com/sushi-dev55/sushitools-games-repo/refs/heads/main/onlinefix/" .. tostring(appid) .. ".zip"
    }

    local fix_url = nil
    for _, curl in ipairs(candidate_urls) do
        local fix_resp = http_client.head(curl, { timeout = 4 })
        if fix_resp and (fix_resp.status == 200 or fix_resp.status == 301 or fix_resp.status == 302) then
            local ok_v, res_u = _validate_manifest_response(fix_resp, curl)
            if ok_v then
                fix_url = res_u
                break
            end
        end
    end

    local fix_install = (install_path and install_path ~= "") and install_path or nil
    if not fix_install then
        local ok_p, path_res = pcall(steam_utils.get_game_install_path_response, appid)
        if ok_p and type(path_res) == "table" and path_res.success and path_res.installPath and path_res.installPath ~= "" then
            fix_install = path_res.installPath
        else
            fix_install = fs.join(base_path, "steamapps", "common", tostring(appid))
        end
    end

    _set_download_state(appid, {
        status = "downloading",
        currentApi = api_name,
        isBundleDownload = true,
        manifestDone = false,
        fixDone = (fix_url == nil),
        error = nil
    })

    -- Launch manifest download in background
    bg_job.launch({
        id = tostring(appid),
        url = manifest_url,
        sources = candidate_sources,
        extract_dir = extract_dir,
        record_files = false,
        user_agent = "ManifestAdvTools",
        appid = appid,
        depot_cache = depot_cache,
        target_lua = target_lua
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
    local cur = _get_download_state(appid)

    local ms = bg_job.read_state(job_id)
    local fs_ = bg_job.read_state(fix_job_id)

    local m_status = ms.status or (cur.manifestDone and "done" or "done")
    local f_status = fs_.status or (cur.fixDone and "not_available" or "done")

    if m_status == "extracted" then
        local dest_root  = utils.ensure_temp_download_dir()
        local dest_path  = fs.join(dest_root, tostring(appid) .. ".zip")
        local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
        local apiName = (ms.currentApi and ms.currentApi ~= "") and ms.currentApi or (cur.currentApi or "OnlineFix Bundle")

        local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
        if not ok then
            _set_download_state(appid, { status = "failed", error = tostring(res) })
        end
        bg_job.cleanup(job_id, false)
        _set_download_state(appid, { manifestDone = true })
        m_status = "done"
    elseif m_status == "failed" then
        bg_job.cleanup(job_id, false)
    end

    if f_status == "extracted" then
        fixes.get_apply_status(appid) -- registers the fix
        _set_download_state(appid, { fixDone = true })
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
