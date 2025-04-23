local config_module = require "config_loader"
local ip_rete_limit = require "handlers.ip_rete_limit"
local ua_blist = require "handlers.ua_bList"
local ua_wlist = require "handlers.ua_wList"
local usr_bwlist = require "handlers.usr_bwList"

local _M = {}

local config = config_module.get_rules("preprocess")

function _M.rules_process(redis, fingerprint)
    -- 执行 ip 流量控制 若未启用规则退出当前函数
    -- ip_rete_limit.process() 的返回值为 nil
    ip_rete_limit.process()
    -- 判断 UA 是否合法 非法则拒绝请求 返回403 若未启用规则 return 退出当前函数
    -- ua_blist.process() 的返回值为 nil
    ua_blist.process()

    -- 用户位于白名单中则返回 true
    if usr_bwlist.is_in_Wlist(redis, fingerprint) then
        return true   
    end

    -- 判断 UA 是否为浏览器爬虫 是则返回 true
    if ua_wlist.is_ua_whitelisted() then
        return true
    end

    -- 用户位于黑名单中则返回 true
    if usr_bwlist.is_in_Blist(redis, fingerprint) then
        if config.preprocess[5].action == "refuse" then
            return ngx.exit(403)
        elseif config.preprocess[5].action == "captcha" then
            local original_url = ngx.var.request_uri
            return ngx.redirect("/captcha?fp=" .. fingerprint .. "&redirect=" .. ngx.escape_uri(original_url), ngx.HTTP_MOVED_TEMPORARILY)
        else
            return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
    end

end

return _M