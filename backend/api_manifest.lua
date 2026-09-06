local fs = require("fs")
local config = require("config")
local http_client = require("http_client")
local logger = require("plugin_logger")
local utils = require("plugin_utils")
local paths = require("paths")

local api_manifest = {}

local _APIS_INIT_DONE = false
local _INIT_APIS_LAST_MESSAGE = ""

local DEFAULT_FREE_APIS = {
    {
        name = "Ryuu",
        url = "http://167.235.229.108/<appid>",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "Raian Manifests",
        url = "https://raw.githubusercontent.com/raianffyt2222/reporaianlmm/refs/heads/main/<appid>.zip",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "Sushi",
        url = "https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/<appid>.zip",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "GOG Pirate Repo",
        url = "https://raw.githubusercontent.com/Mysticf1/GOG-Pirate-Lua-Manifest-Repo/refs/heads/main/<appid>.zip",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "LuaDepot Games",
        url = "https://raw.githubusercontent.com/LuaDepot/LuaDeopot-games/refs/heads/main/<appid>.zip",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "Angel Manifest",
        url = "https://raw.githubusercontent.com/Angelpro09xd/manifestrepo/refs/heads/main/<appid>.zip",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    },
    {
        name = "Morrenus",
        url = "https://hubcapmanifest.com/api/v1/manifest/<appid>?api_key=<moapikey>",
        success_code = 200,
        unavailable_code = 404,
        enabled = true
    }
}

