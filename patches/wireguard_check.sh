#!/bin/bash

# 获取接口名称
interface_name=$(wg show | awk '/interface/ {print $2}')

# 如果接口名称为空，则退出
if [[ -z "$interface_name" ]]; then
    exit 0
fi

# 获取最新的握手时间（分钟）
latest_handshake_time=$(wg show | grep -oE "latest handshake:.*" | awk '/minutes/ {print $3}' | sort -r | head -n 1)

# 检查时间是否存在且大于2分钟
if [[ -n "$latest_handshake_time" && "$latest_handshake_time" -gt 2 ]]; then
    # 重新启动接口
    /sbin/ifup "$interface_name"
    exit 0
fi

# 获取端点和活动握手的数量
peer_count=$(wg show | grep -cE "endpoint")
alive_count=$(wg show | grep -cE "latest handshake")

# 检查是否有未活动的端点
if [[ $peer_count -gt $alive_count ]]; then
    # 重新启动接口
    /sbin/ifup "$interface_name"
fi
