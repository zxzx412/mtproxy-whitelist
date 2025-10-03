#!/bin/bash
set -e

echo "🚀 MTProxy 白名单系统 v5.0 (重构版)"
echo "=========================================="

# ===== 阶段1: 变量别名处理（向后兼容） =====
handle_legacy_vars() {
    echo "🔄 检查向后兼容性..."

    # MTPROXY_PORT → EXTERNAL_PROXY_PORT
    if [ -n "$MTPROXY_PORT" ]; then
        echo "⚠️  警告: MTPROXY_PORT已废弃，请使用EXTERNAL_PROXY_PORT"
        export EXTERNAL_PROXY_PORT="${EXTERNAL_PROXY_PORT:-$MTPROXY_PORT}"
    fi

    # WEB_PORT → EXTERNAL_WEB_PORT
    if [ -n "$WEB_PORT" ]; then
        echo "⚠️  警告: WEB_PORT已废弃，请使用EXTERNAL_WEB_PORT"
        export EXTERNAL_WEB_PORT="${EXTERNAL_WEB_PORT:-$WEB_PORT}"
    fi

    # 端口445废弃警告
    if [ "${PROXY_PROTOCOL_PORT:-}" = "445" ]; then
        echo "⚠️  警告: 端口445已废弃（Windows SMB冲突），自动改用14445"
        export INTERNAL_PROXY_PROTOCOL_PORT=14445
    fi

    # 设置默认值
    export EXTERNAL_PROXY_PORT="${EXTERNAL_PROXY_PORT:-14202}"
    export EXTERNAL_WEB_PORT="${EXTERNAL_WEB_PORT:-8989}"
    export INTERNAL_PROXY_PROTOCOL_PORT="${INTERNAL_PROXY_PROTOCOL_PORT:-14445}"
    export BACKEND_MTPROXY_PORT="${BACKEND_MTPROXY_PORT:-444}"
    export INTERNAL_API_PORT="${INTERNAL_API_PORT:-8080}"

    # 向后兼容：保留旧变量名（供其他脚本使用）
    export MTPROXY_PORT="${EXTERNAL_PROXY_PORT}"
    export WEB_PORT="${EXTERNAL_WEB_PORT}"
}

# ===== 阶段2: 加载部署策略 =====
load_strategy() {
    # 兼容旧的NAT_MODE变量
    if [ -n "$NAT_MODE" ] && [ -z "$DEPLOYMENT_MODE" ]; then
        if [ "$NAT_MODE" = "true" ]; then
            if [ "${HAPROXY_ENABLED:-false}" = "true" ]; then
                export DEPLOYMENT_MODE="nat-haproxy"
            else
                export DEPLOYMENT_MODE="nat-direct"
            fi
        else
            export DEPLOYMENT_MODE="bridge"
        fi
        echo "⚠️  警告: NAT_MODE已废弃，自动转换为DEPLOYMENT_MODE=${DEPLOYMENT_MODE}"
    fi

    local mode="${DEPLOYMENT_MODE:-bridge}"
    local strategy_file="/etc/mtproxy/strategies/${mode}.conf"

    if [ ! -f "$strategy_file" ]; then
        echo "❌ 错误：策略文件不存在 $strategy_file"
        echo "支持的模式: bridge, nat-direct, nat-haproxy"
        exit 1
    fi

    echo "🔧 加载部署策略: $mode"
    source "$strategy_file"

    # 显示策略配置
    echo "   策略名称: $STRATEGY_NAME"
    echo "   网络模式: $NETWORK_MODE"
    echo "   HAProxy: $HAPROXY_ENABLED"
    echo "   Nginx Stream端口: $INTERNAL_NGINX_STREAM_PORT"
    echo "   Nginx Web端口: $INTERNAL_NGINX_WEB_PORT"
}

# ===== 阶段3: 验证配置 =====
validate_config() {
    echo "✓ 验证配置..."

    # 验证端口范围
    local ports=(
        "EXTERNAL_PROXY_PORT:${EXTERNAL_PROXY_PORT}"
        "EXTERNAL_WEB_PORT:${EXTERNAL_WEB_PORT}"
        "INTERNAL_PROXY_PROTOCOL_PORT:${INTERNAL_PROXY_PROTOCOL_PORT}"
        "BACKEND_MTPROXY_PORT:${BACKEND_MTPROXY_PORT}"
    )

    for port_spec in "${ports[@]}"; do
        local name="${port_spec%%:*}"
        local value="${port_spec#*:}"

        if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
            echo "❌ 错误: $name=$value 超出有效范围(1-65535)"
            exit 1
        fi
    done

    echo "   ✓ 端口配置验证通过"

    # 验证必需配置
    if [ -z "$MTPROXY_DOMAIN" ]; then
        echo "⚠️  警告: MTPROXY_DOMAIN未设置，使用默认值 azure.microsoft.com"
        export MTPROXY_DOMAIN="azure.microsoft.com"
    fi

    echo "   ✓ 业务配置验证通过"
}

