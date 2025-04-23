local config_module = require "config_loader"
local usr_bwlist = require "handlers.usr_bwList"
local xxh32 = require "tools.luaxxhash"
local redis_iresty = require "tools.redis_iresty"
local request_count = require "handlers.request_count"
local bit = require "bit"
local cjson = require "cjson"

local config = config_module.get_rules("version").rules[1]

local _M = {}

-- 以 sep 为标志分割字符串
local function split(inputstr, sep)
    if sep == nil then
      sep = "%s"
    end

    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
      table.insert(t, str)
    end

    return t
end

-- 生成 length 个字符组成的字符串
local function rand_string(length)
    local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    for i = 1, length do
        local rand_index = math.random(1, #charset)
        table.insert(result, charset:sub(rand_index, rand_index))
    end
    return table.concat(result)
end

  

-- 验证 cookie 是否有效
function _M.is_valid_cookie(redis)
    
    local cookie = ngx.var.cookie_MyCookie

    ngx.log(ngx.INFO, "NOW is checking valid cookie... cookie is: ", cookie)

    if cookie then
        local parts = split(cookie, ":")

        if #parts == 3 then
            local user_id, signature, expires = parts[1], parts[2], parts[3]

            -- ngx.log(ngx.INFO, "The signature is ", signature, " and type is: ", type(signature))

            local new_seed = tonumber(redis:get("new_seed")) or 9790083248
            local old_seed = tonumber(redis:get("old_seed")) or 9790083248

            local string = user_id .. tostring(expires)

            local expected_1 = tostring(xxh32(string, #string, new_seed))
            local expected_2 = tostring(xxh32(string, #string, old_seed))

            -- ngx.log(ngx.INFO, "The expected new is ", expected_1, " and type is: ", type(expected_1))
            -- ngx.log(ngx.INFO, "The expected old is ", expected_2)

            -- ngx.log(ngx.INFO, "The expire time is ", tonumber(expires), " and type is: ", type(expires))
            -- ngx.log(ngx.INFO, "The ngx.time is ", ngx.time(), " and type is: ", type(ngx.time()))

            if (signature == expected_1 or signature == expected_2) and tonumber(expires) > ngx.time() then
                -- 验证通过 返回 true 与 signature 作为用户指纹进行请求计数
                return true, signature
            end
        end
    end

end

-- 验证 token 是否有效
function _M.is_valid_token(redis)
    local token = ngx.var.cookie_AuthToken

    if not token then
        return false
    end

    local parts = split(ngx.decode_base64(token), ":")
    
    if #parts == 2 and #parts[1] == 8 and (tonumber(parts[2]) - ngx.time()) >= 0 then
        -- 验证通过 颁发长期Cookie
        ngx.log(ngx.INFO, "The token is valid!")
        local expires = config.cookie_expire + ngx.time()
        return true, parts[1], expires
    end

end

-- 认证成功，设置访问 Cookie
function _M.set_cookie(user_id, expires, redis)
    local seed = redis:get("new_seed")
    if seed == ngx.null then 
        seed = 9790083248
    end
    
    ngx.log(ngx.INFO, "Setting cookie... The seed is: ", seed)

    local string = user_id .. tostring(expires)

    local num_seed = tonumber(seed)

    local ok, signature = pcall(xxh32, string, #string, num_seed)

    if not ok then
        ngx.log(ngx.ERR, "xxh32() crashed with error: ", signature)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    ngx.log(ngx.INFO, "A new user get cookie: ", user_id .. ":" .. signature .. ":" .. expires)

    ngx.header["Set-Cookie"] = "MyCookie=" .. user_id .. ":" .. signature .. ":" .. expires .. "; Path=/; HttpOnly; Max-Age=" .. config.cookie_expire

    -- 自动触发用户带着 cookie 再次访问
    ngx.say(string.format([[
        <script>
        setTimeout(() => {
            location.reload();
        }, 500);
        </script>
    ]]))
end

-- 无 token 的情况下触发 js 挑战与 IP+UA 计数
function _M.process(redis, fingerprint)

    request_count.process(redis, fingerprint, "ipua")  -- 计数用户请求，大于阈值则加入黑名单，并返回403或验证码

    local timestamp = ngx.time()    -- 返回秒级精度的时间戳
    local nonce = rand_string(8)    -- 随机8位字符

    ngx.header["Content-Type"] = "text/html"
    ngx.say([[
    <html>
    <head>
        <meta charset="utf-8">
    </head>
    <body>
        <h1>Checking your browser...</h1>
        <script>
            // 反 Selenium 爬虫检测
            if (window.navigator.webdriver) {
                document.body.innerHTML = "<h1>403 Forbidden</h1><p>You don't have permission to access / on this server.</p>";
                throw new Error();  // 停止 JS 执行
            }

            // 检测是否允许 Cookie
            if (!window.navigator.cookieEnabled) {
                document.body.innerHTML = "<h1>Cookies are disabled</h1><p>Please enable cookies to continue.</p>";
                throw new Error("Cookies are disabled, stopping execution.");   // 停止JS执行防止继续设置document.cookie
            }

            // 计算 Token 并写入 Cookie
            function computeToken() {
                let t = ]] .. ngx.time() .. [[ + 5; // Token 5 秒有效
                return btoa("]] .. rand_string(8) .. [[: " + t.toString());
            }

            document.cookie = "AuthToken=" + computeToken() + "; path=/; max-age=10";   // 10秒后过期

            setTimeout(() => {
                location.reload();
            }, 500);   // 0.5s 后刷新页面
        </script>
    </body>
    </html>
    ]])
    
    
end



-- 原子更新脚本（预加载提升性能）
local UPDATE_SCRIPT = [[
    local new_seed = ARGV[1]
    local interval = tonumber(ARGV[2])
    
    -- 获取当前种子并设置旧种子
    local current = redis.call('GET', 'new_seed')
    if current then
        redis.call('SETEX', 'old_seed', interval, current)
    end
    
    -- 设置新种子（强制覆盖）
    redis.call('SETEX', 'new_seed', interval, new_seed)
    return true
]]

function _M.rnd_seed()
    -- 仅worker 0执行
    if ngx.worker.id() ~= 0 then return end

    -- 延迟启动等待配置加载
    ngx.timer.at(1, function()
        -- 只在 worker 0 上执行，防止多个 worker 进程重复执行
        if ngx.worker.id() ~= 0 then
            return
        end

        -- 查看是否读取到配置文件
        local config = config_module.get_rules("version").rules[1]
        if not config then
            ngx.log(ngx.ERR, "rnd_seed(): Config is not properly loaded, retrying in 1 seconds...")
            _M.rnd_seed()  -- 继续尝试启动定时器
            return
        end

        -- 定期任务，不使用请求中的 redis 连接，因此使用二次开发库，使用时只负责申请
        local redis = redis_iresty:new()

        -- 计算过期时间
        local interval = 2 * config.cookie_expire

        -- 启动定时任务
        ngx.timer.every(1.5 * config.cookie_expire, function()
            -- 生成新seed 时间戳+随机数异或
            local seed = bit.bxor(
                ngx.time() % 0xFFFFFFFF,
                math.random(0, 0xFFFF)
            )
            
            -- 原子更新操作
            local ok, err = redis:eval(UPDATE_SCRIPT, 0, seed, interval)
            if not ok then
                ngx.log(ngx.ERR, "update seed failed: ", err)
                return
            end
            
            ngx.log(ngx.INFO, "Seed updated to: ", seed)

            -- -- 获取旧种子并记录日志
            -- local old_seed, err = redis:get("old_seed")
            -- if not old_seed then
            --     ngx.log(ngx.ERR, "failed to get old_seed: ", err)
            -- else
            --     ngx.log(ngx.INFO, "The old_seed is: ", old_seed)
            -- end

            -- -- 获取新种子并记录日志
            -- local new_seed, err = redis:get("new_seed")
            -- if not new_seed then
            --     ngx.log(ngx.ERR, "failed to get new_seed: ", err)
            -- else
            --     ngx.log(ngx.INFO, "The new_seed is: ", new_seed)
            -- end
        end)
    end)
end




return _M