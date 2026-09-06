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
            latest_version = tag_name or data.name or ""
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
    
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    local cmd
    if is_windows then
        cmd = string.format('curl.exe -sL -A "ManifestAdvTools" "%s" -o "%s" && tar.exe -xf "%s" -C "%s"', zip_url, pending_zip, pending_zip, paths.get_plugin_dir())
    else
        cmd = string.format('curl -L -o "%s" "%s" && unzip -o -q "%s" -d "%s"', pending_zip, zip_url, pending_zip, paths.get_plugin_dir())
    end
    
    m_utils.exec(cmd)
    
    if fs.exists(pending_zip) then fs.remove(pending_zip) end
    
    local msg = "ManifestAdvTools atualizado com sucesso para " .. latest_version .. "! Reinicie o Steam."
    return { success = true, message = msg }
end

function auto_update.restart_steam()
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    if is_windows then
        local steam_dir = steam_utils.detect_steam_install_path() or "C:\\Program Files (x86)\\Steam"
        local steam_exe = fs.join(steam_dir, "steam.exe"):gsub("/", "\\")
        
        -- Detached PowerShell process that survives Steam job object termination
        local ps_cmd = string.format(
            'powershell.exe -NoProfile -WindowStyle Hidden -Command "' ..
            'Start-Sleep -Seconds 1; ' ..
            'Get-Process -Name \'steam\', \'steamwebhelper\', \'millennium*\' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; ' ..
            'Start-Sleep -Seconds 2; ' ..
            'if (Test-Path \'%s\') { Start-Process \'%s\' } else { Start-Process \'steam://open/main\' }"',
            steam_exe, steam_exe
        )
        
        m_utils.exec('cmd.exe /c start "" /min ' .. ps_cmd)
        return true
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
