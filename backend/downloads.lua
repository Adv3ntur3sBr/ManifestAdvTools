local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local utils = require("plugin_utils")
local paths = require("paths")
local steam_utils = require("steam_utils")
local api_manifest = require("api_manifest")
local settings_manager = require("settings.manager")
local cjson = require("json")

local downloads = {}

local DOWNLOAD_STATE = {}

local function _is_windows()
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return true
    end
    if os and os.getenv and os.getenv("OS") == "Windows_NT" then
        return true
    end
    if m_utils and type(m_utils.getenv) == "function" then
        local ok, val = pcall(m_utils.getenv, "OS")
        if ok and val == "Windows_NT" then return true end
    end
    return false
end

local function _set_download_state(appid, update)
    local key = tonumber(appid) or appid
    local state = DOWNLOAD_STATE[key] or {}
    for k, v in pairs(update) do
        state[k] = v
    end
    DOWNLOAD_STATE[key] = state
end

local function _get_download_state(appid)
    local key = tonumber(appid) or appid
    local state = DOWNLOAD_STATE[key] or {}
    local copy = {}
    for k, v in pairs(state) do copy[k] = v end
    return copy
end

local function _ps_escape(s)
    return tostring(s or ""):gsub("'", "''")
end

local function _list_files_recursive(dir_path)
    local results = {}
    local ok_rec, rec_files = pcall(fs.list_recursive, dir_path)
    if ok_rec and type(rec_files) == "table" then
        return rec_files
    end
    local function walk(curr)
        local ok_l, list = pcall(fs.list, curr)
        if not ok_l or type(list) ~= "table" then return end
        for _, entry in ipairs(list) do
            if type(entry) == "table" then
                local epath = entry.path or (entry.name and fs.join(curr, entry.name)) or ""
                if entry.is_directory then
                    walk(epath)
                else
                    table.insert(results, {
                        name = entry.name or epath:match("([^/\\]+)$") or "",
                        path = epath,
                        is_directory = false
                    })
                end
            elseif type(entry) == "string" then
                local epath = fs.join(curr, entry)
                table.insert(results, {
                    name = entry:match("([^/\\]+)$") or entry,
                    path = epath,
                    is_directory = false
                })
            end
        end
    end
    walk(dir_path)
    return results
end

