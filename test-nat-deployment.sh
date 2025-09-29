#!/bin/bash

# NAT模式部署测试脚本
# 验证NAT模式首次部署是否正常

echo "🧪 NAT模式部署测试"
echo "==================="

# 检查环境变量
echo "1. 检查环境变量..."
if [[ -f ".env" ]]; then
    source .env
    echo "✅ .env文件存在"
    echo "   NAT_MODE=$NAT_MODE"
    echo "   MTPROXY_PORT=$MTPROXY_PORT"
    echo "   WEB_PORT=$WEB_PORT"
else
    echo "❌ .env文件不存在"
    exit 1
fi

# 检查NAT模式配置
echo ""
echo "2. 检查NAT模式配置..."
if [[ "$NAT_MODE" == "true" ]]; then
    echo "✅ NAT模式已启用"
else
    echo "❌ NAT模式未启用"
    exit 1
fi

# 检查docker-compose配置
echo ""
echo "3. 检查docker-compose配置..."
if [[ -f "docker-compose.nat.yml" ]]; then
    echo "✅ NAT模式配置文件存在"
    
    # 检查配置文件内容
    if grep -q "network_mode: host" docker-compose.nat.yml; then
        echo "✅ host网络模式配置正确"
    else
        echo "❌ host网络模式配置错误"
    fi
    
    if ! grep -q "ports:" docker-compose.nat.yml; then
        echo "✅ 正确移除了端口映射配置"
    else
        echo "⚠️  仍包含端口映射配置（可能导致冲突）"
    fi
else
    echo "❌ NAT模式配置文件不存在"
    exit 1
fi

# 检查端口占用
echo ""
echo "4. 检查端口占用..."
if ss -tuln | grep -q ":$MTPROXY_PORT "; then
    echo "⚠️  端口 $MTPROXY_PORT 已被占用"
    ss -tuln | grep ":$MTPROXY_PORT "
else
    echo "✅ 端口 $MTPROXY_PORT 可用"
fi

if ss -tuln | grep -q ":$WEB_PORT "; then
    echo "⚠️  端口 $WEB_PORT 已被占用"
    ss -tuln | grep ":$WEB_PORT "
else
    echo "✅ 端口 $WEB_PORT 可用"
fi

# 模拟部署测试
echo ""
echo "5. 模拟部署测试..."
echo "测试命令: docker-compose -f docker-compose.nat.yml config"
if docker-compose -f docker-compose.nat.yml config >/dev/null 2>&1; then
    echo "✅ NAT模式配置语法正确"
else
    echo "❌ NAT模式配置语法错误"
    docker-compose -f docker-compose.nat.yml config
    exit 1
fi

# 检查容器状态（如果已运行）
echo ""
echo "6. 检查容器状态..."
if docker ps | grep -q "mtproxy-whitelist"; then
    echo "✅ 容器正在运行"
    
    # 检查网络模式
    NETWORK_MODE=$(docker inspect mtproxy-whitelist --format='{{.HostConfig.NetworkMode}}' 2>/dev/null)
    if [[ "$NETWORK_MODE" == "host" ]]; then
        echo "✅ 容器使用host网络模式"
    else
        echo "❌ 容器网络模式错误: $NETWORK_MODE"
    fi
    
    # 检查端口监听
    if ss -tuln | grep -q ":$MTPROXY_PORT "; then
        echo "✅ MTProxy端口监听正常"
    else
        echo "❌ MTProxy端口未监听"
    fi
    
    if ss -tuln | grep -q ":$WEB_PORT "; then
        echo "✅ Web端口监听正常"
    else
        echo "❌ Web端口未监听"
    fi
else
    echo "ℹ️  容器未运行（首次部署前正常）"
fi

echo ""
echo "🎯 NAT模式部署测试完成"
echo ""
echo "如果所有检查都通过，可以安全执行："
echo "  ./deploy.sh rebuild"
echo ""
echo "部署后验证命令："
echo "  ./deploy.sh status"
echo "  ./deploy.sh diagnose"