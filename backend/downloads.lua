local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local paths = require("paths")
local steam_utils = require("steam_utils")
local utils = require("plugin_utils")
local api_manifest = require("api_manifest")
local settings_manager = require("settings.manager")
local cjson = require("json")

local downloads = {}
local DOWNLOAD_STATE = {}

local function _set_download_state(appid, update)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not DOWNLOAD_STATE[appid] then DOWNLOAD_STATE[appid] = {} end
    for k, v in pairs(update) do
        DOWNLOAD_STATE[appid][k] = v
    end
end

local function _get_download_state(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local state = DOWNLOAD_STATE[appid] or {}
    local copy = {}
    for k, v in pairs(state) do copy[k] = v end
    return copy
end

function downloads.get_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")
    
    if fs.exists(state_file) then
        local content = m_utils.read_file(state_file)
        if content and content ~= "" then
            local success, data = pcall(cjson.decode, content)
            if success and type(data) == "table" and data.status then
                _set_download_state(appid, { status = data.status, error = data.error })
                
                if data.status == "extracted" then
                    -- Background script finished! Complete the installation synchronously.
                    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
                    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
                    local apiName = _get_download_state(appid).currentApi or "Unknown"
                    
                    local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
                    if not ok then
                        _set_download_state(appid, { status = "failed", error = tostring(res) })
                    end
                    
                    -- Cleanup background script files
                    pcall(fs.remove, state_file)
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.sh"))
                elseif data.status == "failed" then
                    pcall(fs.remove, state_file)
                end
            end
        end
    end

    return { success = true, state = _get_download_state(appid) }
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

local function _win_slash(p)
    return (p:gsub("\\\\", "/"):gsub("\\", "/"))
end

local function _launch_async_download(appid, url, dest_path, extract_dir)
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")

    m_utils.write_file(state_file, '{"status": "downloading"}')
    if not fs.exists(extract_dir) then fs.create_directories(extract_dir) end

    if is_windows then
        -- Write a silent PowerShell script — no CMD/terminal window appears
        local ps1_path = fs.join(dest_root, tostring(appid) .. "_dl.ps1")
        local sf  = _win_slash(state_file)
        local dp  = _win_slash(dest_path)
        local ed  = _win_slash(extract_dir)
        local ps1 =
            "$sf  = '" .. sf  .. "'\r\n" ..
            "$url = '" .. url .. "'\r\n" ..
            "$dp  = '" .. dp  .. "'\r\n" ..
            "$ed  = '" .. ed  .. "'\r\n" ..
            "$ErrorActionPreference = 'Stop'\r\n" ..
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13\r\n" ..
            "try {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"downloading\"}')\r\n" ..
            "    $wc = New-Object Net.WebClient\r\n" ..
            "    $wc.Headers['User-Agent'] = 'discord(dot)gg/luatools'\r\n" ..
            "    $wc.DownloadFile($url, $dp)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracting\"}')\r\n" ..
            "    Add-Type -A System.IO.Compression.FileSystem\r\n" ..
            "    [IO.Compression.ZipFile]::ExtractToDirectory($dp, $ed)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracted\"}')\r\n" ..
            "} catch {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"failed\",\"error\":\"download failed\"}')\r\n" ..
            "}\r\n"
        m_utils.write_file(ps1_path, ps1)
        -- /b = no new window; -WindowStyle Hidden = fully invisible process
        local cmd = 'cmd.exe /c start /b "" powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. ps1_path .. '"'
        m_utils.exec(cmd)
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        local cmd = string.format(
            'nohup bash "%s" "%s" "%s" "%s" "%s" > /dev/null 2>&1 &',
            sh_path, url, dest_path, extract_dir, state_file
        )
        m_utils.exec(cmd)
    end
end

-- Downloads manifest + OnlineFix in parallel (two silent PS1 scripts)
local function _launch_async_download_with_fix(appid, manifest_url, fix_url, dest_path, extract_dir, install_path)
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    local dest_root = utils.ensure_temp_download_dir()
    local state_file     = fs.join(dest_root, tostring(appid) .. "_state.json")
    local fix_state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local fix_zip        = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")

    m_utils.write_file(state_file,     '{"status": "downloading"}')
    m_utils.write_file(fix_state_file, '{"status": "downloading"}')
    if not fs.exists(extract_dir) then fs.create_directories(extract_dir) end
    if not fs.exists(install_path) then fs.create_directories(install_path) end

    if is_windows then
        -- === Script 1: manifest download + extract ===
        local ps1_path = fs.join(dest_root, tostring(appid) .. "_dl.ps1")
        local sf  = _win_slash(state_file)
        local dp  = _win_slash(dest_path)
        local ed  = _win_slash(extract_dir)
        local ps1 =
            "$sf  = '" .. sf  .. "'\r\n" ..
            "$url = '" .. manifest_url .. "'\r\n" ..
            "$dp  = '" .. dp  .. "'\r\n" ..
            "$ed  = '" .. ed  .. "'\r\n" ..
            "$ErrorActionPreference = 'Stop'\r\n" ..
            "try {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"downloading\"}')\r\n" ..
            "    $wc = New-Object Net.WebClient\r\n" ..
            "    $wc.Headers['User-Agent'] = 'discord(dot)gg/luatools'\r\n" ..
            "    $wc.DownloadFile($url, $dp)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracting\"}')\r\n" ..
            "    Add-Type -A System.IO.Compression.FileSystem\r\n" ..
            "    [IO.Compression.ZipFile]::ExtractToDirectory($dp, $ed)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracted\"}')\r\n" ..
            "} catch {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"failed\",\"error\":\"manifest download failed\"}')\r\n" ..
            "}\r\n"
        m_utils.write_file(ps1_path, ps1)
        m_utils.exec('cmd.exe /c start /b "" powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. ps1_path .. '"')

        -- === Script 2: OnlineFix download + extract (runs in parallel) ===
        local fix_ps1_path = fs.join(dest_root, "fix_" .. tostring(appid) .. "_dl.ps1")
        local fsf = _win_slash(fix_state_file)
        local fdp = _win_slash(fix_zip)
        local fip = _win_slash(install_path)
        local fix_ps1 =
            "$sf  = '" .. fsf .. "'\r\n" ..
            "$url = '" .. fix_url .. "'\r\n" ..
            "$dp  = '" .. fdp .. "'\r\n" ..
            "$ed  = '" .. fip .. "'\r\n" ..
            "$ErrorActionPreference = 'Stop'\r\n" ..
            "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13\r\n" ..
            "try {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"downloading\"}')\r\n" ..
            "    $wc2 = New-Object Net.WebClient\r\n" ..
            "    $wc2.Headers['User-Agent'] = 'discord(dot)gg/luatools'\r\n" ..
            "    $wc2.DownloadFile($url, $dp)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracting\"}')\r\n" ..
            "    Add-Type -A System.IO.Compression.FileSystem\r\n" ..
            "    [IO.Compression.ZipFile]::ExtractToDirectory($dp, $ed)\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracted\"}')\r\n" ..
            "} catch {\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"failed\",\"error\":\"fix download failed\"}')\r\n" ..
            "}\r\n"
        m_utils.write_file(fix_ps1_path, fix_ps1)
        m_utils.exec('cmd.exe /c start /b "" powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. fix_ps1_path .. '"')
    else
        -- Linux: parallel background jobs
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        m_utils.exec(string.format('nohup bash "%s" "%s" "%s" "%s" "%s" > /dev/null 2>&1 &', sh_path, manifest_url, dest_path, extract_dir, state_file))
        m_utils.exec(string.format('nohup bash "%s" "%s" "%s" "%s" "%s" > /dev/null 2>&1 &', sh_path, fix_url, fix_zip, install_path, fix_state_file))
    end
end

-- Returns combined manifest+fix download progress (both must succeed)
function downloads.get_bundle_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local dest_root = utils.ensure_temp_download_dir()
    local state_file     = fs.join(dest_root, tostring(appid) .. "_state.json")
    local fix_state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")

    local function read_state(path)
        if not fs.exists(path) then return { status = "done" } end
        local c = m_utils.read_file(path)
        if not c or c == "" then return { status = "downloading" } end
        local ok, d = pcall(cjson.decode, c)
        return (ok and type(d) == "table") and d or { status = "downloading" }
    end

    local ms = read_state(state_file)
    local fs_ = read_state(fix_state_file)

    -- If manifest finished downloading, finalize it
    if ms.status == "extracted" then
        local dest_path  = fs.join(dest_root, tostring(appid) .. ".zip")
        local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
        local apiName = _get_download_state(appid).currentApi or "OnlineFix Bundle"
        local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
        if not ok then _set_download_state(appid, { status = "failed", error = tostring(res) }) end
        pcall(fs.remove, state_file)
        pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))
        ms.status = "done"
    elseif ms.status == "failed" then
        pcall(fs.remove, state_file)
    end

    -- Fix finalization: already handled by fixes module (ExtractToDirectory goes straight to install_path)
    if fs_.status == "extracted" then
        pcall(fs.remove, fix_state_file)
        pcall(fs.remove, fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip"))
        pcall(fs.remove, fs.join(dest_root, "fix_" .. tostring(appid) .. "_dl.ps1"))
        fs_.status = "done"
    elseif fs_.status == "failed" then
        pcall(fs.remove, fix_state_file)
    end

    -- Merge: report combined status
    local combined
    if ms.status == "failed" then
        combined = "failed"
    elseif ms.status == "done" and (fs_.status == "done" or fs_.status == "not_available") then
        combined = "done"
        _set_download_state(appid, { status = "done", success = true, hadOnlineFix = (fs_.status == "done") })
    elseif ms.status == "extracting" or fs_.status == "extracting" then
        combined = "extracting"
    else
        combined = "downloading"
    end

    return { success = true, state = { status = combined, manifest = ms.status, fix = fs_.status } }
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

-- Exposed to frontend: download manifest + OnlineFix together
function downloads.start_add_with_online_fix(appid, manifest_url, api_name, install_path)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    -- Auto-resolve manifest URL if missing or empty
    if not manifest_url or manifest_url == "" then
        manifest_url, api_name = downloads.find_manifest_url_for_app(appid)
        if not manifest_url or manifest_url == "" then
            return { success = false, error = "Manifesto não encontrado para este jogo em nenhuma das APIs ativas" }
        end
    end
    api_name = api_name or "AdvgameTool"

    logger.log("AdvgameTool: Bundle download appid=" .. tostring(appid) .. " manifest=" .. tostring(manifest_url))
    _set_download_state(appid, { status = "downloading", currentApi = api_name, isBundleDownload = true })

    local dest_root   = utils.ensure_temp_download_dir()
    local dest_path   = fs.join(dest_root, tostring(appid) .. ".zip")
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local fix_state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")

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

    if fix_url then
        local fix_install = install_path or fs.join(
            steam_utils.detect_steam_install_path(), "steamapps", "common", tostring(appid)
        )
        local ok, res = pcall(_launch_async_download_with_fix, appid, manifest_url, fix_url, dest_path, extract_dir, fix_install)
        if not ok then
            logger.warn("AdvgameTool: Bundle download failed to start - " .. tostring(res))
            _set_download_state(appid, { status = "failed", error = tostring(res) })
            return { success = false, error = tostring(res) }
        end
        return { success = true, isBundleDownload = true, fixUrl = fix_url }
    else
        -- OnlineFix not available for this appid: install manifest and set fix state to not_available
        logger.log("AdvgameTool: OnlineFix not available for " .. tostring(appid) .. ", proceeding with manifest-only")
        m_utils.write_file(fix_state_file, '{"status":"not_available"}')
        local ok, res = pcall(_launch_async_download, appid, manifest_url, dest_path, extract_dir)
        if not ok then
            logger.warn("AdvgameTool: Manifest download failed - " .. tostring(res))
            _set_download_state(appid, { status = "failed", error = tostring(res) })
            return { success = false, error = tostring(res) }
        end
        return { success = true, isBundleDownload = true, fixAvailable = false }
    end
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
    apiName = apiName or "AdvgameTool"

    logger.log("AdvgameTool: StartAddViaLuaToolsFromUrl appid=" .. tostring(appid) .. " api=" .. tostring(apiName))
    _set_download_state(appid, { status = "downloading", currentApi = apiName, bytesRead = 0, totalBytes = 0 })

    local ok, res = pcall(function()
        local dest_root = utils.ensure_temp_download_dir()
        local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
        local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
        _launch_async_download(appid, url, dest_path, extract_dir)
    end)

    if not ok then
        logger.warn("AdvgameTool: Async Download crashed - " .. tostring(res))
        _set_download_state(appid, { status = "failed", error = tostring(res) })
        return { success = false, error = tostring(res) }
    end

    return { success = true }
end

function downloads.start_add_via_luatools(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    logger.log("AdvgameTool: StartAddViaLuaTools appid=" .. tostring(appid))
    _set_download_state(appid, { status = "queued", bytesRead = 0, totalBytes = 0 })

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        _set_download_state(appid, { status = "failed", error = "No APIs available" })
        return { success = true }
    end

    local dest_root = utils.ensure_temp_download_dir()
    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    local ok, res = pcall(function()
        -- Note: For auto-add we only try the FIRST valid URL without verifying it via a synchronous HTTP request,
        -- because verifying it synchronously would defeat the purpose of async downloads.
        -- We assume CheckApisForApp already verified availability before user clicked this!
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
        if not target_url then error("Not available on any API") end
        
        _set_download_state(appid, { status = "downloading", currentApi = target_name })
        _launch_async_download(appid, target_url, dest_path, extract_dir)
    end)

    if not ok then
        logger.warn("AdvgameTool: start_add_via_luatools crashed - " .. tostring(res))
        _set_download_state(appid, { status = "failed", error = tostring(res) })
        return { success = false, error = tostring(res) }
    end

    return { success = true }
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
            local success = false
            local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
            if resp and resp.status == success_code then
                success = true
            else
                -- Fallback to GET if HEAD fails
                local get_resp = http_client.get(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
                if get_resp and get_resp.status == success_code then
                    success = true
                end
            end
            
            if success then
                available = true
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

return downloads
