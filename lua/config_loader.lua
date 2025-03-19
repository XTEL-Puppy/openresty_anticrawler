local cjson = require "cjson"
local lfs = require "lfs_ffi"
local cache = ngx.shared.config_cache  -- 共享内存
local file_path = "/usr/local/openresty/nginx/json/" -- 规则文件目录

local _M = {}

-- 记录上次加载的文件修改时间
local last_modified_times = {}
local current_version = nil

-- 读取 JSON 文件
local function load_json(filename)
    local f, err = io.open(file_path .. filename, "r")
    if not f then
        ngx.log(ngx.ERR, "Failed to open file: ", filename, " - ", err)
        return nil
    end
    local content = f:read("*a")
    f:close()
    
    local data, err = cjson.decode(content)
    if not data then
        ngx.log(ngx.ERR, "Failed to parse JSON: ", filename, " - ", err)
        return nil
    end
    return data
end

-- 检查文件是否被修改
local function is_file_modified(filename)

    local attr = lfs.attributes(file_path .. filename)
    if not attr then
        ngx.log(ngx.ERR, "Failed to get file attributes: ", filename)
        return false
    end
    local mtime = attr.modification

    if not mtime then
        ngx.log(ngx.ERR, "Error getting file mtime: ", err)  -- 记录到 OpenResty 日志
        return false
    end

    -- 如果记录的修改时间为空，说明是第一次加载
    if not last_modified_times[filename] then
        last_modified_times[filename] = mtime
        return true
    end

    -- 检查是否修改过
    if last_modified_times[filename] ~= mtime then
        last_modified_times[filename] = mtime
        return true
    end

    return false
end

-- 检查是否变换规则版本
local function is_rule_reloaded(new_version)
    if not current_version or current_version ~= new_version then  -- current_version 为空 或 版本号不同
        ngx.log(ngx.INFO, "Rule version changed: ", current_version or "nil", " → ", new_version)
        return true
    end
    return false
end


-- 加载规则
function _M.load_rules()
    -- **检查 preprocess.json 是否修改**
    if not is_file_modified("preprocess.json") then
        -- ngx.log(ngx.INFO, "preprocess.json not modified, skipping reload")
        return true
    end

    -- 加载 preprocess.json
    local preprocess_data = load_json("preprocess.json")
    if not preprocess_data then
        ngx.log(ngx.ERR, "Failed to load preprocess.json")
        return false
    end

    ngx.log(ngx.INFO, "preprocess.json is modified")

    -- 缓存 preprocess.json 规则集
    cache:set("preprocess_rules", cjson.encode(preprocess_data))

    -- 选择 rule1.json 或 rule2.json
    local rule_version = preprocess_data.meta.rule_version or 1     -- 获取当前版本号
    local rule_file = "rule_" .. rule_version .. ".json"  -- 动态拼接文件名

    local force_reload = is_rule_reloaded(rule_version)  -- 计算是否需要强制重载
    -- 如果规则文件被修改，或者需要强制重载，则执行重载
    if is_file_modified(rule_file) or force_reload then
        current_version = rule_version  -- 更新当前版本号

        -- 加载 rule.json
        local rule_data = load_json(rule_file)
        if not rule_data then
            ngx.log(ngx.ERR, "Failed to load ", rule_file)
            return false
        end

        -- 缓存 rule.json 规则集
        cache:set("version_rules", cjson.encode(rule_data))
        ngx.log(ngx.INFO, "Loaded rules from ", rule_file, force_reload and " (force reload)" or "")
    -- else
        -- ngx.log(ngx.INFO, rule_file, " is loaded well, skipping reload")
    end
end

-- 获取规则
-- rule_type = preprocess/version
function _M.get_rules(rule_type)
    local key = rule_type .. "_rules"
    local rules_json = cache:get(key)
    if not rules_json then
        ngx.log(ngx.ERR, "Rules not found in cache: ", rule_type)
        return nil
    end
    return cjson.decode(rules_json)
end

-- 定时器函数
local function check_update(premature)
    if premature then
        return
    end

    -- 重新加载规则
    _M.load_rules()

    -- 10 秒后再次检查
    local ok, err = ngx.timer.at(10, check_update)
    if not ok then
        ngx.log(ngx.ERR, "Failed to create timer: ", err)
        -- 3 秒后重试，避免定时器彻底停掉
        ngx.timer.at(3, check_update)
    end
end


-- 初始化定时器
function _M.start_watch()
    -- 只在 worker 0 上启动定时器，防止多个 worker 进程重复执行
    if ngx.worker.id() == 0 then
        local ok, err = ngx.timer.at(0, check_update)
        if not ok then
            ngx.log(ngx.ERR, "Failed to start config watcher: ", err)
        else
            ngx.log(ngx.INFO, "Config watcher started successfully.")
        end
    end
end


return _M