local function _execute_manifest_download(appid, url, dest_path, extract_dir)
    local is_windows = _is_windows()
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")

    local base_path = steam_utils.detect_steam_install_path() or ""
    local target_dir = base_path ~= "" and fs.join(base_path, "config", "stplug-in") or ""
    local depot_cache = base_path ~= "" and fs.join(base_path, "depotcache") or ""
    local target_lua = target_dir ~= "" and fs.join(target_dir, tostring(appid) .. ".lua") or ""

    if target_dir ~= "" and not fs.exists(target_dir) then pcall(fs.create_directories, target_dir) end
    if depot_cache ~= "" and not fs.exists(depot_cache) then pcall(fs.create_directories, depot_cache) end

    m_utils.write_file(state_file, '{"status":"downloading","bytesRead":50,"totalBytes":100}')
    if not fs.exists(extract_dir) then pcall(fs.create_directories, extract_dir) end

    if is_windows then
        local ps1_path = fs.join(dest_root, tostring(appid) .. "_dl.ps1")
        local ps1 =
            "$ProgressPreference = 'SilentlyContinue'\r\n" ..
            "$ErrorActionPreference = 'Stop'\r\n" ..
            "$sf         = '" .. _ps_escape(state_file) .. "'\r\n" ..
            "$url        = '" .. _ps_escape(url) .. "'\r\n" ..
            "$dp         = '" .. _ps_escape(dest_path) .. "'\r\n" ..
            "$ed         = '" .. _ps_escape(extract_dir) .. "'\r\n" ..
            "$depotCache = '" .. _ps_escape(depot_cache) .. "'\r\n" ..
            "$targetDir  = '" .. _ps_escape(target_dir) .. "'\r\n" ..
            "$targetLua  = '" .. _ps_escape(target_lua) .. "'\r\n" ..
            "$appidStr   = '" .. tostring(appid) .. "'\r\n" ..
            "try {\r\n" ..
            "    if (Test-Path -LiteralPath $dp) { Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue }\r\n" ..
            "    if (Test-Path -LiteralPath $ed) { Remove-Item -LiteralPath $ed -Recurse -Force -ErrorAction SilentlyContinue }\r\n" ..
            "    New-Item -ItemType Directory -Force -Path $ed | Out-Null\r\n" ..
            "    if ($depotCache -ne '' -and -not (Test-Path -LiteralPath $depotCache)) { New-Item -ItemType Directory -Force -Path $depotCache | Out-Null }\r\n" ..
            "    if ($targetDir -ne '' -and -not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }\r\n" ..
            "    $dlOk = $false\r\n" ..
            "    if ($url -match '^https?://' -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {\r\n" ..
            "        & curl.exe -sSL --fail --connect-timeout 15 --max-time 120 -A 'discord(dot)gg/luatools' -o $dp $url 2>$null\r\n" ..
            "        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dp) -and (Get-Item -LiteralPath $dp).Length -gt 0) {\r\n" ..
            "            $dlOk = $true\r\n" ..
            "        }\r\n" ..
            "    }\r\n" ..
            "    if (-not $dlOk) {\r\n" ..
            "        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12\r\n" ..
            "        $wc = New-Object Net.WebClient\r\n" ..
            "        $wc.Headers['User-Agent'] = 'discord(dot)gg/luatools'\r\n" ..
            "        $wc.DownloadFile($url, $dp)\r\n" ..
            "    }\r\n" ..
            "    if (-not (Test-Path -LiteralPath $dp) -or (Get-Item -LiteralPath $dp).Length -eq 0) {\r\n" ..
            "        throw 'Downloaded file is empty or missing'\r\n" ..
            "    }\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"processing\",\"bytesRead\":85,\"totalBytes\":100}')\r\n" ..
            "    $extOk = $false\r\n" ..
            "    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {\r\n" ..
            "        & tar.exe -xf $dp -C $ed 2>$null\r\n" ..
            "        if ($LASTEXITCODE -eq 0) { $extOk = $true }\r\n" ..
            "    }\r\n" ..
            "    if (-not $extOk) {\r\n" ..
            "        Expand-Archive -LiteralPath $dp -DestinationPath $ed -Force\r\n" ..
            "    }\r\n" ..
            "    $manifestFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.manifest')\r\n" ..
            "    if ($depotCache -ne '' -and $manifestFiles.Count -gt 0) {\r\n" ..
            "        foreach ($mf in $manifestFiles) {\r\n" ..
            "            Copy-Item -LiteralPath $mf.FullName -Destination (Join-Path $depotCache $mf.Name) -Force\r\n" ..
            "        }\r\n" ..
            "    }\r\n" ..
            "    $luaWritten = $false\r\n" ..
            "    if ($targetLua -ne '') {\r\n" ..
            "        $luaFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.lua')\r\n" ..
            "        $chosenLua = $luaFiles | Where-Object { $_.Name -eq ($appidStr + '.lua') } | Select-Object -First 1\r\n" ..
            "        if (-not $chosenLua) {\r\n" ..
            "            $chosenLua = $luaFiles | Where-Object { $_.Name -match '^\\d+\\.lua$' } | Select-Object -First 1\r\n" ..
            "        }\r\n" ..
            "        if (-not $chosenLua -and $luaFiles.Count -gt 0) {\r\n" ..
            "            $chosenLua = $luaFiles[0]\r\n" ..
            "        }\r\n" ..
            "        if ($chosenLua) {\r\n" ..
            "            $text = [IO.File]::ReadAllText($chosenLua.FullName)\r\n" ..
            "            $text = [Text.RegularExpressions.Regex]::Replace($text, '(?m)^(\\s*)(setManifestid\\()', '$1-- $2')\r\n" ..
            "            [IO.File]::WriteAllText($targetLua, $text)\r\n" ..
            "            $luaWritten = $true\r\n" ..
            "        } else {\r\n" ..
            "            $vdfFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.vdf')\r\n" ..
            "            $depotKeys = @{}\r\n" ..
            "            foreach ($vf in $vdfFiles) {\r\n" ..
            "                $vdfText = [IO.File]::ReadAllText($vf.FullName)\r\n" ..
            "                $matches = [Text.RegularExpressions.Regex]::Matches($vdfText, '\"(\\d+)\"\\s*\\{[\\s\\S]*?\"[Dd]ecryption[Kk]ey\"\\s*\"([0-9a-fA-F]{64})\"')\r\n" ..
            "                foreach ($m in $matches) {\r\n" ..
            "                    $depotKeys[$m.Groups[1].Value] = $m.Groups[2].Value\r\n" ..
            "                }\r\n" ..
            "            }\r\n" ..
            "            if ($depotKeys.Count -gt 0 -or $manifestFiles.Count -gt 0) {\r\n" ..
            "                $genLines = New-Object System.Collections.Generic.List[string]\r\n" ..
            "                $genLines.Add('addappid(' + $appidStr + ')')\r\n" ..
            "                foreach ($dk in $depotKeys.GetEnumerator()) {\r\n" ..
            "                    $genLines.Add('addappid(' + $dk.Key + ', 1, \"' + $dk.Value + '\")')\r\n" ..
            "                }\r\n" ..
            "                foreach ($mf in $manifestFiles) {\r\n" ..
            "                    if ($mf.BaseName -match '^(\\d+)_(\\d+)$') {\r\n" ..
            "                        $dId = $Matches[1]\r\n" ..
            "                        $mId = $Matches[2]\r\n" ..
            "                        if (-not $depotKeys.ContainsKey($dId)) {\r\n" ..
            "                            $genLines.Add('addappid(' + $dId + ')')\r\n" ..
            "                        }\r\n" ..
            "                        $genLines.Add('-- setManifestid(' + $dId + ', \"' + $mId + '\", 0)')\r\n" ..
            "                    }\r\n" ..
            "                }\r\n" ..
            "                [IO.File]::WriteAllText($targetLua, ($genLines -join \"`n\"))\r\n" ..
            "                $luaWritten = $true\r\n" ..
            "            }\r\n" ..
            "        }\r\n" ..
            "    }\r\n" ..
            "    if (-not $luaWritten -and $manifestFiles.Count -eq 0) {\r\n" ..
            "        throw 'No valid .lua or .manifest files found in archive'\r\n" ..
            "    }\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracted\",\"bytesRead\":100,\"totalBytes\":100}')\r\n" ..
            "} catch {\r\n" ..
            "    $errMsg = ($_.Exception.Message -replace '[\"\\\\\\r\\n]', ' ')\r\n" ..
            "    [IO.File]::WriteAllText($sf, ('{\"status\":\"failed\",\"error\":\"' + $errMsg + '\"}'))\r\n" ..
            "}\r\n"
        m_utils.write_file(ps1_path, ps1)
        local cmd = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' .. ps1_path .. '"'
        m_utils.exec(cmd)
    else
        local cmd = string.format(
            'curl -sSL --fail -A "discord(dot)gg/luatools" -o "%s" "%s" && unzip -o -q "%s" -d "%s"',
            dest_path, url, dest_path, extract_dir
        )
        m_utils.exec(cmd)
        if fs.exists(dest_path) then
            m_utils.write_file(state_file, '{"status":"extracted","bytesRead":100,"totalBytes":100}')
        else
            m_utils.write_file(state_file, '{"status":"failed","error":"download failed"}')
        end
    end
