#!/bin/bash

# MTProxy 白名单重载脚本
# 用于生成nginx映射文件并重载nginx配置

set -e

# 配置路径
WHITELIST_FILE="/data/nginx/whitelist.txt"
MAP_FILE="/data/nginx/whitelist_map.conf"
NGINX_CONFIG="/etc/nginx/nginx.conf"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 生成白名单映射文件 (使用统一脚本)
generate_whitelist_map() {
    log "调用统一映射生成脚本..."
    
    # 导出环境变量供统一脚本使用
    export WHITELIST_FILE="$WHITELIST_FILE"
    export MAP_FILE="$MAP_FILE"
    
    # 调用统一的映射生成脚本
    if /usr/local/bin/generate-whitelist-map.sh generate; then
        log "映射文件生成成功"
        return 0
    else
        log "错误: 映射文件生成失败"
        return 1
    fi
}

# 重载nginx配置
reload_nginx() {
    log "重载nginx配置..."
    
    # 测试nginx配置
    if nginx -t 2>/dev/null; then
        # 重载nginx
        nginx -s reload
        log "Nginx配置重载成功"
    else
        log "ERROR: Nginx配置测试失败，不执行重载"
        return 1
    fi
}

# 主要功能
case "${1:-reload}" in
    "reload")
        log "开始白名单重载流程..."
        generate_whitelist_map
        reload_nginx
        log "白名单重载完成"
        ;;
    "generate")
        log "仅生成映射文件..."
        generate_whitelist_map
        log "映射文件生成完成"
        ;;
    "test")
        log "测试nginx配置..."
        nginx -t
        ;;
    *)
        echo "用法: $0 {reload|generate|test}"
        echo "  reload   - 生成映射文件并重载nginx (默认)"
        echo "  generate - 仅生成映射文件"
        echo "  test     - 测试nginx配置"
        exit 1
        ;;
esac
