local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local paths = require("paths")
local utils = require("plugin_utils")
local steam_utils = require("steam_utils")

local auto_update = {}

function auto_update.check_for_updates_now()
    local cfg_path = paths.backend_path(config.UPDATE_CONFIG_FILE)
    local cfg = utils.read_json(cfg_path)
    
    local latest_version = ""
    local zip_url = ""
    
    local gh_cfg = cfg.github
    if gh_cfg then
        local owner = gh_cfg.owner or ""
        local repo = gh_cfg.repo or ""
        local asset_name = gh_cfg.asset_name or "ltsteamplugin.zip"
        local tag = gh_cfg.tag or ""
        local tag_prefix = gh_cfg.tag_prefix or ""
        
        local endpoint = "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/releases/latest"
        if tag ~= "" then
            endpoint = "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/releases/tags/" .. tag
        end
        
        local resp = http_client.get(endpoint, {
            headers = {
                ["Accept"] = "application/vnd.github+json",
                ["User-Agent"] = "ManifestAdvTools-Updater"
            },
            timeout = 10
        })
        if resp and resp.status == 200 and resp.body then
            local data = utils.decode_json(resp.body)
            local tag_name = data.tag_name or ""
            latest_version = (tag_name ~= "" and tag_name) or data.name or ""
            if tag_prefix ~= "" and latest_version:sub(1, #tag_prefix) == tag_prefix then
                latest_version = latest_version:sub(#tag_prefix + 1)
            end
            
            for _, asset in ipairs(data.assets or {}) do
                if asset.name == asset_name then
                    zip_url = asset.browser_download_url
                    break
                end
            end
            if zip_url == "" and tag_name ~= "" then
                zip_url = "https://github.com/Adv3ntur3sBr/ManifestAdvTools/releases/download/" .. tag_name .. "/" .. asset_name
            end
        end
    end
    
    if latest_version == "" or zip_url == "" then
        return { success = false, error = "Manifest missing version or zip_url" }
    end
    
    local current_version = utils.get_plugin_version()

    -- Compare version tables component by component (can't use <= on tables in Lua)
    local function compare_versions(a, b)
        local ta = utils.parse_version(a)
        local tb = utils.parse_version(b)
        local len = math.max(#ta, #tb)
        for i = 1, len do
            local ai = ta[i] or 0
            local bi = tb[i] or 0
            if ai < bi then return -1
            elseif ai > bi then return 1
            end
        end
        return 0
    end

    if compare_versions(latest_version, current_version) <= 0 then
        return { success = true, message = "ManifestAdvTools já está na versão mais recente (" .. current_version .. ")" }
    end
    
    local pending_zip = paths.backend_path(config.UPDATE_PENDING_ZIP)
    local plugin_dir = paths.get_plugin_dir()

    -- Drop any leftover zip so a stale file can't pass for a fresh download
    if fs.exists(pending_zip) then fs.remove(pending_zip) end

    -- exec() gives no exit code, so download and extract are separate steps
    -- and the zip's presence is the success check. -f keeps HTTP errors
    -- (404, rate limit) from being saved as the zip.
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    local download_cmd, extract_cmd
    if is_windows then
        download_cmd = string.format('curl.exe -sfL -A "ManifestAdvTools" "%s" -o "%s"', zip_url, pending_zip)
        extract_cmd = string.format('tar.exe -xf "%s" -C "%s"', pending_zip, plugin_dir)
    else
        download_cmd = string.format('curl -sfL -o "%s" "%s"', pending_zip, zip_url)
        extract_cmd = string.format('unzip -o -q "%s" -d "%s"', pending_zip, plugin_dir)
    end

    m_utils.exec(download_cmd)
    if not fs.exists(pending_zip) then
        logger.warn("auto_update: download failed: " .. zip_url)
        return { success = false, error = "Falha ao baixar a atualização " .. latest_version .. ". Tente de novo mais tarde." }
    end

    m_utils.exec(extract_cmd)
    fs.remove(pending_zip)
    
    local msg = "ManifestAdvTools atualizado com sucesso para " .. latest_version .. "! Reinicie o Steam."
    return { success = true, message = msg }
end

-- The backend runs inside Steam, so anything it spawns dies with Steam's
-- process tree when restart_steam.cmd kills steam.exe — Steam closed but
-- never came back. Win32_Process.Create (WMI) starts the script outside
-- that tree; Start-Process is only the fallback.
local RESTART_LAUNCHER_PS = [==[
$ErrorActionPreference = 'Stop'
try {
    $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = 'cmd.exe /c "' + $script + '"'
        ProcessStartupInformation = $si
    }
    if ($r.ReturnValue -ne 0) { throw "Win32_Process.Create returned $($r.ReturnValue)" }
} catch {
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('"' + $script + '"') -WindowStyle Hidden
}
]==]

function auto_update.restart_steam()
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    if is_windows then
        local script_path = paths.backend_path("restart_steam.cmd")
        if fs.exists(script_path) then
            local win_path = script_path:gsub("/", "\\")
            local launcher = fs.join(utils.ensure_temp_download_dir(), "restart_launcher.ps1")
            -- BOM so Windows PowerShell 5 reads non-ASCII paths (user names with accents) correctly
            local quoted = win_path:gsub("'", "''")
            local body = "\239\187\191$script = '" .. quoted .. "'\r\n"
                .. RESTART_LAUNCHER_PS:gsub("\r?\n", "\r\n")
            m_utils.write_file(launcher, body)
            logger.log("auto_update: restarting Steam via " .. win_path)
            m_utils.exec('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. launcher .. '"')
            return true
        end
    else
        m_utils.exec("killall steam && steam &")
        return true
    end
    return false
end

function auto_update.apply_pending_update_if_any()
    return ""
end

return auto_update
