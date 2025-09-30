#!/bin/bash

# NAT模式 Docker Compose 管理脚本
# 支持HAProxy + PROXY Protocol的NAT环境真实IP获取

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查环境变量
check_env() {
    if [ ! -f ".env" ]; then
        print_warning "未找到.env文件，使用默认配置"
        cp .env.example .env 2>/dev/null || true
    fi
    
    # 加载环境变量
    if [ -f ".env" ]; then
        export $(grep -v '^#' .env | xargs)
    fi
    
    # 设置默认值
    export MTPROXY_PORT=${MTPROXY_PORT:-14202}
    export WEB_PORT=${WEB_PORT:-8787}
    
    print_info "NAT+HAProxy模式配置："
    print_info "  MTProxy端口: ${MTPROXY_PORT}"
    print_info "  Web管理端口: ${WEB_PORT}"
    print_info "  HAProxy -> nginx PROXY Protocol: 14203"
}

# 检查端口冲突
check_ports() {
    local ports=("${MTPROXY_PORT}" "${WEB_PORT}" "14203")
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            print_warning "端口 ${port} 已被占用"
            print_info "占用进程："
            netstat -tulnp 2>/dev/null | grep ":${port} " || true
        fi
    done
}

# 主函数
main() {
    local command=${1:-up}
    
    case "$command" in
        "up"|"start")
            print_info "启动NAT+HAProxy模式服务..."
            check_env
            check_ports
            docker-compose -f docker-compose.nat.yml up -d
            print_success "NAT+HAProxy模式启动完成"
            print_info "HAProxy处理外部连接，nginx通过PROXY Protocol获取真实IP"
            ;;
        "down"|"stop")
            print_info "停止NAT+HAProxy模式服务..."
            docker-compose -f docker-compose.nat.yml down
            print_success "服务已停止"
            ;;
        "restart")
            print_info "重启NAT+HAProxy模式服务..."
            docker-compose -f docker-compose.nat.yml restart
            print_success "服务已重启"
            ;;
        "logs")
            shift
            docker-compose -f docker-compose.nat.yml logs -f "$@"
            ;;
        "ps"|"status")
            docker-compose -f docker-compose.nat.yml ps
            ;;
        "build")
            print_info "构建NAT+HAProxy模式镜像..."
            docker-compose -f docker-compose.nat.yml build --no-cache
            print_success "镜像构建完成"
            ;;
        "exec")
            shift
            docker-compose -f docker-compose.nat.yml exec "$@"
            ;;
        "test-ip")
            print_info "测试真实IP获取..."
            print_info "检查HAProxy状态："
            docker-compose -f docker-compose.nat.yml exec haproxy haproxy -vv
            print_info "检查nginx PROXY Protocol日志："
            docker-compose -f docker-compose.nat.yml exec mtproxy-whitelist tail -20 /var/log/nginx/proxy_protocol_access.log
            ;;
        "help"|"-h"|"--help")
            echo "NAT+HAProxy模式管理脚本"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  up, start     启动服务"
            echo "  down, stop    停止服务"
            echo "  restart       重启服务"
            echo "  logs          查看日志"
            echo "  ps, status    查看状态"
            echo "  build         构建镜像"
            echo "  exec          执行容器命令"
            echo "  test-ip       测试IP获取"
            echo "  help          显示帮助"
            echo ""
            echo "特性:"
            echo "  ✅ HAProxy前端代理，处理外部连接"
            echo "  ✅ PROXY Protocol传递真实客户端IP"
            echo "  ✅ nginx白名单验证真实IP而非NAT网关IP"
            echo "  ✅ 完全解决NAT环境IP获取问题"
            ;;
        *)
            print_error "未知命令: $command"
            print_info "使用 '$0 help' 查看帮助"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"