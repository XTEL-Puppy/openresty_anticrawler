local config_module = require "config_loader"
local redis_iresty = require "tools.redis_iresty"

-- 获取json文件转换而来的lua表
local config = config_module.get_rules("preprocess")


local _M = {}


--[[
fingerprint 预计使用 xxhash32 计算 (IP..UA) 得到32位低碰撞率的用户指纹
官方文档显示XXHASH具有与生日悖论一致的良好结果，而对于32位hash值，大概93000条目时碰撞概率为1%
对于该小型系统而言足够了，同时xxhash32比xxhash64能减少50%的内存
--]] 

--[[
priority=4 黑名单有序集合 key=usr_Blist; score=now+interval; value=fingerprint (xxhash32(IP..UA))
priority=5 白名单有序集合 key=usr_Wlist; score=now+interval; value=fingerprint
--]]

-- 添加到白名单
function _M.add_to_Wlist(redis, ip, fingerprint)
    if not redis then return end
    local interval = config.preprocess[3].interval
    local expire_time = ngx.time() + interval  -- 当前时间 + interval

    -- Redis 保证 EVAL 命令执行的脚本的原子性
    local script = [[
        local whitelist_key = KEYS[1]
        local fingerprint = ARGV[1]
        local expire_time = ARGV[2]

        -- 检查是否已存在
        local exists = redis.call("ZSCORE", whitelist_key, fingerprint)
        if not exists then
            -- 如果不存在，则添加到白名单
            redis.call("ZADD", whitelist_key, expire_time, fingerprint)
            return 1  -- 成功添加
        else
            return 0  -- 已存在，跳过添加
        end
    ]]

    local result = redis:eval(script, 1, "usr_Wlist", fingerprint, expire_time)
    if result == 1 then
        ngx.log(ngx.INFO, "A new user is added into user WhiteList. IP: ", ip, " and fingerprint: ", fingerprint, " and interval: ", interval)
    end    

end


-- 添加到黑名单
function _M.add_to_Blist(redis, ip, fingerprint)
    if not redis then return end
    local interval = config.preprocess[5].interval
    local expire_time = ngx.time() + interval  -- 当前时间 + interval

    -- Redis 保证 EVAL 命令执行的脚本的原子性
    local script = [[
        local blacklist_key = KEYS[1]
        local fingerprint = ARGV[1]
        local expire_time = ARGV[2]

        -- 检查是否已存在
        local exists = redis.call("ZSCORE", blacklist_key, fingerprint)
        if not exists then
            -- 如果不存在，则添加到黑名单
            redis.call("ZADD", blacklist_key, expire_time, fingerprint)
            return 1  -- 成功添加
        else
            return 0  -- 已存在，跳过添加
        end
    ]]

    local result = redis:eval(script, 1, "usr_Blist", fingerprint, expire_time)

    if result == 1 then
        ngx.log(ngx.INFO, "A new user is added into user BlackList.IP: ", ip, " and fingerprint: ", fingerprint, " and interval: ", interval)
    end

end

-- 检查是否在白名单
function _M.is_in_Wlist(redis, fingerprint)
    -- 检查该规则是否启用，若未启用则 return，退出该函数
    if not config.preprocess[3].enable then
        return
    end
    if not redis then return end

    local now = ngx.time()

    -- 检查白名单
    local wscore = redis:zscore("usr_Wlist", fingerprint)
    if wscore ~= ngx.null and tonumber(wscore) > now then
        ngx.log(ngx.INFO, "User is in whitelist")
        return true
    end

    return false
end


-- 检查是否在黑名单
function _M.is_in_Blist(redis, fingerprint)
    -- 检查该规则是否启用，若未启用则 return，退出该函数
    if not config.preprocess[5].enable then
        return
    end
    if not redis then return end

    local now = ngx.time()

    -- 检查黑名单
    local bscore = redis:zscore("usr_Blist", fingerprint)
    if bscore ~= ngx.null and tonumber(bscore) > now then
        ngx.log(ngx.INFO, "User is in blacklist")
        return true
    end

    return false
end


-- 清理过期数据
-- 白名单
local function cleanup_W_expired(redis)
    if not redis then return end

    local now = ngx.time()
    local res, err = redis:zremrangebyscore("usr_Wlist", "-inf", now)
    if err then ngx.log(ngx.ERR, "Failed to clean usr_Wlist: ", err) end

end
-- 黑名单
local function cleanup_B_expired(redis)
    if not redis then return end

    local now = ngx.time()
    local res, err = redis:zremrangebyscore("usr_Blist", "-inf", now)
    if err then ngx.log(ngx.ERR, "Failed to clean usr_Blist: ", err) end

end


-- 定期执行清理任务
function _M.start_cleanup_timer()
    ngx.timer.at(1, function()
        -- 1 表示定时器将在创建后 1 秒触发
        -- 只在 worker 0 上执行，防止多个 worker 进程重复执行
        if ngx.worker.id() ~= 0 then
            return
        end
        -- 查看是否读取到配置文件
        local config = config_module.get_rules("preprocess")
        if not config or not config.preprocess then
            ngx.log(ngx.ERR, "start_cleanup_timer(): Config is not properly loaded, retrying in 1 seconds...")
            _M.start_cleanup_timer()  -- 继续尝试启动定时器
            return
        end

        -- 定期任务，不使用请求中的 redis 连接，因此使用二次开发库，使用时只负责申请
        local redis = redis_iresty:new()

        -- WhiteList
        local interval = config.preprocess[3] and config.preprocess[3].interval or 1800  -- 默认 30 min
        ngx.timer.every(interval, function() cleanup_W_expired(redis) end)

        -- BlackList
        interval = config.preprocess[5] and config.preprocess[5].interval or 600  -- 默认 10 min
        ngx.timer.every(interval, function() cleanup_B_expired(redis) end)

        ngx.log(ngx.INFO, "start_cleanup_timer(): Cleanup timers started successfully.")
    end)
end

return _M
