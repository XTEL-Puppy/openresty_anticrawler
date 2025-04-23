local redis_iresty = require "tools.redis_iresty"
local usr_bwlist = require "handlers.usr_bwList"

local redis = redis_iresty:new()



-- 读取请求体
ngx.req.read_body()

-- 解析请求参数
local args = ngx.req.get_post_args()

-- 获取参数值
local user_input = args.code
local fingerprint = args.fp
local redirect_url = ngx.unescape_uri(args.redirect) or "/"

if not user_input or not fingerprint then
    ngx.exit(ngx.HTTP_BAD_REQUEST)
end

-- 从 Redis 获取正确答案
local correct_code = redis:get("cap:" .. fingerprint)
if not correct_code then
    ngx.header["Content-Type"] = "text/html; charset=UTF-8"
    ngx.say([[ 
        <script>
            alert("验证码已过期或无效，请重新获取");
            window.location.href = "/captcha?fp=]] .. fingerprint .. [[";
        </script>
    ]])
        return
end

-- 验证是否正确
if user_input == correct_code then
    -- 删除 Redis 记录，并加入白名单
    redis:del("cap:" .. fingerprint)
    usr_bwlist.add_to_Wlist(redis, ngx.var.remote_addr, fingerprint)

    -- 确保 URL 只能跳转到站内路径
    if not redirect_url:match("^/") then
        redirect_url = "/"  -- 防止跳转到恶意网站
    end

    ngx.header["Content-Type"] = "text/html; charset=UTF-8"
    ngx.say([[
        <script>
            alert("验证成功，正在跳转...");
            window.location.href = decodeURIComponent("]] .. ngx.escape_uri(redirect_url) .. [[");
        </script>
    ]])
else
    -- 失败则删除旧验证码，刷新新验证码
    redis:del("cap:" .. fingerprint)
    ngx.header["Content-Type"] = "text/html; charset=UTF-8"
    ngx.say([[ 
        <script>
            alert("验证码错误，请重试");
            window.location.href = "/captcha?fp=]] .. fingerprint .. [[";
        </script>
    ]])
end

