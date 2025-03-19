local ffi = require("ffi")

ffi.cdef[[
    struct stat {
        dev_t     st_dev;      // 设备 ID
        ino_t     st_ino;      // inode 号
        mode_t    st_mode;     // 文件类型和权限
        nlink_t   st_nlink;    // 硬链接数量
        uid_t     st_uid;      // 用户 ID
        gid_t     st_gid;      // 组 ID
        dev_t     st_rdev;     // 设备类型（特殊文件）
        off_t     st_size;     // 文件大小（字节）
        blksize_t st_blksize;  // 文件系统块大小
        blkcnt_t  st_blocks;   // 分配的 512B 块数
        struct timespec st_atim;  // 最后访问时间
        struct timespec st_mtim;  // 最后修改时间
        struct timespec st_ctim;  // 最后状态变更时间
    };
    int stat(const char *path, struct stat *buf);
]]

local _M = {}

function _M.get_file_mtime(path)
    local stat = ffi.new("struct stat")
    if ffi.C.stat(path, stat) ~= 0 then
        return nil, "File not found"
    end
    return tonumber(stat.st_mtim.tv_sec)  -- 从 timespec 中提取秒
end

return _M

