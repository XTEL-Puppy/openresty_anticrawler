local redis = require "resty.redis"
local config_module = require "config_loader"
local preprocess = require "strategies.preprocess"
local xxh32 = require "tools.luaxxhash"


-- 保存 redis 连接到请求上下文，供后续阶段使用
local ctx = ngx.ctx

local red = redis:new()
red:set_timeout(1000) -- 1 秒超时
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
    ngx.log(ngx.ERR, "failed to connect: ", err)
    return nil
end

ctx.redis_conn = red -- 绑定到 ngx.ctx


-- 获取用户 IP 地址
local function get_client_ip()
    local headers = ngx.req.get_headers()
    local x_forwarded_for = headers["X-Forwarded-For"]
    
    if x_forwarded_for then
        -- 取第一个 IP
        local client_ip = x_forwarded_for:match("([^,]+)")
        return client_ip
    end

    -- 回退到 X-Real-IP
    return headers["X-Real-IP"] or ngx.var.remote_addr
end

-- 获取 User-Agent
local function get_user_agent()
    return ngx.var.http_user_agent
end

local client_ip = get_client_ip()
local user_agent = get_user_agent()

-- 如果任意一方为空，则返回 403
if not client_ip or client_ip == "" or not user_agent or user_agent == "" then
    return ngx.exit(403)
end

-- 计算哈希值
local function generate_fingerprint(ip, ua)
    local raw_str = ip .. "|" .. ua  -- 用 | 分隔避免歧义
    return xxh32(raw_str)
end

-- 保存用户 IP 与 UA
ngx.ctx.ip = client_ip
ngx.ctx.ua = user_agent
-- 计算并保存指纹
local fingerprint = generate_fingerprint(client_ip, user_agent)
ngx.ctx.fingerprint = fingerprint

-- 如果此时存在cookie 则将cookie的signature部分作为fingerprint传递到 preprocess 模块
local cookie_str = ngx.var.cookie_MyCookie


if cookie_str then
    local parts = {}
    for part in cookie_str:gmatch("[^:]+") do
        table.insert(parts, part)
    end
    fingerprint = parts[2]  -- 取第二部分
else
    fingerprint = ngx.ctx.fingerprint  -- 提取失败时 重新填入 IP+UA 的 XXH32 值
end

-- ngx.log(ngx.INFO, "THE ctx.fingerprint is: ", ngx.ctx.fingerprint, " THE fingerprint is: ", fingerprint)

-- 读取规则版本
local version = config_module.get_rules("preprocess").meta.rule_version
local rule_module_name = "strategies.rule_" .. version
local rule = require(rule_module_name)

-- 执行反爬规则链
if preprocess.rules_process(red, fingerprint) then
    --  return 终止当前 Lua 脚本的执行
    return
end
rule.rules_process(red, fingerprint)