# ===== 阶段4: 初始化配置 =====
initialize_configs() {
    echo "🔧 初始化配置文件..."

    # 初始化MTProxy配置
    CONFIG_FILE="/opt/mtproxy/mtp_config"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "生成MTProxy配置..."
        SECRET=$(openssl rand -hex 16)
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "127.0.0.1")
        DOMAIN=${MTPROXY_DOMAIN:-"azure.microsoft.com"}

        cat > "$CONFIG_FILE" << EOF
secret="$SECRET"
domain="$DOMAIN"
PUBLIC_IP="$PUBLIC_IP"
MTPROXY_PORT=$EXTERNAL_PROXY_PORT
EOF
        echo "   ✓ MTProxy配置已生成"
    fi

    # 初始化nginx目录
    mkdir -p /etc/nginx/conf.d /data/nginx

    # 初始化白名单文件
    if [ ! -f /data/nginx/whitelist.txt ]; then
        cat > /data/nginx/whitelist.txt << 'EOF'
# MTProxy 白名单配置文件
# 每行一个IP地址或CIDR网段

# 本地回环地址
127.0.0.1
::1
EOF
        echo "   ✓ 白名单文件已初始化"
    fi

    # 生成白名单映射
    /usr/local/bin/generate-whitelist-map.sh generate
    echo "   ✓ 白名单映射已生成"
}

# ===== 阶段5: 生成配置文件 =====
generate_configs() {
    echo "🔧 生成配置文件..."

    # 设置环境变量供模板使用
    export NGINX_STREAM_PORT="$INTERNAL_NGINX_STREAM_PORT"
    export NGINX_WEB_PORT="$INTERNAL_NGINX_WEB_PORT"
    export PROXY_PROTOCOL_PORT="$INTERNAL_PROXY_PROTOCOL_PORT"

    # 生成nginx配置
    echo "   生成nginx配置: $NGINX_TEMPLATE"
    envsubst '$WEB_PORT $MTPROXY_PORT $NGINX_STREAM_PORT $NGINX_WEB_PORT $PROXY_PROTOCOL_PORT $EXTERNAL_PROXY_PORT $EXTERNAL_WEB_PORT $INTERNAL_PROXY_PROTOCOL_PORT' \
        < "/etc/nginx/templates/$NGINX_TEMPLATE" \
        > /etc/nginx/nginx.conf

    # 验证nginx配置
    if ! nginx -t 2>&1 | tee /tmp/nginx-test.log; then
        echo "❌ nginx配置验证失败"
        cat /tmp/nginx-test.log
        exit 1
    fi
    echo "   ✓ nginx配置验证通过"

    # 如果启用HAProxy，生成HAProxy配置
    if [ "$HAPROXY_ENABLED" = "true" ]; then
        echo "   生成HAProxy配置"
        envsubst '$MTPROXY_PORT $PROXY_PROTOCOL_PORT $EXTERNAL_PROXY_PORT $INTERNAL_PROXY_PROTOCOL_PORT' \
            < /etc/haproxy/haproxy.cfg.template \
            > /etc/haproxy/haproxy.cfg
        echo "   ✓ HAProxy配置已生成"
    fi
}

# ===== 阶段6: 启动服务 =====
start_services() {
    echo "🚀 启动服务..."

    # 检查是否使用Supervisor
    if command -v supervisord >/dev/null 2>&1 && [ -f /etc/supervisor/supervisord.conf ]; then
        echo "   使用Supervisor管理进程"

        # 如果HAProxy启用，确保HAProxy程序配置存在
        if [ "$HAPROXY_ENABLED" = "true" ]; then
            if [ ! -f /etc/supervisor/conf.d/haproxy.conf ]; then
                cat > /etc/supervisor/conf.d/haproxy.conf << 'EOF'
[program:haproxy]
command=/usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -db
directory=/etc/haproxy
autostart=true
autorestart=true
startretries=10
startsecs=3
redirect_stderr=true
stdout_logfile=/var/log/haproxy/stdout.log
priority=150
EOF
                echo "   ✓ HAProxy supervisor配置已生成"
            fi
        fi

        exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    else
        echo "   使用传统进程管理"
        start_services_traditional
    fi
}

