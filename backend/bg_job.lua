-- bg_job.lua
-- Background download + extract jobs (silent PowerShell on Windows, bash on Linux).
-- Each job communicates with the Lua side through small files in temp_dl:
--   <id>_state.json  -> {"status":"downloading|extracting|extracted|failed", "error":"...", "currentApi":"..."}
--   <id>.pid         -> PID of the worker (used for cancellation)
--   <id>_files.txt   -> optional list of extracted files (relative paths, one per line)

local m_utils = require("utils")
local fs      = require("fs")
local paths   = require("paths")
local logger  = require("plugin_logger")
local utils   = require("plugin_utils")
local cjson   = require("json")

local bg_job = {}

local UTF8_BOM = "\239\187\191"

local function is_windows()
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return true
    end
    local ok, os_env = pcall(function() return m_utils.getenv("OS") end)
    return ok and os_env == "Windows_NT"
end
bg_job.is_windows = is_windows

local function fwd(p)
    return (tostring(p or ""):gsub("\\", "/"))
end

local function win_slash(p)
    return (tostring(p or ""):gsub("/", "\\"))
end

--- Quote a string as a PowerShell single-quoted literal (escapes embedded quotes).
local function ps_quote(s)
    return "'" .. (tostring(s or ""):gsub("'", "''")) .. "'"
end

--- Quote a string for bash (single quotes).
local function sh_quote(s)
    return "'" .. (tostring(s or ""):gsub("'", "'\\''")) .. "'"
end

--- Returns the set of file paths used by a job id.
function bg_job.files_for(id)
    local root = utils.ensure_temp_download_dir()
    return {
        root   = root,
        state  = fs.join(root, id .. "_state.json"),
        pid    = fs.join(root, id .. ".pid"),
        list   = fs.join(root, id .. "_files.txt"),
        zip    = fs.join(root, id .. ".zip"),
        script = fs.join(root, id .. (is_windows() and "_dl.ps1" or "_dl.sh")),
    }
end

local PS_TEMPLATE = [==[
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Set-State([string]$s, [string]$e, [int]$br = 0, [int]$tb = 100, [string]$api = '') {
    $o = [ordered]@{ status = $s; bytesRead = $br; totalBytes = $tb }
    if ($api -ne '') { $o.currentApi = $api }
    if ($e) { $o.error = $e }
    [IO.File]::WriteAllText($sf, ($o | ConvertTo-Json -Compress))
}

function Invoke-RawDownload([string]$targetUrl, [string]$destFile) {
    if (Test-Path -LiteralPath $destFile) { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
    $ok = $false
    if ($targetUrl -match '^https?://' -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & curl.exe -sSL --fail --connect-timeout 15 --max-time 180 -A $ua -o $destFile $targetUrl 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destFile) -and (Get-Item -LiteralPath $destFile).Length -gt 0) {
                $ok = $true
            }
        } catch {}
        $ErrorActionPreference = $oldEap
    }
    if (-not $ok) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 3072 } catch {}
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = $ua
        $wc.DownloadFile($targetUrl, $destFile)
    }
    return ((Test-Path -LiteralPath $destFile) -and (Get-Item -LiteralPath $destFile).Length -gt 0)
}

function Invoke-SmartDownload([string]$targetUrl, [string]$destFile) {
    if (-not (Invoke-RawDownload $targetUrl $destFile)) { return $false }
    $fileLen = (Get-Item -LiteralPath $destFile).Length
    if ($fileLen -gt 0 -and $fileLen -lt 512) {
        $headTxt = [IO.File]::ReadAllText($destFile)
        if ($headTxt -match '^version https://git-lfs\.github\.com/spec/v1') {
            if ($targetUrl -match '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(?:refs/heads/)?([^/]+)/(.+)$') {
                $lfsOwner  = $Matches[1]
                $lfsRepo   = $Matches[2]
                $lfsBranch = $Matches[3]
                $lfsPath   = $Matches[4]
                $mediaUrl  = "https://media.githubusercontent.com/media/$lfsOwner/$lfsRepo/$lfsBranch/$lfsPath"
                if (-not (Invoke-RawDownload $mediaUrl $destFile)) {
                    $rawRedirectUrl = "https://github.com/$lfsOwner/$lfsRepo/raw/$lfsBranch/$lfsPath"
                    Invoke-RawDownload $rawRedirectUrl $destFile | Out-Null
                }
            }
        }
    }
    return ((Test-Path -LiteralPath $destFile) -and (Get-Item -LiteralPath $destFile).Length -gt 0)
}

