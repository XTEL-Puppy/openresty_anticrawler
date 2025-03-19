local config_module = require "config_loader"

local _M = {}

math.randomseed(ngx.now()*1000%1e+8) -- 使用当前时间生成随机种子，确保每次运行的随机性
local rnd = math.random -- 将 math.random 函数赋值给 rnd 变量，方便调用

-- 获取json文件转换而来的lua表
local config = config_module.get_rules("preprocess").meta

-- 定义验证码字符集
local dict = "ABCDEFGHJKLMNPQRSTUVWYZabdehkmnrstuvwz23456789"

-- 可用的 TTF 字体
local fonts = config.captcha.valid_fonts

-- 生成随机验证码字符串
local function generate_random_text(length)
    local result = {}
    for i = 1, length do
        local rand_index = rnd(1, #dict)
        table.insert(result, dict:sub(rand_index, rand_index))
    end
    return table.concat(result)
end

-- 随机颜色
local function random_color()
    return rnd(0, 200), rnd(0, 200), rnd(0, 200)  -- 限制到 0~200 避免过亮
end

-- 生成 SVG 验证码
function _M.generate()
    local width, height = 150, 70  -- 图像尺寸
    local text = generate_random_text(4)  -- 生成 4 个字符的验证码
    local svg = {}

    -- SVG 头部
    table.insert(svg, string.format(
        [[<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">]],
        width, height
    ))

    -- 背景
    local bg_r, bg_g, bg_b = random_color()
    table.insert(svg, string.format([[<rect width="100%%" height="100%%" fill="rgb(%d,%d,%d)"/>]], bg_r, bg_g, bg_b))

    -- 绘制验证码字符
    for i = 1, #text do
        local char = text:sub(i, i)
        local font_size = rnd(25, 35)  -- 随机字体大小
        local angle = rnd(-30, 30)  -- 随机角度
        local x = 20 + (i - 1) * 30  -- 计算 x 轴位置
        local y = rnd(40, 60)  -- 计算 y 轴位置
        local r, g, b = random_color()
        local font = fonts[rnd(1, #fonts)]  -- 随机选择字体

        table.insert(svg, string.format(
            [[<text x="%d" y="%d" font-size="%d" fill="rgb(%d,%d,%d)" font-family="%s" transform="rotate(%d %d %d)">%s</text>]],
            x, y, font_size, r, g, b, font, angle, x, y, char
        ))
    end

    -- 干扰线
    for i = 1, 5 do
        local x1, y1 = rnd(0, width), rnd(0, height)
        local x2, y2 = rnd(0, width), rnd(0, height)
        local r, g, b = random_color()
        table.insert(svg, string.format(
            [[<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="rgb(%d,%d,%d)" stroke-width="2"/>]],
            x1, y1, x2, y2, r, g, b
        ))
    end

    -- 关闭 SVG
    table.insert(svg, "</svg>")

    -- 返回验证码字符串 + SVG 图片
    return text, table.concat(svg)
end

return _M

