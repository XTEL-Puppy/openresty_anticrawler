local config_module = require "config_loader"
local request_count = require "handlers.request_count"

local _M = {}

function _M.rules_process(redis, fingerprint)

    -- 依赖于 ngx.ctx.ip
    request_count.process(redis, fingerprint, "ipua")  -- 计数用户请求，大于阈值则加入黑名单，并返回403或验证码

end



return _M
