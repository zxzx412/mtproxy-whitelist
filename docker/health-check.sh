#!/bin/bash
# MTProxy Whitelist System - Multi-Layer Health Check Script
# v1.0 - 支持多种部署模式的健康检查

set -e

# 配置错误日志
ERROR_LOG="/var/log/health-check-error.log"
exec 2>>"$ERROR_LOG"

# 获取当前时间戳
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_error() {
    echo "[$(timestamp)] ERROR: $1" >&2
}

log_info() {
    echo "[$(timestamp)] INFO: $1"
}

# L1: 进程检查
check_processes() {
    log_info "L1: Checking process status..."

    # 检查nginx进程
    if ! pgrep -x nginx >/dev/null 2>&1; then
        log_error "Nginx process not running"
        return 1
    fi

    # 检查Python API进程
    if ! pgrep -x python3 >/dev/null 2>&1; then
        log_error "Python3 API process not running"
        return 1
    fi

    # 检查MTProxy进程
    if ! pgrep -x mtg >/dev/null 2>&1; then
        log_error "MTProxy (mtg) process not running"
        return 1
    fi

    log_info "L1: All processes running"
    return 0
}

# L2: 端口监听检查
check_ports() {
    log_info "L2: Checking port listeners..."

    # 获取端口配置（带默认值）
    local BACKEND_MTPROXY_PORT=${BACKEND_MTPROXY_PORT:-444}
    local INTERNAL_API_PORT=${INTERNAL_API_PORT:-8080}

    # 检查MTProxy后端端口
    if ! ss -tlnp 2>/dev/null | grep -q ":${BACKEND_MTPROXY_PORT} "; then
        log_error "MTProxy backend port ${BACKEND_MTPROXY_PORT} not listening"
        return 1
    fi

    # 检查API内部端口
    if ! ss -tlnp 2>/dev/null | grep -q ":${INTERNAL_API_PORT} "; then
        log_error "API internal port ${INTERNAL_API_PORT} not listening"
        return 1
    fi

    log_info "L2: All ports listening correctly"
    return 0
}

# L3: 服务响应检查
check_services() {
    log_info "L3: Checking service responses..."

    local INTERNAL_API_PORT=${INTERNAL_API_PORT:-8080}

    # 检查API健康端点
    if ! curl -f -m 2 -s "http://localhost:${INTERNAL_API_PORT}/health" >/dev/null 2>&1; then
        log_error "API health endpoint not responding on port ${INTERNAL_API_PORT}"
        return 1
    fi

    log_info "L3: All services responding"
    return 0
}

# L4: 部署模式特定检查
check_deployment_mode() {
    local DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-bridge}
    log_info "L4: Checking deployment mode: ${DEPLOYMENT_MODE}"

    case "$DEPLOYMENT_MODE" in
        bridge)
            # Bridge模式：检查nginx监听内部端口443和8888
            if ! ss -tlnp 2>/dev/null | grep nginx | grep -q ":443 "; then
                log_error "Bridge mode: Nginx not listening on port 443"
                return 1
            fi
            if ! ss -tlnp 2>/dev/null | grep nginx | grep -q ":8888 "; then
                log_error "Bridge mode: Nginx not listening on port 8888"
                return 1
            fi
            ;;
        nat-haproxy)
            # NAT+HAProxy模式：检查PROXY Protocol端口
            local INTERNAL_PROXY_PROTOCOL_PORT=${INTERNAL_PROXY_PROTOCOL_PORT:-14445}
            if ! ss -tlnp 2>/dev/null | grep nginx | grep -q ":${INTERNAL_PROXY_PROTOCOL_PORT} "; then
                log_error "NAT-HAProxy mode: Nginx not listening on PROXY Protocol port ${INTERNAL_PROXY_PROTOCOL_PORT}"
                return 1
            fi
            ;;
        nat-direct)
            # NAT直连模式：检查外部端口
            local EXTERNAL_PROXY_PORT=${EXTERNAL_PROXY_PORT:-14202}
            if ! ss -tlnp 2>/dev/null | grep nginx | grep -q ":${EXTERNAL_PROXY_PORT} "; then
                log_error "NAT-Direct mode: Nginx not listening on external port ${EXTERNAL_PROXY_PORT}"
                return 1
            fi
            ;;
        *)
            log_error "Unknown deployment mode: ${DEPLOYMENT_MODE}"
            return 1
            ;;
    esac

    log_info "L4: Deployment mode check passed"
    return 0
}

# 主健康检查流程
main() {
    log_info "========== Health Check Started =========="

    # 执行所有检查层
    if ! check_processes; then
        log_error "Health check failed at L1 (Process Check)"
        exit 1
    fi

    if ! check_ports; then
        log_error "Health check failed at L2 (Port Check)"
        exit 1
    fi

    if ! check_services; then
        log_error "Health check failed at L3 (Service Response Check)"
        exit 1
    fi

    if ! check_deployment_mode; then
        log_error "Health check failed at L4 (Deployment Mode Check)"
        exit 1
    fi

    log_info "========== Health Check Passed =========="
    exit 0
}

# 执行主流程
main