try {
    [IO.File]::WriteAllText($pf, [string]$PID)

    $candidateSources = @()
    if ($sourcesJson -and $sourcesJson -ne '') {
        try {
            $parsed = ConvertFrom-Json $sourcesJson
            if ($parsed) {
                foreach ($item in @($parsed)) {
                    if ($item -and $item.url) {
                        $candidateSources += [PSCustomObject]@{
                            name = [string]($item.name)
                            url  = [string]($item.url)
                        }
                    }
                }
            }
        } catch {}
    }
    if ($candidateSources.Count -eq 0 -and $url -ne '') {
        $candidateSources += [PSCustomObject]@{ name = ''; url = $url }
    }
    if ($candidateSources.Count -eq 0) {
        throw 'Nenhuma URL de download disponivel'
    }

    $jobSuccess = $false
    $winningApi = ''
    $lastError  = 'Formato de arquivo invalido ou fonte indisponivel'
    $recordedFiles = New-Object System.Collections.Generic.List[string]

    foreach ($src in $candidateSources) {
        $curUrl = [string]$src.url
        $curApi = [string]$src.name
        try {
            Set-State 'downloading' '' 55 100 $curApi
            if (-not (Invoke-SmartDownload $curUrl $dp)) {
                $lastError = "Falha ao baixar de $curApi"
                continue
            }

            Set-State 'extracting' '' 85 100 $curApi
            if (Test-Path -LiteralPath $ed) {
                Remove-Item -LiteralPath $ed -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Path $ed -Force | Out-Null
            $root = [IO.Path]::GetFullPath($ed).TrimEnd('\', '/') + '\'
            $files = New-Object System.Collections.Generic.List[string]

            # Read magic bytes to verify archive format before invoking extractors
            $fsStream = [IO.File]::OpenRead($dp)
            $magic = New-Object byte[] 8
            $readCount = $fsStream.Read($magic, 0, 8)
            $fsStream.Close()

            $isZip  = ($readCount -ge 4 -and $magic[0] -eq 0x50 -and $magic[1] -eq 0x4B)
            $isGzip = ($readCount -ge 2 -and $magic[0] -eq 0x1F -and $magic[1] -eq 0x8B)
            $is7z   = ($readCount -ge 6 -and $magic[0] -eq 0x37 -and $magic[1] -eq 0x7A -and $magic[2] -eq 0xBC -and $magic[3] -eq 0xAF)
            $isRar  = ($readCount -ge 4 -and $magic[0] -eq 0x52 -and $magic[1] -eq 0x61 -and $magic[2] -eq 0x72 -and $magic[3] -eq 0x21)

            $extOk = $false
            if ($isZip) {
                try {
                    $zip = [IO.Compression.ZipFile]::OpenRead($dp)
                    try {
                        foreach ($en in $zip.Entries) {
                            $rel = $en.FullName.Replace('\', '/')
                            $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $rel))
                            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
                            if ($rel.EndsWith('/')) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
                            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                            [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $target, $true)
                            $files.Add($rel)
                        }
                        $extOk = $true
                    } finally { $zip.Dispose() }
                } catch {
                    try {
                        Expand-Archive -LiteralPath $dp -DestinationPath $ed -Force
                        $extOk = $true
                    } catch {}
                }
            }

            if (-not $extOk -and ($isZip -or $isGzip -or $is7z -or $isRar)) {
                if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
                    $oldEap = $ErrorActionPreference
                    $ErrorActionPreference = 'Continue'
                    try {
                        & tar.exe -xf $dp -C $ed 2>$null
                        if ($LASTEXITCODE -eq 0) { $extOk = $true }
                    } catch {}
                    $ErrorActionPreference = $oldEap
                }
            }

            if (-not $extOk) {
                # Check if the API returned a raw .lua script directly instead of an archive
                $fileLen = (Get-Item -LiteralPath $dp).Length
                if ($fileLen -gt 10 -and $fileLen -lt 524288) {
                    $rawText = [IO.File]::ReadAllText($dp)
                    if ($rawText -notmatch '(?i)<!DOCTYPE|<html' -and $rawText -match 'addappid\s*\(|setManifestid\s*\(') {
                        $luaName = if ($appidStr -ne '') { "$appidStr.lua" } else { 'manifest.lua' }
                        $destLua = Join-Path $ed $luaName
                        [IO.File]::WriteAllText($destLua, $rawText)
                        $files.Add($luaName)
                        $extOk = $true
                    }
                }
            }

            if (-not $extOk) {
                $lastError = "A fonte '$curApi' retornou um formato invalido (nao e um arquivo .zip/.lua valido)"
                continue
            }

            if ($depotCache -ne '' -or $targetLua -ne '') {
                if ($depotCache -ne '' -and -not (Test-Path -LiteralPath $depotCache)) {
                    New-Item -ItemType Directory -Path $depotCache -Force | Out-Null
                }
                $targetDir = if ($targetLua -ne '') { [IO.Path]::GetDirectoryName($targetLua) } else { '' }
                if ($targetDir -ne '' -and -not (Test-Path -LiteralPath $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                $manifestFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.manifest')
                if ($depotCache -ne '' -and $manifestFiles.Count -gt 0) {
                    foreach ($mf in $manifestFiles) {
                        Copy-Item -LiteralPath $mf.FullName -Destination (Join-Path $depotCache $mf.Name) -Force
                    }
                }
                $luaWritten = $false
                if ($targetLua -ne '') {
                    $luaFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.lua')
                    $chosenLua = $luaFiles | Where-Object { $_.Name -eq ($appidStr + '.lua') } | Select-Object -First 1
                    if (-not $chosenLua) {
                        $chosenLua = $luaFiles | Where-Object { $_.Name -match '^\d+\.lua$' } | Select-Object -First 1
                    }
                    if (-not $chosenLua -and $luaFiles.Count -gt 0) {
                        $chosenLua = $luaFiles[0]
                    }
                    if ($chosenLua) {
                        $text = [IO.File]::ReadAllText($chosenLua.FullName)
                        $text = [Text.RegularExpressions.Regex]::Replace($text, '(?m)^(\s*)(setManifestid\()', '$1-- $2')
                        [IO.File]::WriteAllText($targetLua, $text)
                        $luaWritten = $true
                    } else {
                        $vdfFiles = @(Get-ChildItem -LiteralPath $ed -Recurse -File -Filter '*.vdf')
                        $depotKeys = @{}
                        foreach ($vf in $vdfFiles) {
                            $vdfText = [IO.File]::ReadAllText($vf.FullName)
                            $matches = [Text.RegularExpressions.Regex]::Matches($vdfText, '"(\d+)"\s*\{[\s\S]*?"[Dd]ecryption[Kk]ey"\s*"([0-9a-fA-F]{64})"')
                            foreach ($m in $matches) {
                                $depotKeys[$m.Groups[1].Value] = $m.Groups[2].Value
                            }
                        }
                        if ($depotKeys.Count -gt 0 -or $manifestFiles.Count -gt 0) {
                            $genLines = New-Object System.Collections.Generic.List[string]
                            if ($appidStr -ne '') { $genLines.Add('addappid(' + $appidStr + ')') }
                            foreach ($dk in $depotKeys.GetEnumerator()) {
                                $genLines.Add('addappid(' + $dk.Key + ', 1, "' + $dk.Value + '")')
                            }
                            foreach ($mf in $manifestFiles) {
                                if ($mf.BaseName -match '^(\d+)_(\d+)$') {
                                    $dId = $Matches[1]
                                    $mId = $Matches[2]
                                    if (-not $depotKeys.ContainsKey($dId)) {
                                        $genLines.Add('addappid(' + $dId + ')')
                                    }
                                    $genLines.Add('-- setManifestid(' + $dId + ', "' + $mId + '", 0)')
                                }
                            }
                            [IO.File]::WriteAllText($targetLua, ($genLines -join "`n"))
                            $luaWritten = $true
                        }
                    }
                }
                if (-not $luaWritten -and $manifestFiles.Count -eq 0) {
                    $lastError = "Nenhum arquivo .lua ou .manifest encontrado em '$curApi'"
                    continue
                }
            }

            $recordedFiles = $files
            $winningApi = $curApi
            $jobSuccess = $true
            break
        } catch {
            $lastError = $_.Exception.Message
            continue
        }
    }

    if (-not $jobSuccess) {
        throw $lastError
    }

    if ($lf) { [IO.File]::WriteAllLines($lf, $recordedFiles) }
    Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue
    Set-State 'extracted' '' 100 100 $winningApi
} catch {
    Set-State 'failed' ($_.Exception.Message) 0 100
} finally {
    Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
}
]==]

