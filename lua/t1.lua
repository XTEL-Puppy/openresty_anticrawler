local redis_iresty = require "resty.redis_iresty"
local redis = redis_iresty:new()
local json = require "cjson"
local limit_conn = require "resty.limit.conn"
local config_module = require "config_loader"

local config = config_module.get_config()

-- priority=1，并发控制
local function IP_concurrency_control()
    -- 检查该规则是否启用，若未启用则返回false，退出该函数
    if not config.preprocess[1].enable then
        ngx.log(ngx.INFO, "rule no loaded")
	return false
    else
        ngx.log(ngx.INFO, "rule is loaded")
    end

end

-- 显式调用
IP_concurrency_control()