function api_manifest.init_apis()
    logger.log("InitApis: invoked")
    if _APIS_INIT_DONE then
        logger.log("InitApis: already completed this session, skipping")
        return { success = true, message = _INIT_APIS_LAST_MESSAGE }
    end

    local api_json_path = paths.backend_path(config.API_JSON_FILE)
    local message = ""

    if not fs.exists(api_json_path) then
        logger.log("InitApis: Local file not found -> initializing default APIs")
        local initial_data = { api_list = DEFAULT_FREE_APIS }
        local encoded = utils.encode_json(initial_data)
        utils.write_text(api_json_path, utils.normalize_manifest_text(encoded))
        message = "Loaded " .. tostring(#DEFAULT_FREE_APIS) .. " Free APIs :D"
    else
        logger.log("InitApis: Local file exists -> " .. api_json_path)
    end

    _APIS_INIT_DONE = true
    _INIT_APIS_LAST_MESSAGE = message
    logger.log("InitApis: completed message=" .. tostring(message))
    return { success = true, message = message }
end

function api_manifest.get_init_apis_message()
    logger.log("InitApis: GetInitApisMessage invoked")
    local msg = _INIT_APIS_LAST_MESSAGE or ""
    if msg ~= "" then
        logger.log("InitApis: delivering queued message -> " .. msg)
    end
    _INIT_APIS_LAST_MESSAGE = ""
    return { success = true, message = msg }
end

function api_manifest.store_last_message(message)
    _INIT_APIS_LAST_MESSAGE = message or ""
end

function api_manifest.fetch_free_apis_now()
    logger.log("ManifestAdvTools: FetchFreeApisNow invoked")
    local manifest_text = ""

    logger.log("ManifestAdvTools: Fetching manifest from " .. config.API_MANIFEST_URL)
    local resp = http_client.get(config.API_MANIFEST_URL, { timeout = 15 })
    if resp and resp.status == 200 and resp.body then
        manifest_text = resp.body
        logger.log("ManifestAdvTools: Fetched manifest from primary URL")
    else
        logger.warn("ManifestAdvTools: Primary manifest URL failed, trying proxy...")
        resp = http_client.get(config.API_MANIFEST_PROXY_URL, { timeout = config.HTTP_PROXY_TIMEOUT_SECONDS })
        if resp and resp.status == 200 and resp.body then
            manifest_text = resp.body
            logger.log("ManifestAdvTools: Fetched manifest from proxy URL")
        else
            logger.warn("ManifestAdvTools: Proxy manifest URL also failed")
        end
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local current_data = utils.read_json(path)
    local current_list = {}
    if current_data and type(current_data.api_list) == "table" then
        current_list = current_data.api_list
    end

    local existing_names = {}
    for _, api in ipairs(current_list) do
        if api.name then existing_names[string.lower(api.name)] = true end
    end

    -- Ensure all default known free APIs are present
    for _, def in ipairs(DEFAULT_FREE_APIS) do
        if not existing_names[string.lower(def.name)] then
            table.insert(current_list, {
                name = def.name,
                url = def.url,
                success_code = def.success_code,
                unavailable_code = def.unavailable_code,
                enabled = def.enabled ~= false
            })
            existing_names[string.lower(def.name)] = true
        end
    end

    -- Also merge any new remote APIs without overwriting existing
    if manifest_text ~= "" then
        local ok, parsed = pcall(utils.decode_json, utils.normalize_manifest_text(manifest_text))
        if ok and type(parsed) == "table" and type(parsed.api_list) == "table" then
            for _, r_api in ipairs(parsed.api_list) do
                if r_api.name and not existing_names[string.lower(r_api.name)] then
                    table.insert(current_list, r_api)
                    existing_names[string.lower(r_api.name)] = true
                end
            end
        end
    end

    local final_text = utils.encode_json({ api_list = current_list })
    utils.write_text(path, utils.normalize_manifest_text(final_text))
    return { success = true, count = #current_list }
end

function api_manifest.load_api_manifest()
    local path = paths.backend_path(config.API_JSON_FILE)
    local text = utils.read_text(path)

    local normalized = utils.normalize_manifest_text(text)
    if normalized and normalized ~= text and normalized ~= "" then
        utils.write_text(path, normalized)
        logger.log("ManifestAdvTools: Normalized api.json")
        text = normalized
    end

    local data = utils.read_json(path)
    local apis = {}
    if data and type(data.api_list) == "table" then
        for _, api in ipairs(data.api_list) do
            if api.enabled then
                table.insert(apis, api)
            end
        end
    end
    return apis
end

function api_manifest.add_custom_api(payload)
    if not payload or type(payload.name) ~= "string" or type(payload.url) ~= "string" then
        return { success = false, error = "Invalid payload: name and url are required" }
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local text = ""
    if fs.exists(path) then
        text = utils.read_text(path)
    end

    local data = { api_list = {} }
    if text ~= "" then
        local ok, parsed = pcall(utils.decode_json, text)
        if ok and type(parsed) == "table" and type(parsed.api_list) == "table" then
            data = parsed
        end
    end

    local new_api = {
        name = payload.name,
        url = payload.url,
        success_code = payload.success_code or 200,
        unavailable_code = payload.unavailable_code or 404,
        enabled = true
    }
    
    if payload.api_key and payload.api_key ~= "" then
        new_api.api_key = payload.api_key
    end

    table.insert(data.api_list, new_api)

    local new_text = utils.encode_json(data)
    local formatted = utils.normalize_manifest_text(new_text)
    utils.write_text(path, formatted)
    
    logger.log("ManifestAdvTools: Added custom API: " .. payload.name)
    return { success = true }
end

function api_manifest.get_api_list()
    local success, apis = pcall(api_manifest.load_api_manifest)
    if not success then
        return { success = false, error = tostring(apis), apis = {} }
    end

    local morrenus_api_key = ""
    local ok, sm = pcall(require, "settings.manager")
    if ok and sm and sm.get_morrenus_api_key then
        morrenus_api_key = sm.get_morrenus_api_key() or ""
    end

    local api_names = {}
    for i, api in ipairs(apis) do
        local url = api.url or ""
        if not (string.find(url, "<moapikey>") and (not morrenus_api_key or morrenus_api_key == "")) then
            table.insert(api_names, { name = api.name or "Unknown", index = i - 1 })
        end
    end

    return { success = true, apis = api_names }
end

function api_manifest.get_all_apis()
    local path = paths.backend_path(config.API_JSON_FILE)
    local data = utils.read_json(path)
    local apis = {}
    if data and type(data.api_list) == "table" then
        for _, api in ipairs(data.api_list) do
            table.insert(apis, {
                name    = api.name or "Unknown",
                url     = api.url or "",
                enabled = api.enabled ~= false  -- default true
            })
        end
    end
    return { success = true, apis = apis }
end

function api_manifest.toggle_api(name)
    if not name or type(name) ~= "string" or name == "" then
        return { success = false, error = "name is required" }
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local data = utils.read_json(path)
    if not data or type(data.api_list) ~= "table" then
        return { success = false, error = "Failed to load api.json" }
    end

    local found = false
    local new_state = false
    for _, api in ipairs(data.api_list) do
        if api.name == name then
            api.enabled = not (api.enabled ~= false)
            new_state = api.enabled
            found = true
            break
        end
    end

    if not found then
        return { success = false, error = "API not found: " .. name }
    end

    local new_text = utils.encode_json(data)
    local formatted = utils.normalize_manifest_text(new_text)
    utils.write_text(path, formatted)

    logger.log("ManifestAdvTools: Toggled API '" .. name .. "' -> " .. tostring(new_state))
    return { success = true, enabled = new_state }
end

function api_manifest.remove_api(name)
    if not name or type(name) ~= "string" or name == "" then
        return { success = false, error = "name is required" }
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local data = utils.read_json(path)
    if not data or type(data.api_list) ~= "table" then
        return { success = false, error = "Failed to load api.json" }
    end

    local new_list = {}
    local found = false
    for _, api in ipairs(data.api_list) do
        if api.name == name then
            found = true
        else
            table.insert(new_list, api)
        end
    end

    if not found then
        return { success = false, error = "API not found: " .. name }
    end

    data.api_list = new_list
    local new_text = utils.encode_json(data)
    local formatted = utils.normalize_manifest_text(new_text)
    utils.write_text(path, formatted)

    logger.log("ManifestAdvTools: Removed API '" .. name .. "'")
    return { success = true }
end

function api_manifest.rename_api(old_name, new_name)
    if not old_name or old_name == "" or not new_name or new_name == "" then
        return { success = false, error = "old_name and new_name are required" }
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local data = utils.read_json(path)
    if not data or type(data.api_list) ~= "table" then
        return { success = false, error = "Failed to load api.json" }
    end

    local found = false
    for _, api in ipairs(data.api_list) do
        if api.name == old_name then
            api.name = new_name
            found = true
            break
        end
    end

    if not found then
        return { success = false, error = "API not found: " .. old_name }
    end

    local new_text = utils.encode_json(data)
    local formatted = utils.normalize_manifest_text(new_text)
    utils.write_text(path, formatted)

    logger.log("ManifestAdvTools: Renamed API '" .. old_name .. "' -> '" .. new_name .. "'")
    return { success = true }
end

function api_manifest.set_api_order(ordered_names)
    if type(ordered_names) ~= "table" then
        return { success = false, error = "ordered_names must be a table" }
    end

    local path = paths.backend_path(config.API_JSON_FILE)
    local data = utils.read_json(path)
    if not data or type(data.api_list) ~= "table" then
        return { success = false, error = "Failed to load api.json" }
    end

    local new_list = {}
    local added = {}

    -- Add items in the requested order
    for _, name in ipairs(ordered_names) do
        for _, api in ipairs(data.api_list) do
            if api.name == name and not added[name] then
                table.insert(new_list, api)
                added[name] = true
                break
            end
        end
    end

    -- Add any items that were left out of the ordered list (safeguard)
    for _, api in ipairs(data.api_list) do
        if not added[api.name] then
            table.insert(new_list, api)
        end
    end

    data.api_list = new_list
    local new_text = utils.encode_json(data)
    local formatted = utils.normalize_manifest_text(new_text)
    utils.write_text(path, formatted)

    logger.log("ManifestAdvTools: Reordered APIs")
    return { success = true }
end

return api_manifest
