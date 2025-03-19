#!/bin/bash
set -e

echo "The anti-crawler system based on OpenResty is currently being installed..."

# 获取 OpenResty 安装路径
OPENRESTY_PREFIX=$(openresty -V 2>&1 | grep 'configure arguments' | sed -n 's/.*--prefix=\([^ ]*\).*/\1/p')

# 检查是否获取到路径
if [[ -z "$OPENRESTY_PREFIX" ]]; then
    echo "未能自动检测 OpenResty 的安装路径，请手动输入路径（例如 /usr/local/openresty）："
    read -r OPENRESTY_PREFIX
fi

# 复制 Lua 和 JSON 规则文件
sudo cp -r lua "$OPENRESTY_PREFIX/nginx/"
sudo cp -r json "$OPENRESTY_PREFIX/nginx/"

# 备份原来的 nginx.conf 并覆盖
sudo cp "$OPENRESTY_PREFIX/nginx/conf/nginx.conf" "$OPENRESTY_PREFIX/nginx/conf/nginx.conf.bak"
sudo cp nginx.conf "$OPENRESTY_PREFIX/nginx/conf/nginx.conf"

# 重启 OpenResty
sudo systemctl restart openresty

echo "The anti-crawler system has been installed successfully!"