# 传统启动方式（向后兼容）
start_services_traditional() {
    # 启动API服务
    echo "启动Flask API..."
    mkdir -p /var/log/api /var/log/mtproxy /var/log/nginx
    cd /opt/mtproxy-api
    python3 app.py > /var/log/api/stdout.log 2> /var/log/api/stderr.log &
    API_PID=$!
    echo $API_PID > /run/api.pid
    sleep 3

    # 启动MTProxy
    echo "启动MTProxy..."
    /usr/local/bin/start-mtproxy.sh > /var/log/mtproxy/stdout.log 2> /var/log/mtproxy/stderr.log &
    MTPROXY_PID=$!
    echo $MTPROXY_PID > /run/mtproxy.pid
    sleep 5

    # 启动HAProxy（如果启用）
    if [ "$HAPROXY_ENABLED" = "true" ]; then
        echo "启动HAProxy..."
        /usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -db &
        HAPROXY_PID=$!
        echo $HAPROXY_PID > /run/haproxy.pid
        sleep 2
    fi

    # 启动Nginx
    echo "启动Nginx..."
    nginx

    # 显示服务状态
    display_service_status

    # 显示连接信息
    display_connection_info

    # 保持容器运行并监控进程
    monitor_processes
}

# 显示服务状态
display_service_status() {
    echo ""
    echo "=========================================="
    echo "检查服务启动状态..."
    sleep 3

    if [ -f /run/api.pid ]; then
        API_PID=$(cat /run/api.pid)
        if kill -0 $API_PID 2>/dev/null; then
            echo "✅ API服务运行正常 (PID: $API_PID)"
        else
            echo "❌ API服务启动失败"
        fi
    fi

    if [ -f /run/mtproxy.pid ]; then
        MTPROXY_PID=$(cat /run/mtproxy.pid)
        if kill -0 $MTPROXY_PID 2>/dev/null; then
            echo "✅ MTProxy服务运行正常 (PID: $MTPROXY_PID)"
        else
            echo "❌ MTProxy服务启动失败"
        fi
    fi

    if [ "$HAPROXY_ENABLED" = "true" ] && [ -f /run/haproxy.pid ]; then
        HAPROXY_PID=$(cat /run/haproxy.pid)
        if kill -0 $HAPROXY_PID 2>/dev/null; then
            echo "✅ HAProxy服务运行正常 (PID: $HAPROXY_PID)"
        else
            echo "❌ HAProxy服务启动失败"
        fi
    fi

    if pgrep nginx >/dev/null; then
        echo "✅ Nginx服务运行正常"
    else
        echo "❌ Nginx服务未运行"
    fi

    echo "✅ 所有服务启动完成"
}

# 显示连接信息
display_connection_info() {
    echo ""
    echo "=========================================="
    echo "🔗 MTProxy 连接信息："
    echo "=========================================="

    if [ -f /opt/mtproxy/mtp_config ]; then
        source /opt/mtproxy/mtp_config
        DOMAIN_HEX=$(printf "%s" "$domain" | hexdump -ve '1/1 "%02x"')
        CLIENT_SECRET="ee${secret}${DOMAIN_HEX}"

        ADVERTISED_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "$PUBLIC_IP")
        ADVERTISED_PORT=$EXTERNAL_PROXY_PORT

        echo "📱 连接密钥: $CLIENT_SECRET"
        echo "🌐 服务器IP: ${ADVERTISED_IP}"
        echo "🔌 服务端口: ${ADVERTISED_PORT}"
        echo ""
        echo "📋 Telegram连接链接:"
        echo "https://t.me/proxy?server=${ADVERTISED_IP}&port=${ADVERTISED_PORT}&secret=${CLIENT_SECRET}"
        echo ""
        echo "📊 管理界面: http://localhost:${EXTERNAL_WEB_PORT}"
        echo "=========================================="
    fi
}

# 监控进程健康状态
monitor_processes() {
    while true; do
        sleep 30

        # 检查API进程
        if [ -f /run/api.pid ]; then
            API_PID=$(cat /run/api.pid)
            if ! kill -0 $API_PID 2>/dev/null; then
                echo "❌ API进程已停止，重新启动容器..."
                exit 1
            fi
        fi

        # 检查MTProxy进程
        if [ -f /run/mtproxy.pid ]; then
            MTPROXY_PID=$(cat /run/mtproxy.pid)
            if ! kill -0 $MTPROXY_PID 2>/dev/null; then
                echo "❌ MTProxy进程已停止，重新启动容器..."
                exit 1
            fi
        fi

        # 检查HAProxy进程
        if [ "$HAPROXY_ENABLED" = "true" ] && [ -f /run/haproxy.pid ]; then
            HAPROXY_PID=$(cat /run/haproxy.pid)
            if ! kill -0 $HAPROXY_PID 2>/dev/null; then
                echo "❌ HAProxy进程已停止，重新启动容器..."
                exit 1
            fi
        fi

        # 检查Nginx进程
        if ! pgrep nginx >/dev/null; then
            echo "❌ Nginx进程已停止，重新启动容器..."
            exit 1
        fi
    done
}

# ===== 主流程 =====
main() {
    handle_legacy_vars
    load_strategy
    validate_config
    initialize_configs
    generate_configs
    start_services
}

main "$@"
