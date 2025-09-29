#!/bin/bash

# NAT环境IP获取修复脚本
# 解决NAT模式下无法获取真实客户端IP的问题

echo "=== NAT环境IP获取问题诊断与修复 ==="

# 1. 检查当前网络环境
echo "1. 检查网络环境..."
echo "容器网络模式: $(docker inspect mtproxy-whitelist --format='{{.HostConfig.NetworkMode}}' 2>/dev/null || echo '未运行')"
echo "主机IP: $(hostname -I | awk '{print $1}')"
echo "公网IP: $(curl -s ifconfig.me || echo '无法获取')"

# 2. 分析日志中的IP模式
echo -e "\n2. 分析访问日志中的IP模式..."
if [ -f "/var/log/nginx/stream_access.log" ]; then
    echo "最近的访问IP:"
    tail -10 /var/log/nginx/stream_access.log | awk '{print $1}' | sort | uniq -c
else
    echo "日志文件不存在，检查容器日志..."
    docker logs mtproxy-whitelist 2>/dev/null | grep -E "172\.|192\.|10\." | tail -5
fi

# 3. 提供解决方案
echo -e "\n3. NAT环境IP获取解决方案:"
echo "问题: 在NAT环境下，nginx只能看到NAT网关的内网IP (如172.16.5.6)"
echo "解决方案选择:"

echo -e "\n方案A: 修改白名单策略 (推荐)"
echo "- 将NAT网关IP添加到白名单"
echo "- 适用于信任的内网环境"

echo -e "\n方案B: 使用HTTP代理模式"
echo "- 改用HTTP CONNECT代理"
echo "- 可以通过X-Forwarded-For获取真实IP"

echo -e "\n方案C: 配置上游PROXY Protocol"
echo "- 需要在NAT网关配置PROXY Protocol"
echo "- 技术要求较高"

# 4. 自动修复选项
echo -e "\n4. 选择修复方案:"
read -p "选择方案 (A/B/C) 或按Enter跳过: " choice

case $choice in
    [Aa])
        echo "执行方案A: 添加NAT网关IP到白名单..."
        # 获取当前访问的内网IP
        NAT_IP=$(docker logs mtproxy-whitelist 2>/dev/null | grep -oE "172\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        if [ -n "$NAT_IP" ]; then
            echo "检测到NAT网关IP: $NAT_IP"
            echo "添加到白名单..."
            docker exec mtproxy-whitelist sh -c "echo '$NAT_IP 1;' >> /data/nginx/whitelist_map.conf"
            docker exec mtproxy-whitelist nginx -s reload
            echo "✅ 已添加 $NAT_IP 到白名单并重载nginx"
        else
            echo "❌ 无法自动检测NAT网关IP，请手动添加"
        fi
        ;;
    [Bb])
        echo "执行方案B: 切换到HTTP代理模式..."
        echo "这需要重新配置nginx为HTTP CONNECT代理模式"
        echo "是否继续? (y/N)"
        read -p "> " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            # 备份当前配置
            docker exec mtproxy-whitelist cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
            # 这里可以添加HTTP代理配置的生成逻辑
            echo "⚠️  HTTP代理模式配置较复杂，建议使用方案A"
        fi
        ;;
    [Cc])
        echo "方案C需要在网络层面配置PROXY Protocol"
        echo "请参考文档配置上游代理服务器"
        ;;
    *)
        echo "跳过自动修复"
        ;;
esac

echo -e "\n=== 修复完成 ==="
echo "建议: 在NAT环境下，最简单的解决方案是将信任的NAT网关IP添加到白名单"
echo "如果需要获取真实客户端IP，需要在网络架构层面进行配置"