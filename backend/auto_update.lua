local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local paths = require("paths")
local utils = require("plugin_utils")
local steam_utils = require("steam_utils")

local auto_update = {}

-- Compare version strings component by component (can't use <= on tables in Lua)
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

local function fail(msg)
    return { success = false, error = msg, message = msg }
end

--- Latest GitHub release: version string and zip asset URL (nil, nil on failure).
local function latest_release(owner, repo, asset_name, tag, tag_prefix)
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
    if not (resp and resp.status == 200 and resp.body) then
        logger.warn("auto_update: releases API returned " .. tostring(resp and resp.status))
        return nil, nil
    end

    local data = utils.decode_json(resp.body)
    local tag_name = data.tag_name or ""
    local version = (tag_name ~= "" and tag_name) or data.name or ""
    if tag_prefix ~= "" and version:sub(1, #tag_prefix) == tag_prefix then
        version = version:sub(#tag_prefix + 1)
    end
    version = version:gsub("^[vV]", "")
    if version == "" then return nil, nil end

    for _, asset in ipairs(data.assets or {}) do
        if asset.name == asset_name then
            return version, asset.browser_download_url
        end
    end
    if tag_name ~= "" then
        return version, "https://github.com/" .. owner .. "/" .. repo .. "/releases/download/" .. tag_name .. "/" .. asset_name
    end
    return nil, nil
end

--- Version in plugin.json on the main branch (nil on failure).
local function main_branch_version(owner, repo)
    local url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/main/plugin.json?t=" .. os.time()
    local resp = http_client.get(url, {
        headers = { ["User-Agent"] = "ManifestAdvTools-Updater" },
        timeout = 10
    })
    if resp and resp.status == 200 and resp.body then
        local data = utils.decode_json(resp.body)
        if data.version then return tostring(data.version) end
    end
    logger.warn("auto_update: could not read main plugin.json (" .. tostring(resp and resp.status) .. ")")
    return nil
end

-- Releases lag behind main (they sat at v8.1.1 while main moved on), so
-- check both and take the newer one, same as install-plugin.ps1.
function auto_update.check_for_updates_now()
    local cfg = utils.read_json(paths.backend_path(config.UPDATE_CONFIG_FILE))
    local gh_cfg = cfg.github or {}
    local owner = gh_cfg.owner or "Adv3ntur3sBr"
    local repo = gh_cfg.repo or "ManifestAdvTools"
    local asset_name = gh_cfg.asset_name or "ManifestAdvTools.zip"

    local rel_version, rel_zip = latest_release(owner, repo, asset_name, gh_cfg.tag or "", gh_cfg.tag_prefix or "")
    local main_version = main_branch_version(owner, repo)

    local latest_version, zip_url
    if rel_version and (not main_version or compare_versions(rel_version, main_version) > 0) then
        latest_version, zip_url = rel_version, rel_zip
    elseif main_version then
        latest_version = main_version
        zip_url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/main/" .. asset_name .. "?t=" .. os.time()
    else
        return fail("Não foi possível verificar atualizações agora (GitHub fora do ar ou limite de consultas atingido). Tente de novo em alguns minutos.")
    end

    local current_version = utils.get_plugin_version()
    if compare_versions(latest_version, current_version) <= 0 then
        return { success = true, message = "ManifestAdvTools já está na versão mais recente (" .. current_version .. ")." }
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
        return fail("Falha ao baixar a atualização " .. latest_version .. ". Tente de novo mais tarde.")
    end

    m_utils.exec(extract_cmd)
    fs.remove(pending_zip)

    return { success = true, message = "ManifestAdvTools atualizado de " .. current_version .. " para " .. latest_version .. "! Reinicie a Steam para aplicar." }
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
