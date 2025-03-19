local json = require "cjson"
local limit_req = require "resty.limit.req"
local config_module = require "config_loader"

local _M = {}

local config = config_module.get_rules("preprocess")



-- preprocess id=1，限制请求速率
function _M.process()

    -- 检查该规则是否启用，若未启用则 return，退出该函数
    if not config.preprocess[1].enable then
        return
    end

    -- 从 JSON 配置中获取指定的请求速率（每秒数量）阈值
    local rate = config.preprocess[1].rate

    -- burst是每秒允许延迟的超额请求数
    local burst = math.floor(rate / 2)

    -- 初始化限流器
    local lim, err = limit_req.new("my_limit_req_store", rate, burst)
    if not lim then
        ngx.log(ngx.ERR, "Failed to instantiate a resty.limit.req object: ", err)
        return ngx.exit(500)

    end

    -- 以IP作为限制键，检查并发连接数
    local key = ngx.var.binary_remote_addr
    local delay, err = lim:incoming(key, true)

    if not delay then
        if err == "rejected" then
            return ngx.exit(503)
        end
        ngx.log(ngx.ERR, "Failed to limit req: ", err)
        return ngx.exit(500)
    end

    if delay >= 0.001 then
        -- 保存超出 rate 限制的值
        local excess = err
        ngx.log(ngx.WARN, "The number of current requests exceeds the allowed rate: ", excess)

        ngx.sleep(delay)
    end
end

return _M
