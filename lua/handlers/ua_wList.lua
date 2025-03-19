local config_module = require "config_loader"
local resolver = require "resty.dns.resolver"

local _M = {}

local config = config_module.get_rules("preprocess")
local dns_resolver = nil

-- preprocess id=4，ua白名单

function _M.is_ua_whitelisted()

    -- 检查该规则是否启用，若未启用则返回false，退出该函数
    if not config.preprocess[4].enable then
        return
    end

    -- 获取规则
    local ua_rules = config.preprocess[4].match.value
    local dns_rules = config.preprocess[4].match.dns

    -- 逐个匹配 User-Agent
    for _, bot_name in ipairs(ua_rules) do
        local pattern = bot_name  -- 直接使用规则中的字符串进行匹配
        local dns_whitelist = dns_rules[bot_name] -- 对应的 DNS 白名单

        if ngx.re.find(ngx.ctx.ua, pattern, "jo") then
            -- 创建 DNS 解析器
            local r, err = resolver:new{ nameservers = config.preprocess[4].dns_servers or { "8.8.8.8", "8.8.4.4" }, timeout = 1000 }
            if not r then
                ngx.log(ngx.WARN, "Failed to create resolver: ", err)
                -- 创建DNS解析器失败，跳出该函数，交给后续函数处理
                return 
            end

            -- 执行反向 DNS 查询
            local ptr_records, err = r:reverse_query(ngx.ctx.ip)
            if not ptr_records then
                ngx.log(ngx.WARN, "Failed to resolve PTR record for ", ngx.ctx.ip, ": ", err)
                -- 查询失败，跳出该函数，交给后续函数处理
                return false
            end

            -- 遍历 PTR 记录，检查是否属于搜索引擎域名白名单
            for _, ptr in ipairs(ptr_records) do
                for _, domain in ipairs(dns_whitelist) do
                    -- 转义域名中的点号，处理结尾点号
                    local white_domain = domain:gsub("%.", "\\.") .. "%.?"  
                    if ngx.re.find(ptr, white_domain .. "$", "jo") then
                        ngx.log(ngx.INFO, "PTR record matched: ", ptr)
                        return true
                    end
                end
            end

            -- DNS 解析成功，但没有匹配白名单域名
            ngx.log(ngx.ERR, "Domain name matching failed, no match for PTR records")
            return ngx.exit(403)
        end
    end

    -- 没有匹配到 User-Agent，交给后续函数处理
    return
end

return _M

