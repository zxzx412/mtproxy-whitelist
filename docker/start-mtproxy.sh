#!/bin/bash
# MTProxy启动脚本
# 从entrypoint.sh提取的MTProxy启动逻辑

set -e

CONFIG_FILE="/opt/mtproxy/mtp_config"

echo "启动MTProxy服务..."

# 加载配置
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在 $CONFIG_FILE"
    exit 1
fi

cd /opt/mtproxy
source mtp_config

# 生成客户端密钥
DOMAIN_HEX=$(printf "%s" "$domain" | hexdump -ve '1/1 "%02x"')
CLIENT_SECRET="ee${secret}${DOMAIN_HEX}"

# 根据NAT模式选择正确的IP和端口配置
if [ "${NAT_MODE:-false}" = "true" ]; then
    # NAT模式：使用主机IP和主机网络，直接绑定用户配置的端口
    ADVERTISED_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || hostname -I | cut -d' ' -f1)
    ADVERTISED_PORT=${EXTERNAL_PROXY_PORT:-${MTPROXY_PORT:-14202}}
    echo "NAT模式: 广告IP=${ADVERTISED_IP}, 广告端口=${ADVERTISED_PORT}"
else
    # Bridge模式：MTProxy绑定内部端口444，nginx转发外部端口到444
    ADVERTISED_IP=${PUBLIC_IP:-$(curl -s --connect-timeout 5 https://api.ipify.org || echo "127.0.0.1")}
    ADVERTISED_PORT=${EXTERNAL_PROXY_PORT:-${MTPROXY_PORT:-14202}}
    echo "Bridge模式: 广告IP=${ADVERTISED_IP}, 广告端口=${ADVERTISED_PORT}"
fi

# 保存连接信息供其他脚本使用
export CLIENT_SECRET
export ADVERTISED_IP
export ADVERTISED_PORT

# 启动MTProxy（前台运行，由Supervisor管理）
echo "MTProxy监听: 0.0.0.0:${BACKEND_MTPROXY_PORT:-444}"
echo "MTProxy广告地址: ${ADVERTISED_IP}:${ADVERTISED_PORT}"

exec ./mtg run $CLIENT_SECRET \
    -b 0.0.0.0:${BACKEND_MTPROXY_PORT:-444} \
    --multiplex-per-connection 500 \
    -t 127.0.0.1:8081 \
    -4 ${ADVERTISED_IP}:${ADVERTISED_PORT}
