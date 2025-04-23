local ctx = ngx.ctx
local redis_conn = ctx.redis_conn

-- ngx.log(ngx.INFO, "conn log is running...")

-- 释放 Redis 连接
if redis_conn then
    -- pcall 避免 set_keepalive() 失败导致 Lua 运行时异常
    local ok, err = pcall(function()
        return redis_conn:set_keepalive(60000, 1000)
    end)
    if not ok then
        ngx.log(ngx.ERR, "Failed to release Redis connection: ", err)
    end
    ctx.redis_conn = nil  -- 清理 ngx.ctx
end