--- Launch a background job.
-- opts: { id, url, sources, extract_dir, record_files (bool), user_agent, appid, depot_cache, target_lua }
function bg_job.launch(opts)
    local f = bg_job.files_for(opts.id)
    local extract_dir = opts.extract_dir
    if not fs.exists(extract_dir) then pcall(fs.create_directories, extract_dir) end

    -- Clean leftovers of previous runs
    pcall(fs.remove, f.list)
    pcall(fs.remove, f.zip)
    pcall(fs.remove, f.pid)
    m_utils.write_file(f.state, '{"status":"queued","bytesRead":35,"totalBytes":100}')

    local ua = opts.user_agent or "ManifestAdvTools"
    local list_file = opts.record_files and f.list or ""
    local depot_cache = opts.depot_cache and fwd(opts.depot_cache) or ""
    local target_lua  = opts.target_lua and fwd(opts.target_lua) or ""
    local appid_str   = opts.appid and tostring(opts.appid) or ""
    local sources_json = ""
    if type(opts.sources) == "table" and #opts.sources > 0 then
        local ok_s, s_enc = pcall(cjson.encode, opts.sources)
        if ok_s and s_enc then sources_json = s_enc end
    end

    if is_windows() then
        local header =
            "$sf          = " .. ps_quote(fwd(f.state)) .. "\r\n" ..
            "$pf          = " .. ps_quote(fwd(f.pid)) .. "\r\n" ..
            "$url         = " .. ps_quote(opts.url or "") .. "\r\n" ..
            "$sourcesJson = " .. ps_quote(sources_json) .. "\r\n" ..
            "$dp          = " .. ps_quote(fwd(f.zip)) .. "\r\n" ..
            "$ed          = " .. ps_quote(fwd(extract_dir)) .. "\r\n" ..
            "$lf          = " .. ps_quote(list_file ~= "" and fwd(list_file) or "") .. "\r\n" ..
            "$ua          = " .. ps_quote(ua) .. "\r\n" ..
            "$depotCache  = " .. ps_quote(depot_cache) .. "\r\n" ..
            "$targetLua   = " .. ps_quote(target_lua) .. "\r\n" ..
            "$appidStr    = " .. ps_quote(appid_str) .. "\r\n"
        local body = PS_TEMPLATE:gsub("\r?\n", "\r\n")
        -- Write the PowerShell script with UTF-8 BOM so Windows PowerShell 5 reads non-ASCII paths properly
        m_utils.write_file(f.script, UTF8_BOM .. header .. body)

        local vbs_path = fs.join(paths.get_plugin_dir(), "backend", "silent_run.vbs")
        local win_vbs = win_slash(vbs_path)
        local win_script = win_slash(f.script)
        if fs.exists(vbs_path) then
            m_utils.exec('wscript.exe //b //nologo "' .. win_vbs .. '" "' .. win_script .. '"')
        else
            m_utils.exec('powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. win_script .. '"')
        end
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec("chmod +x " .. sh_quote(sh_path))
        local cmd = string.format("nohup bash %s %s %s %s %s %s %s %s %s %s >/dev/null 2>&1 &",
            sh_quote(sh_path), sh_quote(opts.url or ""), sh_quote(f.zip), sh_quote(extract_dir),
            sh_quote(f.state), sh_quote(list_file), sh_quote(f.pid),
            sh_quote(depot_cache), sh_quote(target_lua), sh_quote(appid_str))
        m_utils.exec(cmd)
    end
    logger.log("bg_job: launched '" .. opts.id .. "' -> " .. tostring(opts.url))
    return true
end

--- Read job state. Returns table (status=nil if no state file exists).
function bg_job.read_state(id)
    local f = bg_job.files_for(id)
    if not fs.exists(f.state) then return {} end
    local c = m_utils.read_file(f.state)
    if not c or c == "" then return { status = "downloading", bytesRead = 45, totalBytes = 100 } end
    -- strip BOM if any
    if c:sub(1, 3) == UTF8_BOM then c = c:sub(4) end
    local ok, d = pcall(cjson.decode, c)
    if not (ok and type(d) == "table") then
        return { status = "downloading", bytesRead = 45, totalBytes = 100 }
    end

    -- Fallback if wscript.exe was blocked by Windows Script Host / Defender and PowerShell never started:
    if d.status == "queued" and is_windows() then
        if not d.FallbackReady then
            m_utils.write_file(f.state, '{"status":"queued","bytesRead":45,"totalBytes":100,"FallbackReady":true}')
            return { status = "downloading", bytesRead = 45, totalBytes = 100 }
        elseif not fs.exists(f.pid) and fs.exists(f.script) then
            local win_script = win_slash(f.script)
            m_utils.exec('powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. win_script .. '"')
            local c2 = m_utils.read_file(f.state) or ""
            if c2:sub(1, 3) == UTF8_BOM then c2 = c2:sub(4) end
            local ok2, d2 = pcall(cjson.decode, c2)
            if ok2 and type(d2) == "table" then return d2 end
        end
        return { status = "downloading", bytesRead = 50, totalBytes = 100 }
    end

    return d
end

function bg_job.write_state(id, tbl)
    local f = bg_job.files_for(id)
    local ok, s = pcall(cjson.encode, tbl)
    if ok then m_utils.write_file(f.state, s) end
end

--- Read list of extracted files recorded by the job.
function bg_job.read_file_list(id)
    local f = bg_job.files_for(id)
    local out = {}
    if not fs.exists(f.list) then return out end
    local c = m_utils.read_file(f.list) or ""
    if c:sub(1, 3) == UTF8_BOM then c = c:sub(4) end
    for line in c:gmatch("[^\r\n]+") do
        local t = line:match("^%s*(.-)%s*$")
        if t and t ~= "" then table.insert(out, t) end
    end
    return out
end

--- Kill a running job (if still alive) and mark it as cancelled.
function bg_job.cancel(id, reason)
    local f = bg_job.files_for(id)
    if fs.exists(f.pid) then
        local pid = tonumber((m_utils.read_file(f.pid) or ""):match("(%d+)"))
        if pid then
            if is_windows() then
                pcall(m_utils.exec, "taskkill /PID " .. pid .. " /T /F >nul 2>&1")
            else
                pcall(m_utils.exec, "kill " .. pid .. " >/dev/null 2>&1")
            end
        end
    end
    bg_job.write_state(id, { status = "cancelled", error = reason or "Cancelled by user" })
    bg_job.cleanup(id, true)
end

--- Remove temp files of a job. keep_state=true keeps the state file.
function bg_job.cleanup(id, keep_state)
    local f = bg_job.files_for(id)
    pcall(fs.remove, f.zip)
    pcall(fs.remove, f.pid)
    pcall(fs.remove, f.list)
    pcall(fs.remove, f.script)
    if not keep_state then pcall(fs.remove, f.state) end
end

return bg_job
