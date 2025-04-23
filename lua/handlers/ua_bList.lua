local config_module = require "config_loader"

local _M = {}

local config = config_module.get_rules("preprocess")


-- preprocess id=2，ua黑名单
local function is_ua_blacklisted()

    -- ngx.log(ngx.INFO, "ua blacklist is enable, process is loaded, now ua is", ngx.ctx.ua)
    -- 遍历黑名单规则进行匹配
    for _, pattern in ipairs(config.preprocess[2].match.value) do
        local find, err = ngx.re.find(ngx.ctx.ua, pattern, "ijo")  -- 'i'不区分大小写模式 -- 'jo'启用PCRE JIT编译为获得更好性能
        if find then
            return true  -- 匹配成功，拒绝请求
        end
    end

    return false
end

-- priority=2，若匹配UA黑名单则返回403
function _M.process()

    -- 检查该规则是否启用，若未启用则 return，退出该函数
    if not config.preprocess[2].enable then
        return
    end

    if is_ua_blacklisted() then
        ngx.log(ngx.WARN, ngx.ctx.ip, " Be blocked by User-Agent: ", ngx.ctx.ua)
        ngx.exit(403)
    end

end

return _M