end

local function _execute_fix_download(appid, fix_url, fix_zip, install_path, fix_state_file)
    local is_windows = _is_windows()
    local dest_root = utils.ensure_temp_download_dir()
    if not fs.exists(install_path) then pcall(fs.create_directories, install_path) end

    if is_windows then
        local fix_ps1_path = fs.join(dest_root, "fix_" .. tostring(appid) .. "_dl.ps1")
        local fix_ps1 =
            "$ProgressPreference = 'SilentlyContinue'\r\n" ..
            "$ErrorActionPreference = 'Stop'\r\n" ..
            "$sf   = '" .. _ps_escape(fix_state_file) .. "'\r\n" ..
            "$furl = '" .. _ps_escape(fix_url) .. "'\r\n" ..
            "$fzip = '" .. _ps_escape(fix_zip) .. "'\r\n" ..
            "$inst = '" .. _ps_escape(install_path) .. "'\r\n" ..
            "try {\r\n" ..
            "    if (Test-Path -LiteralPath $fzip) { Remove-Item -LiteralPath $fzip -Force -ErrorAction SilentlyContinue }\r\n" ..
            "    if (-not (Test-Path -LiteralPath $inst)) { New-Item -ItemType Directory -Force -Path $inst | Out-Null }\r\n" ..
            "    $dlOk = $false\r\n" ..
            "    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {\r\n" ..
            "        & curl.exe -sSL --fail --connect-timeout 15 --max-time 180 -A 'ManifestAdvTools' -o $fzip $furl 2>$null\r\n" ..
            "        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fzip) -and (Get-Item -LiteralPath $fzip).Length -gt 0) {\r\n" ..
            "            $dlOk = $true\r\n" ..
            "        }\r\n" ..
            "    }\r\n" ..
            "    if (-not $dlOk) {\r\n" ..
            "        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12\r\n" ..
            "        $wc = New-Object Net.WebClient\r\n" ..
            "        $wc.Headers['User-Agent'] = 'ManifestAdvTools'\r\n" ..
            "        $wc.DownloadFile($furl, $fzip)\r\n" ..
            "    }\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracting\"}')\r\n" ..
            "    $extOk = $false\r\n" ..
            "    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {\r\n" ..
            "        & tar.exe -xf $fzip -C $inst 2>$null\r\n" ..
            "        if ($LASTEXITCODE -eq 0) { $extOk = $true }\r\n" ..
            "    }\r\n" ..
            "    if (-not $extOk) {\r\n" ..
            "        Expand-Archive -LiteralPath $fzip -DestinationPath $inst -Force\r\n" ..
            "    }\r\n" ..
            "    Remove-Item -LiteralPath $fzip -Force -ErrorAction SilentlyContinue\r\n" ..
            "    [IO.File]::WriteAllText($sf, '{\"status\":\"extracted\"}')\r\n" ..
            "} catch {\r\n" ..
            "    $errMsg = ($_.Exception.Message -replace '[\"\\\\\\r\\n]', ' ')\r\n" ..
            "    [IO.File]::WriteAllText($sf, ('{\"status\":\"failed\",\"error\":\"' + $errMsg + '\"}'))\r\n" ..
            "}\r\n"
        m_utils.write_file(fix_ps1_path, fix_ps1)
        m_utils.exec('powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' .. fix_ps1_path .. '"')
        pcall(fs.remove, fix_ps1_path)
    else
        local fix_cmd = string.format(
            'curl -sSL --fail -A "ManifestAdvTools" -o "%s" "%s" && unzip -o -q "%s" -d "%s" && rm -f "%s"',
            fix_zip, fix_url, fix_zip, install_path, fix_zip
        )
        m_utils.exec(fix_cmd)
        m_utils.write_file(fix_state_file, '{"status":"extracted"}')
    end
