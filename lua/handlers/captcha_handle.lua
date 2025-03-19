local redis_iresty = require "tools.redis_iresty"
local captcha_generate = require "handlers.captcha_generate"

local redis = redis_iresty:new()

local function refresh(fingerprint)
    if ngx.var.arg_refresh ~= "1" then
        return
    end

    local new_code, new_img = captcha_generate.generate()

    redis:del("cap:" .. fingerprint)
    redis:setex("cap:" .. fingerprint, 300, new_code)  -- 5分钟过期

    ngx.header.content_type = "image/svg+xml"
    ngx.print(new_img)
    
    return ngx.exit(ngx.HTTP_OK)  -- 终止请求
end



local fingerprint = ngx.var.arg_fp  -- 获取 URL 参数 fp 为用户指纹

if not fingerprint then
    ngx.exit(ngx.HTTP_BAD_REQUEST)  -- 如果没有 fp 则返回 400
end

refresh(fingerprint)

local captcha_code, captcha_img = captcha_generate.generate()

-- 绑定到 Redis
local redis_key = "cap:" .. fingerprint
redis:setex(redis_key, 300, captcha_code)  -- 5 分钟过期

-- 保存需要重定向的 url
local redirect_url = ngx.var.arg_redirect or "/"
-- ngx.log(ngx.INFO, "The redirect url is: ", ngx.unescape_uri(redirect_url))


-- 返回 HTML 页面，嵌入验证码图片
ngx.header.content_type = "text/html; charset=UTF-8"
ngx.say([[
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="UTF-8">
        <title>安全验证</title>
        <style>
            .captcha-box { 
                max-width: 300px; 
                margin: 50px auto; 
                padding: 20px;
                border: 1px solid #ddd;
                border-radius: 8px;
                box-shadow: 0 2px 8px rgba(0,0,0,0.1);
                text-align: center;
            }
            .error { color: #dc3545; }
            input { 
                width: 100%;
                padding: 8px;
                margin: 10px -10px;
                border: 1px solid #ccc;
                border-radius: 4px;
            }
            button { 
                background: #007bff;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
            }
        </style>
        <script>
            function refreshCaptcha() {
                fetch("/captcha?fp=]] .. fingerprint .. [[&refresh=1")
                    .then(response => response.text())
                    .then(svg => {
                        var captchaContainer = document.getElementById("captcha-container");
                        captchaContainer.innerHTML = "";  // 先清空
                        captchaContainer.innerHTML = svg.trim(); // 避免插入额外的空格或换行导致多个验证码
                    })
                    .catch(error => console.error("Error refreshing CAPTCHA:", error));
            }
        </script>
    </head>
    <body>
        <div class="captcha-box">
            <form method="POST" action="/verify_captcha">
                <input type="hidden" name="redirect" value="]] .. redirect_url .. [[">
                <h3>请输入验证码</h3>
                <p>点击验证码图片进行刷新</p>
                
                <!-- SVG 直接作为 HTML 嵌入 -->
                <div id="captcha-container" onclick="refreshCaptcha()">
                    ]] .. captcha_img .. [[
                </div>

                <input type="hidden" name="fp" value="]] .. fingerprint .. [[">
                <input type="text" name="code" placeholder="输入验证码">
                <button type="submit">提交</button>
            </form>
        </div>
    </body>
    </html>
]])

