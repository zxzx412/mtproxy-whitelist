#!/bin/bash
set -e

echo "🚀 MTProxy 白名单系统 v4.0"
echo "=========================================="

# 初始化配置
CONFIG_FILE="/opt/mtproxy/mtp_config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "生成初始配置..."
    SECRET=$(openssl rand -hex 16)
    PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "127.0.0.1")
    DOMAIN=${MTPROXY_DOMAIN:-"azure.microsoft.com"}
    PORT=${MTPROXY_PORT:-444}
    echo "secret=\"$SECRET\"" > "$CONFIG_FILE"
    echo "domain=\"$DOMAIN\"" >> "$CONFIG_FILE"
    echo "PUBLIC_IP=\"$PUBLIC_IP\"" >> "$CONFIG_FILE"
    echo "MTPROXY_PORT=$PORT" >> "$CONFIG_FILE"
    echo "配置文件已生成: $CONFIG_FILE"
fi

# 初始化nginx配置
mkdir -p /etc/nginx/conf.d /data/nginx

# 设置默认端口值（防止环境变量未设置）
export WEB_PORT=${WEB_PORT:-8888}
export MTPROXY_PORT=${MTPROXY_PORT:-8765}

echo "开始生成nginx配置，WEB_PORT=${WEB_PORT}, MTPROXY_PORT=${MTPROXY_PORT}"

# 根据NAT模式配置nginx监听端口
if [ "${NAT_MODE:-false}" = "true" ]; then
    echo "🔧 NAT模式：配置nginx监听外部端口443用于HAProxy连接"
    # NAT模式下，nginx需要监听443端口接收HAProxy的连接
    export NGINX_STREAM_PORT=443
else
    echo "🔧 Bridge模式：配置nginx监听内部端口443"
    # Bridge模式下，nginx监听443，Docker映射外部端口到443
    export NGINX_STREAM_PORT=443
fi

# 替换环境变量并生成最终配置
envsubst '$WEB_PORT $MTPROXY_PORT $NGINX_STREAM_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "nginx配置文件内容预览："
head -20 /etc/nginx/nginx.conf

# 显示stream配置部分
echo "nginx stream配置预览："
grep -A 10 "listen.*;" /etc/nginx/nginx.conf | head -15

# 初始化白名单文件和映射
echo "127.0.0.1" > /data/nginx/whitelist.txt
echo "::1" >> /data/nginx/whitelist.txt

# 生成nginx白名单映射配置
echo "生成nginx白名单映射配置..."
/usr/local/bin/generate-whitelist-map.sh generate

# 检测NAT环境配置
echo "检测NAT环境配置..."
if [ "${NAT_MODE:-false}" = "true" ]; then
    echo "🔍 检测到NAT模式"
    echo "⚠️  NAT环境需要手动配置白名单或启用透明代理"
    echo "🔒 出于安全考虑，不会自动添加内网段到白名单"
    echo "📖 请参考部署后的说明文档进行安全配置"
    
    # 仅添加必要的本地回环地址
    if ! grep -q "127.0.0.0/8" /data/nginx/whitelist.txt 2>/dev/null; then
        cat >> /data/nginx/whitelist.txt << EOF

# === NAT环境基础配置 ===
# 仅添加本地回环地址，其他IP请通过Web界面手动添加
127.0.0.0/8
::1
EOF
    fi
    
    echo "✅ NAT环境基础配置完成（仅本地回环）"
    echo "🌐 请通过Web界面添加具体的客户端IP地址"
fi

# 启动API服务
echo "启动Flask API..."
mkdir -p /var/log/api /var/log/mtproxy
cd /opt/mtproxy-api
python3 app.py > /var/log/api/stdout.log 2> /var/log/api/stderr.log &
API_PID=$!
echo $API_PID > /run/api.pid
sleep 3

# 启动MTProxy
echo "启动MTProxy..."
cd /opt/mtproxy
source mtp_config
DOMAIN_HEX=$(printf "%s" "$domain" | hexdump -ve '1/1 "%02x"')
CLIENT_SECRET="ee${secret}${DOMAIN_HEX}"

# 根据NAT模式选择正确的IP和端口配置
if [ "${NAT_MODE:-false}" = "true" ]; then
    # NAT模式：使用主机IP和主机网络，直接绑定用户配置的端口
    ADVERTISED_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || hostname -I | cut -d' ' -f1)
    ADVERTISED_PORT=${MTPROXY_PORT}
    echo "NAT模式: 广告IP=${ADVERTISED_IP}, 端口=${ADVERTISED_PORT}"
else
    # 标准bridge模式：MTProxy绑定内部端口444，nginx转发外部端口到444
    ADVERTISED_IP=${PUBLIC_IP}
    ADVERTISED_PORT=${MTPROXY_PORT}
    echo "Bridge模式: 广告IP=${ADVERTISED_IP}, 端口=${ADVERTISED_PORT}"
fi

./mtg run $CLIENT_SECRET -b 0.0.0.0:444 --multiplex-per-connection 500 -t 127.0.0.1:8081 -4 ${ADVERTISED_IP}:${ADVERTISED_PORT} > /var/log/mtproxy/stdout.log 2> /var/log/mtproxy/stderr.log &
MTPROXY_PID=$!
echo $MTPROXY_PID > /run/mtproxy.pid
sleep 5

# 启动Nginx
echo "启动Nginx..."
nginx -t && nginx

# 检查服务启动状态
echo "检查服务启动状态..."
sleep 5

echo "API服务检查:"
if kill -0 $API_PID 2>/dev/null; then
    echo "✅ API服务运行正常 (PID: $API_PID)"
else
    echo "❌ API服务启动失败"
fi

echo "MTProxy服务检查:"
if kill -0 $MTPROXY_PID 2>/dev/null; then
    echo "✅ MTProxy服务运行正常 (PID: $MTPROXY_PID)"
    echo "MTProxy监听端口: 444"
    netstat -tlnp 2>/dev/null | grep ":444 " || echo "⚠️  警告：端口444未在监听"
else
    echo "❌ MTProxy服务启动失败"
    echo "MTProxy日志："
    tail -10 /var/log/mtproxy/stderr.log 2>/dev/null || echo "无法读取错误日志"
fi

echo "Nginx服务检查:"
if pgrep nginx >/dev/null; then
    echo "✅ Nginx服务运行正常"
    echo "Nginx监听端口:"
    netstat -tlnp 2>/dev/null | grep nginx | head -5
else
    echo "❌ Nginx服务未运行"
fi

echo "✅ 所有服务启动完成"

# 保持容器运行
while true; do
    sleep 30
    # 检查进程是否存在
    if ! kill -0 $API_PID 2>/dev/null; then
        echo "❌ API进程已停止，重新启动容器..."
        exit 1
    fi
    if ! kill -0 $MTPROXY_PID 2>/dev/null; then
        echo "❌ MTProxy进程已停止，重新启动容器..."
        exit 1
    fi
    if ! pgrep nginx >/dev/null; then
        echo "❌ Nginx进程已停止，重新启动容器..."
        exit 1
    fi
done