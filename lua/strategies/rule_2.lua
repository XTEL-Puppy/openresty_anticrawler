local config_module = require "config_loader"
local js_challenge = require "handlers.js_challenge"
local request_count = require "handlers.request_count"

local _M = {}

local config = config_module.get_rules("version")

function _M.rules_process(redis, fingerprint)
    -- js 挑战规则不启用即规则二基本无效 只启用 preprocess
    if not config.rules[1].enable then return end
    local valid, signature = js_challenge.is_valid_cookie(redis)
    if valid then
        -- 有 cookie 则以 signature 为特征计数用户请求，大于阈值则加入黑名单，并返回403或验证码
        request_count.process(redis, signature, "cookie")
        return
    end

    local valid, user_id, expires = js_challenge.is_valid_token(redis)
    if valid then
        -- token合法 生成cookie
        js_challenge.set_cookie(user_id,expires, redis)
        return
    end

    -- 无 token 与 cookie 触发 js 挑战与 IP+UA 计数
    js_challenge.process(redis, fingerprint)

end



return _M