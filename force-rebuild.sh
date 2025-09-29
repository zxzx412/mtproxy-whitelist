#!/bin/bash

echo "🔧 强制重建 MTProxy 容器 - 彻底修复环境变量问题"
echo "=================================================="

# 1. 完全停止和清理
echo "1. 完全停止和清理现有容器..."
docker-compose down -v --remove-orphans
docker system prune -f
docker volume prune -f

# 2. 删除旧镜像
echo "2. 删除旧镜像..."
docker rmi mtproxy-whitelist-mtproxy-whitelist 2>/dev/null || true
docker rmi $(docker images -q --filter "dangling=true") 2>/dev/null || true

# 3. 验证 .env 文件
echo "3. 验证 .env 文件内容..."
if [ ! -f ".env" ]; then
    echo "❌ .env 文件不存在，创建新的..."
    cat > .env << 'EOF'
# MTProxy 白名单系统环境配置
MTPROXY_DOMAIN=azure.microsoft.com
MTPROXY_TAG=
SECRET_KEY=ee004d64da8e145b8daa35a2012e220e
JWT_EXPIRATION_HOURS=24
ADMIN_PASSWORD=admin123
MTPROXY_PORT=14202
WEB_PORT=8989
NGINX_STREAM_PORT=14202
NGINX_WEB_PORT=8989
INTERNAL_MTPROXY_PORT=444
API_PORT=8080
NETWORK_MODE=host
NAT_MODE=true
DEBUG_IP_DETECTION=true
LOG_LEVEL=INFO
ENABLE_IP_MONITORING=true
ENABLE_PROXY_PROTOCOL=true
EOF
fi

echo "✅ .env 文件内容："
cat .env

# 4. 验证 docker-compose.yml
echo ""
echo "4. 验证 docker-compose.yml 环境变量部分..."
grep -A 15 "environment:" docker-compose.yml

# 5. 强制重建（不使用缓存）
echo ""
echo "5. 强制重建容器（不使用缓存）..."
docker-compose build --no-cache --pull

# 6. 启动服务
echo "6. 启动服务..."
docker-compose up -d

# 7. 等待启动
echo "7. 等待服务启动..."
sleep 20

# 8. 详细检查
echo "8. 详细状态检查..."
echo ""
echo "容器状态："
docker-compose ps

echo ""
echo "容器内环境变量检查："
echo "NAT_MODE: $(docker-compose exec -T mtproxy-whitelist printenv NAT_MODE 2>/dev/null || echo '未设置')"
echo "MTPROXY_PORT: $(docker-compose exec -T mtproxy-whitelist printenv MTPROXY_PORT 2>/dev/null || echo '未设置')"
echo "WEB_PORT: $(docker-compose exec -T mtproxy-whitelist printenv WEB_PORT 2>/dev/null || echo '未设置')"
echo "NGINX_STREAM_PORT: $(docker-compose exec -T mtproxy-whitelist printenv NGINX_STREAM_PORT 2>/dev/null || echo '未设置')"
echo "NGINX_WEB_PORT: $(docker-compose exec -T mtproxy-whitelist printenv NGINX_WEB_PORT 2>/dev/null || echo '未设置')"
echo "NETWORK_MODE: $(docker-compose exec -T mtproxy-whitelist printenv NETWORK_MODE 2>/dev/null || echo '未设置')"

echo ""
echo "容器内端口监听状态："
docker-compose exec -T mtproxy-whitelist netstat -tlnp 2>/dev/null | grep -E ":(14202|8989|443|8888|444)" || echo "⚠️  端口检查失败"

echo ""
echo "主机端口监听状态："
netstat -tlnp | grep -E ":(14202|8989)" || echo "⚠️  主机端口未监听"

echo ""
echo "容器日志（最后20行）："
docker-compose logs --tail=20

echo ""
echo "=================================================="
echo "🎯 强制重建完成！"
echo ""
echo "如果环境变量仍然为空，说明 docker-compose 版本或配置有问题"
echo "请检查："
echo "1. docker-compose 版本：docker-compose --version"
echo "2. .env 文件权限：ls -la .env"
echo "3. 当前目录：pwd"
echo "=================================================="