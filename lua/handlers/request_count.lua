local config_module = require "config_loader"
local usr_bwlist = require "handlers.usr_bwList"

local _M = {}

local config = config_module.get_rules("version")
local config_preprocess = config_module.get_rules("preprocess").preprocess[5]

local function get_handler()
    if config.meta.current_version then
        if config.meta.current_version == 1 then
            return config.rules[1]
        elseif config.meta.current_version == 2 then
            return config.rules[2]
        end
    end

    return nil
end

local function request_count_exceed(handler, redis, fingerprint)

    local script = [[
        local key = KEYS[1]
        local threshold_value = tonumber(ARGV[2])
        local expire_time_count = ARGV[1]
        local blist_key = KEYS[2]
        local fingerprint = ARGV[3]
        local expire_time_blist = ARGV[4]
        local current_time = ARGV[5]

        -- 1. 先检查黑名单
        local exists_time = redis.call("ZSCORE", blist_key, fingerprint)
        if exists_time and exists_time > current_time then
            return 2  -- 2 代表已经在黑名单，不增加计数
        end

        -- 2. 增加计数并设置过期时间
        local count = redis.call("INCR", key)
        if count == 1 then
            redis.call("EXPIRE", key, expire_time_count)
        end

        -- 3. 判断是否超过阈值
        if count >= threshold_value then
            redis.call("ZADD", blist_key, expire_time_blist, fingerprint)
            return 1
        end
        return 0
    ]]

    local threshold_value = handler.threshold.requests
    local expire_time_count = handler.threshold.interval
    local expire_time_blist = config_preprocess.interval


    expire_time_blist = expire_time_blist + ngx.time()

    -- 执行脚本时传递额外参数
    local result = redis:eval(
        script, 
        2,  -- KEYS数量
        fingerprint,  -- KEYS[1]: 计数键
        "usr_Blist",  -- KEYS[2]: 黑名单键
        expire_time_count,  -- ARGV[1]: 计数过期时间
        threshold_value,  -- ARGV[2]: 阈值
        fingerprint,  -- ARGV[3]: 用户指纹
        expire_time_blist,  -- ARGV[4]: 黑名单过期时间
        ngx.time()   -- ARGV[5]: 当前时间
    )

    if result == 1 then
        ngx.log(ngx.INFO, "A new user is added into user BlackList.IP: ", ngx.ctx.ip, " and fingerprint: ", fingerprint, " and interval: ", config_preprocess.interval)
        return true
    elseif result == 0 then
        ngx.log(ngx.INFO, "IP: ", ngx.ctx.ip, " is count......")
        return false
    elseif result == 2 then
        return true
    else
        ngx.log(ngx.ERR, "Redis error: ", err)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

function _M.process(redis, fingerprint, count_type)

    local handler = nil

    if count_type == "ipua" then
        handler = get_handler()
        ngx.log(ngx.INFO, "ipua counting!")

    elseif count_type == "cookie" then
        handler = config.rules[3]
        ngx.log(ngx.INFO, "cookie counting!")

    else
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    if not handler then
        ngx.log(ngx.ERR, "Handler is nil, the version is invalid configuration.")
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    if not handler.enable then return end 

    if request_count_exceed(handler, redis, fingerprint) then
        
        if handler.action == "refuse" then
            return ngx.exit(403)

        elseif handler.action == "captcha" then
            local original_url = ngx.var.request_uri
            return ngx.redirect("/captcha?fp=" .. fingerprint .. "&redirect=" .. ngx.escape_uri(original_url), ngx.HTTP_MOVED_TEMPORARILY)

        else
            return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end

    end

    -- 未超限，正常返回
    return

end


return _M
