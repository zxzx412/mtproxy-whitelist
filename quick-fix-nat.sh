#!/bin/bash

echo "🔧 MTProxy NAT模式快速修复脚本"
echo "=================================="

# 停止现有服务
echo "1. 停止现有服务..."
docker-compose down 2>/dev/null || true

# 强制更新 .env 文件
echo "2. 更新 .env 配置文件..."
cat > .env << 'EOF'
# MTProxy 白名单系统环境配置
# NAT模式快速修复版本

# 基础配置
MTPROXY_DOMAIN=azure.microsoft.com
MTPROXY_TAG=
SECRET_KEY=ee004d64da8e145b8daa35a2012e220e
JWT_EXPIRATION_HOURS=24
ADMIN_PASSWORD=admin123

# 端口配置 - NAT模式
MTPROXY_PORT=14202
WEB_PORT=8989
NGINX_STREAM_PORT=14202
NGINX_WEB_PORT=8989
INTERNAL_MTPROXY_PORT=444
API_PORT=8080

# 网络模式 - NAT模式使用host网络
NETWORK_MODE=host
NAT_MODE=true

# IP获取配置
ENABLE_PROXY_PROTOCOL=true
DEBUG_IP_DETECTION=true
LOG_LEVEL=INFO
ENABLE_IP_MONITORING=true
EOF

echo "✅ .env 文件已更新"

# 显示配置
echo "3. 当前配置："
echo "   NAT_MODE=true"
echo "   NETWORK_MODE=host"
echo "   MTPROXY_PORT=14202"
echo "   WEB_PORT=8989"

# 重新构建和启动
echo "4. 重新构建和启动服务..."
docker-compose build --no-cache
docker-compose up -d

# 等待启动
echo "5. 等待服务启动..."
sleep 15

# 检查状态
echo "6. 检查服务状态..."
echo "容器状态："
docker-compose ps

echo ""
echo "端口监听状态："
netstat -tlnp | grep -E ":(14202|8989)" || echo "⚠️  端口未监听"

echo ""
echo "容器内端口状态："
docker-compose exec mtproxy-whitelist netstat -tlnp 2>/dev/null | grep -E ":(14202|8989|443|8888|444)" || echo "⚠️  容器内端口检查失败"

echo ""
echo "环境变量检查："
echo "NAT_MODE: $(docker-compose exec mtproxy-whitelist printenv NAT_MODE 2>/dev/null)"
echo "MTPROXY_PORT: $(docker-compose exec mtproxy-whitelist printenv MTPROXY_PORT 2>/dev/null)"
echo "WEB_PORT: $(docker-compose exec mtproxy-whitelist printenv WEB_PORT 2>/dev/null)"

echo ""
echo "=================================="
echo "🎯 快速修复完成！"
echo ""
echo "如果端口仍然无法访问，请检查："
echo "1. 防火墙设置：ufw allow 14202 && ufw allow 8989"
echo "2. 云服务器安全组：开放 14202 和 8989 端口"
echo "3. 运行完整诊断：./test-ip-detection.sh"
echo "=================================="