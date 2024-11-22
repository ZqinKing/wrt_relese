#!/bin/bash

# 获取最新的握手时间（分钟）
time=$(wg show | grep -oE "latest handshake:.*" | awk '/minutes/ {print $3}' | sort -r | head -n 1)

# 检查时间是否存在且大于2分钟
if [ -n "$time" ] && [ "$time" -gt 2 ]; then
    # 获取接口名称
    ifname=$(wg show | awk '/interface/ {print $2}')
    # 重新启动接口
    /sbin/ifup "$ifname"
fi
