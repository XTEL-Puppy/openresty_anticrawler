local json = require "cjson"
local config_module = require("config_loader")
local _M = {}

function _M.test()
    local config = config_module.get_config()
    ngx.say("concurrency=", config.preprocess[1].concurrency)
end

return _M