end

function downloads._finalize_install_lua(appid, extract_dir, dest_path, api_name)
    _set_download_state(appid, { status = "processing" })
    local base_path = steam_utils.detect_steam_install_path()
    local target_dir = fs.join(base_path, "config", "stplug-in")
    if not fs.exists(target_dir) then pcall(fs.create_directories, target_dir) end

    local depot_cache = fs.join(base_path, "depotcache")
    if not fs.exists(depot_cache) then pcall(fs.create_directories, depot_cache) end

    local target_lua = fs.join(target_dir, tostring(appid) .. ".lua")

    -- If the PowerShell script already wrote target_lua, we only need Lua fallback when target_lua doesn't exist yet
    if not fs.exists(target_lua) then
        local extracted_lua_path = nil
        local files = _list_files_recursive(extract_dir)
        for _, entry in ipairs(files) do
            if not entry.is_directory then
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
    pcall(fs.remove, extract_dir)
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

function downloads.cancel_add(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return end
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")
    pcall(fs.remove, state_file)
    _set_download_state(appid, {
        status = "cancelled",
        pendingExec = false,
        pollSeen = false
    })
end

function downloads.get_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")
    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))

    local cur = _get_download_state(appid)

    if cur.status == "cancelled" then
        return { success = true, state = cur }
    end

    -- Step 1: On the first poll after StartAdd, return downloading progress immediately so UI updates "Found" & progress bar
    if cur.pendingExec and not cur.pollSeen then
        _set_download_state(appid, {
            pollSeen = true,
            status = "downloading",
            bytesRead = 65,
            totalBytes = 100
        })
        return { success = true, state = _get_download_state(appid) }
    end

    -- Step 2: On the second poll, execute the download + extraction
    if cur.pendingExec and cur.pollSeen then
        _set_download_state(appid, { pendingExec = false })
        local ok_dl, err_dl = pcall(_execute_manifest_download, appid, cur.url, dest_path, extract_dir)
        if not ok_dl then
            _set_download_state(appid, { status = "failed", error = tostring(err_dl) })
            return { success = true, state = _get_download_state(appid) }
        end
    end

    if fs.exists(state_file) then
        local content = m_utils.read_file(state_file)
        if content and content ~= "" then
            local success, data = pcall(cjson.decode, content)
            if success and type(data) == "table" and data.status then
                _set_download_state(appid, {
                    status = data.status,
                    error = data.error,
                    bytesRead = data.bytesRead or cur.bytesRead or 50,
                    totalBytes = data.totalBytes or cur.totalBytes or 100
                })

                if data.status == "extracted" then
                    local apiName = _get_download_state(appid).currentApi or "Unknown"
                    local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
                    if not ok then
                        _set_download_state(appid, { status = "failed", error = tostring(res) })
                    end

                    pcall(fs.remove, state_file)
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.sh"))
                elseif data.status == "failed" then
                    pcall(fs.remove, state_file)
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.sh"))
                end
            end
        end
    end

    return { success = true, state = _get_download_state(appid) }
