local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local logger = require("plugin_logger")
local utils = require("plugin_utils")
local paths = require("paths")
local cjson = require("json")

local fixes = {}

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
            local online_url = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip"
            
            local has_generic = false
            for _, v in ipairs(data.genericFixes or {}) do if tonumber(v) == appid then has_generic = true break end end
            if has_generic then
                result.genericFix.status = 200
                result.genericFix.available = true
                result.genericFix.url = generic_url
            else
                result.genericFix.status = 404
            end
            
            local has_online = false
            for _, v in ipairs(data.onlineFixes or {}) do if tonumber(v) == appid then has_online = true break end end
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
    local dest_root = utils.ensure_temp_download_dir()
    local dest_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")
    local state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local ps1_path = fs.join(dest_root, "fix_" .. tostring(appid) .. "_dl.ps1")

    logger.log("ManifestAdvTools: Applying fix to " .. tostring(install_path))
    m_utils.write_file(state_file, '{"status": "downloading"}')

    local is_windows = m_utils.getenv("OS") == "Windows_NT"

    local function fwd(p) return (p:gsub("\\\\", "/"):gsub("\\", "/")) end

    if is_windows then
        local sf = fwd(state_file)
        local dz = fwd(dest_zip)
        local ip = fwd(install_path)
        local ps1 =
            "$sf  = '" .. sf  .. "'\r\n" ..
            "$url = '" .. download_url .. "'\r\n" ..
            "$dp  = '" .. dz  .. "'\r\n" ..
            "$ed  = '" .. ip  .. "'\r\n" ..
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
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"failed\",\"error\":\"download failed\"}')\r\n" ..
            "}\r\n"
        m_utils.write_file(ps1_path, ps1)
        local cmd = 'cmd.exe /c start /b "" powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. ps1_path .. '"'
        m_utils.exec(cmd)
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        local cmd = string.format(
            'nohup bash "%s" "%s" "%s" "%s" "%s" > /dev/null 2>&1 &',
            sh_path, download_url, dest_zip, install_path, state_file
        )
        m_utils.exec(cmd)
    end

    return { success = true }
end

function fixes.get_apply_status(appid)
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local dest_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")
    
    if not fs.exists(state_file) then
        return { success = true, state = { status = "done" } }
    end
    
    local content = m_utils.read_file(state_file)
    if content and content ~= "" then
        local success, data = pcall(cjson.decode, content)
        if success and type(data) == "table" and data.status then
            if data.status == "extracted" then
                data.status = "done"
                pcall(fs.remove, state_file)
                pcall(fs.remove, dest_zip)
            elseif data.status == "failed" then
                pcall(fs.remove, state_file)
            end
            return { success = true, state = data }
        end
    end
    
    return { success = true, state = { status = "downloading" } }
end

return fixes
