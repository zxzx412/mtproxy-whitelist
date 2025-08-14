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
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

# 初始化白名单文件和映射
echo "127.0.0.1" > /data/nginx/whitelist.txt
echo "::1" >> /data/nginx/whitelist.txt

# 生成nginx白名单映射配置
echo "生成nginx白名单映射配置..."
/usr/local/bin/generate-whitelist-map.sh generate

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
./mtg run $CLIENT_SECRET -b 0.0.0.0:444 --multiplex-per-connection 500 -t 127.0.0.1:8081 -4 ${PUBLIC_IP}:${MTPROXY_PORT} > /var/log/mtproxy/stdout.log 2> /var/log/mtproxy/stderr.log &
MTPROXY_PID=$!
echo $MTPROXY_PID > /run/mtproxy.pid
sleep 5

# 启动Nginx
echo "启动Nginx..."
nginx -t && nginx

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