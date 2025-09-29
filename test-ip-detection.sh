#!/bin/bash

echo "🔍 MTProxy 白名单系统 IP 获取测试"
echo "=========================================="

# 检查服务状态
echo "1. 检查服务运行状态："
docker-compose ps

echo ""
echo "2. 检查端口监听状态："
echo "外部端口检查："
netstat -tlnp | grep -E ":(14202|8989) " || echo "⚠️  外部端口未监听"

echo ""
echo "容器内端口检查："
docker-compose exec mtproxy-whitelist netstat -tlnp | grep -E ":(14202|8989|443|8888|444) "

echo ""
echo "3. 测试 Web 管理界面连通性："
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8989/ --connect-timeout 5)
echo "HTTP 响应码: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Web 管理界面正常"
else
    echo "❌ Web 管理界面异常"
fi

echo ""
echo "4. 测试 MTProxy 端口连通性："
if timeout 3 bash -c "</dev/tcp/localhost/14202" 2>/dev/null; then
    echo "✅ MTProxy 端口 14202 可连接"
else
    echo "❌ MTProxy 端口 14202 无法连接"
fi

echo ""
echo "5. 检查 nginx 配置："
docker-compose exec mtproxy-whitelist nginx -t

echo ""
echo "6. 查看最近的连接日志："
echo "Stream 访问日志："
docker-compose exec mtproxy-whitelist tail -5 /var/log/nginx/stream_access.log 2>/dev/null || echo "暂无日志"

echo ""
echo "Web 访问日志："
docker-compose exec mtproxy-whitelist tail -5 /var/log/nginx/access.log 2>/dev/null || echo "暂无日志"

echo ""
echo "7. 运行容器内 IP 诊断："
docker-compose exec mtproxy-whitelist /usr/local/bin/diagnose-ip.sh 2>/dev/null || echo "诊断脚本不可用"

echo ""
echo "8. 环境变量检查："
echo "NAT_MODE: $(docker-compose exec mtproxy-whitelist printenv NAT_MODE)"
echo "MTPROXY_PORT: $(docker-compose exec mtproxy-whitelist printenv MTPROXY_PORT)"
echo "WEB_PORT: $(docker-compose exec mtproxy-whitelist printenv WEB_PORT)"

echo ""
echo "=========================================="
echo "🎯 IP 获取测试完成"
echo ""
echo "如果发现问题，请运行以下命令重新部署："
echo "  docker-compose down"
echo "  sudo ./deploy.sh"
echo "=========================================="