end

-- Returns combined manifest+fix download progress
function downloads.get_bundle_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")
    local fix_state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local fix_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")

    local cur = _get_download_state(appid)
    local step = cur.bundleStep or 0

    -- Poll 1: return initial downloading status so UI renders smoothly
    if step == 0 then
        _set_download_state(appid, { bundleStep = 1 })
        return {
            success = true,
            state = {
                status = "downloading",
                manifest = cur.manifestStatus or "downloading",
                fix = cur.fixStatus or "downloading"
            }
        }
    end

    -- Poll 2: download & install manifest
    if step == 1 then
        _set_download_state(appid, { bundleStep = 2, manifestStatus = "extracting" })
        local ok_dl, err_dl = pcall(_execute_manifest_download, appid, cur.manifestUrl, dest_path, extract_dir)
        if not ok_dl then
            _set_download_state(appid, {
                status = "failed",
                manifestStatus = "failed",
                error = tostring(err_dl)
            })
            return {
                success = true,
                state = { status = "failed", manifest = "failed", fix = cur.fixStatus or "not_available", error = tostring(err_dl) }
            }
        end

        local m_ok = false
        local m_err = "Manifest extraction failed"
        if fs.exists(state_file) then
            local c = m_utils.read_file(state_file)
            local ok_j, d = pcall(cjson.decode, c or "")
            if ok_j and type(d) == "table" then
                if d.status == "extracted" then
                    m_ok = true
                elseif d.error then
                    m_err = tostring(d.error)
                end
            end
        end

        pcall(fs.remove, state_file)
        pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))

        if not m_ok then
            _set_download_state(appid, {
                status = "failed",
                manifestStatus = "failed",
                error = m_err
            })
            return {
                success = true,
                state = { status = "failed", manifest = "failed", fix = cur.fixStatus or "not_available", error = m_err }
            }
        end

        pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, cur.currentApi or "AdvgameTool")
        _set_download_state(appid, { manifestStatus = "done" })

        -- If there is no OnlineFix to download, we're completely done!
        if not cur.fixUrl or cur.fixStatus == "not_available" then
            _set_download_state(appid, {
                bundleStep = 3,
                status = "done",
                manifestStatus = "done",
                fixStatus = "not_available",
                success = true
            })
            return {
                success = true,
                state = { status = "done", manifest = "done", fix = "not_available" }
            }
        end

        -- Otherwise report manifest=done, fix=extracting so next poll runs fix download
        _set_download_state(appid, { status = "downloading", fixStatus = "extracting" })
        return {
            success = true,
            state = { status = "downloading", manifest = "done", fix = "extracting" }
        }
    end

    -- Poll 3: download & extract OnlineFix
    if step == 2 then
        _set_download_state(appid, { bundleStep = 3 })
        local fix_status = "failed"
        local ok_fx = pcall(_execute_fix_download, appid, cur.fixUrl, fix_zip, cur.fixInstallPath, fix_state_file)
        if ok_fx and fs.exists(fix_state_file) then
            local c = m_utils.read_file(fix_state_file)
            local ok_j, d = pcall(cjson.decode, c or "")
            if ok_j and type(d) == "table" and d.status == "extracted" then
                fix_status = "done"
            end
        end
        pcall(fs.remove, fix_state_file)

        _set_download_state(appid, {
            status = "done",
            manifestStatus = "done",
            fixStatus = fix_status,
            success = true,
            hadOnlineFix = (fix_status == "done")
        })
        return {
            success = true,
            state = { status = "done", manifest = "done", fix = fix_status }
        }
    end

    local final_cur = _get_download_state(appid)
    return {
        success = true,
        state = {
            status = final_cur.status or "done",
            manifest = final_cur.manifestStatus or "done",
            fix = final_cur.fixStatus or "not_available"
        }
    }
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

    if not manifest_url or manifest_url == "" then
        manifest_url, api_name = downloads.find_manifest_url_for_app(appid)
        if not manifest_url or manifest_url == "" then
            return { success = false, error = "Manifesto não encontrado para este jogo em nenhuma das APIs ativas" }
        end
    end
    api_name = (api_name and api_name ~= "") and api_name or "AdvgameTool"

    logger.log("AdvgameTool: Bundle download appid=" .. tostring(appid) .. " manifest=" .. tostring(manifest_url))

    local dest_root = utils.ensure_temp_download_dir()
    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_state.json"))
    pcall(fs.remove, fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json"))

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
            fix_url = curl
            break
        end
    end

    local fix_install = (install_path and install_path ~= "") and install_path or nil
    if not fix_install then
        local ok_p, path_res = pcall(steam_utils.get_game_install_path_response, appid)
        if ok_p and type(path_res) == "table" and path_res.success and path_res.installPath and path_res.installPath ~= "" then
            fix_install = path_res.installPath
        else
            fix_install = fs.join(steam_utils.detect_steam_install_path(), "steamapps", "common", tostring(appid))
        end
    end

    _set_download_state(appid, {
        status = "downloading",
        currentApi = api_name,
        isBundleDownload = true,
        manifestUrl = manifest_url,
        fixUrl = fix_url,
        fixInstallPath = fix_install,
        manifestStatus = "downloading",
        fixStatus = fix_url and "downloading" or "not_available",
        bundleStep = 0,
        pendingExec = false,
        pollSeen = false,
        error = nil
    })

    if fix_url then
        return { success = true, isBundleDownload = true, fixUrl = fix_url }
    else
        logger.log("AdvgameTool: OnlineFix not available for " .. tostring(appid) .. ", proceeding with manifest-only")
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
    apiName = (apiName and apiName ~= "") and apiName or "AdvgameTool"

    logger.log("AdvgameTool: StartAddViaLuaToolsFromUrl appid=" .. tostring(appid) .. " api=" .. tostring(apiName))

    local dest_root = utils.ensure_temp_download_dir()
    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_state.json"))

    _set_download_state(appid, {
        status = "downloading",
        currentApi = apiName,
        url = url,
        bytesRead = 35,
        totalBytes = 100,
        pendingExec = true,
        pollSeen = false,
        error = nil
    })

    return { success = true }
end

function downloads.start_add_via_luatools(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    logger.log("AdvgameTool: StartAddViaLuaTools appid=" .. tostring(appid))
    local url, apiName = downloads.find_manifest_url_for_app(appid)
    if not url or url == "" then
        _set_download_state(appid, { status = "failed", error = "Not available on any API" })
        return { success = false, error = "Not available on any API" }
    end

    return downloads.start_add_via_luatools_from_url(appid, url, apiName)
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
        local unavailable_code = tonumber(api.unavailable_code) or 404

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
            local resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 4 })
            if resp and resp.status == success_code then
                available = true
            end
        else
            local success = false
            local resp = http_client.head(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 4 })
            if resp and resp.status == success_code then
                success = true
            elseif not string.find(url, "codeload%.github%.com") then
                -- Only fallback to GET if HEAD didn't already definitively report 404/unavailable
                local st = resp and tonumber(resp.status) or 0
                if st == 0 or st == 405 or st == 501 then
                    local get_resp = http_client.get(url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 4 })
                    if get_resp and get_resp.status == success_code then
                        success = true
                    end
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
