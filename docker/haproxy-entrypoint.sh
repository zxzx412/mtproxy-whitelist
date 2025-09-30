#!/bin/sh

# HAProxy启动脚本 - 处理环境变量替换

# 设置默认值
export MTPROXY_PORT=${MTPROXY_PORT:-14202}
export WEB_PORT=${WEB_PORT:-8787}
export NGINX_WEB_PORT=${NGINX_WEB_PORT:-8787}
export PROXY_PROTOCOL_PORT=${PROXY_PROTOCOL_PORT:-445}

echo "HAProxy启动配置："
echo "  MTProxy端口: ${MTPROXY_PORT}"
echo "  Web端口: ${WEB_PORT}"
echo "  PROXY Protocol端口: ${PROXY_PROTOCOL_PORT}"

# 如果存在模板文件，则进行环境变量替换
if [ -f "/usr/local/etc/haproxy/haproxy.cfg.template" ]; then
    echo "使用模板文件生成HAProxy配置..."
    envsubst < /usr/local/etc/haproxy/haproxy.cfg.template > /usr/local/etc/haproxy/haproxy.cfg
    echo "HAProxy配置文件已生成"
fi

# 验证配置文件
echo "验证HAProxy配置..."
haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

if [ $? -eq 0 ]; then
    echo "✅ HAProxy配置验证通过"
else
    echo "❌ HAProxy配置验证失败"
    exit 1
fi

# 启动HAProxy
echo "启动HAProxy服务..."
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -D