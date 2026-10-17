-- bg_job.lua
-- Background download + extract jobs (silent PowerShell on Windows, bash on Linux).
-- Each job communicates with the Lua side through small files in temp_dl:
--   <id>_state.json  -> {"status":"downloading|extracting|extracted|failed", "error":"..."}
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
    return m_utils.getenv("OS") == "Windows_NT"
end
bg_job.is_windows = is_windows

local function fwd(p)
    return (tostring(p or ""):gsub("\\", "/"))
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
function Set-State([string]$s, [string]$e) {
    $o = [ordered]@{ status = $s }
    if ($e) { $o.error = $e }
    [IO.File]::WriteAllText($sf, ($o | ConvertTo-Json -Compress))
}
try {
    [IO.File]::WriteAllText($pf, [string]$PID)
    Set-State 'downloading' ''
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 3072 } catch {}
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = $ua
    $wc.DownloadFile($url, $dp)
    Set-State 'extracting' ''
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $ed)) { New-Item -ItemType Directory -Path $ed -Force | Out-Null }
    $root = [IO.Path]::GetFullPath($ed).TrimEnd('\', '/') + '\'
    $files = New-Object System.Collections.Generic.List[string]
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
    } finally { $zip.Dispose() }
    if ($lf) { [IO.File]::WriteAllLines($lf, $files) }
    Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue
    Set-State 'extracted' ''
} catch {
    Set-State 'failed' ($_.Exception.Message)
} finally {
    Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
}
]==]

--- Launch a background job.
-- opts: { id, url, extract_dir, record_files (bool), user_agent }
function bg_job.launch(opts)
    local f = bg_job.files_for(opts.id)
    local extract_dir = opts.extract_dir
    if not fs.exists(extract_dir) then fs.create_directories(extract_dir) end

    -- Clean leftovers of previous runs
    pcall(fs.remove, f.list)
    pcall(fs.remove, f.zip)
    m_utils.write_file(f.state, '{"status":"downloading"}')

    local ua = opts.user_agent or "ManifestAdvTools"
    local list_file = opts.record_files and f.list or ""

    if is_windows() then
        local header =
            "$sf  = " .. ps_quote(fwd(f.state)) .. "\r\n" ..
            "$pf  = " .. ps_quote(fwd(f.pid)) .. "\r\n" ..
            "$url = " .. ps_quote(opts.url) .. "\r\n" ..
            "$dp  = " .. ps_quote(fwd(f.zip)) .. "\r\n" ..
            "$ed  = " .. ps_quote(fwd(extract_dir)) .. "\r\n" ..
            "$lf  = " .. ps_quote(list_file ~= "" and fwd(list_file) or "") .. "\r\n" ..
            "$ua  = " .. ps_quote(ua) .. "\r\n"
        local body = PS_TEMPLATE:gsub("\r?\n", "\r\n")
        -- BOM so Windows PowerShell 5 reads non-ASCII paths (user names with accents) correctly
        local vbs_path = fs.join(paths.get_plugin_dir(), "backend", "silent_run.vbs")
        if fs.exists(vbs_path) then
            m_utils.exec('wscript.exe //b //nologo "' .. vbs_path .. '" "' .. f.script .. '"')
        else
            m_utils.exec('cmd.exe /c start /b "" powershell.exe -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File "' .. f.script .. '"')
        end
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec("chmod +x " .. sh_quote(sh_path))
        local cmd = string.format("nohup bash %s %s %s %s %s %s %s >/dev/null 2>&1 &",
            sh_quote(sh_path), sh_quote(opts.url), sh_quote(f.zip), sh_quote(extract_dir),
            sh_quote(f.state), sh_quote(list_file), sh_quote(f.pid))
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
    if not c or c == "" then return { status = "downloading" } end
    -- strip BOM if any
    if c:sub(1, 3) == UTF8_BOM then c = c:sub(4) end
    local ok, d = pcall(cjson.decode, c)
    if ok and type(d) == "table" then return d end
    return { status = "downloading" }
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
