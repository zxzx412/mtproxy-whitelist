#!/bin/bash

# NAT模式 Docker Compose 管理脚本
# 支持两种NAT部署模式：
#   - nat-haproxy: NAT + HAProxy + PROXY Protocol (默认)
#   - nat-direct:  NAT直连模式 (简化版)

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

# 选择NAT模式
select_nat_mode() {
    # 检查是否通过环境变量指定了模式
    if [ -n "$USE_HAPROXY" ]; then
        if [ "$USE_HAPROXY" = "true" ] || [ "$USE_HAPROXY" = "yes" ] || [ "$USE_HAPROXY" = "1" ]; then
            export NAT_MODE="nat-haproxy"
        else
            export NAT_MODE="nat-direct"
        fi
        return
    fi

    # 交互式选择模式
    echo ""
    print_info "请选择NAT部署模式："
    echo "  1) NAT + HAProxy (推荐) - 使用PROXY Protocol获取真实IP"
    echo "  2) NAT直连模式 - Nginx直接监听外部端口"
    echo ""
    read -p "请选择 [1-2] (默认: 1): " choice

    case "$choice" in
        2)
            export NAT_MODE="nat-direct"
            ;;
        1|"")
            export NAT_MODE="nat-haproxy"
            ;;
        *)
            print_error "无效选择，使用默认模式: NAT + HAProxy"
            export NAT_MODE="nat-haproxy"
            ;;
    esac
}

# 获取配置文件名
get_compose_file() {
    if [ "$NAT_MODE" = "nat-direct" ]; then
        echo "docker-compose.nat-direct.yml"
    else
        echo "docker-compose.nat-haproxy.yml"
    fi
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

    # 设置默认值（使用新变量名）
    export EXTERNAL_PROXY_PORT=${EXTERNAL_PROXY_PORT:-${MTPROXY_PORT:-14202}}
    export EXTERNAL_WEB_PORT=${EXTERNAL_WEB_PORT:-${WEB_PORT:-8989}}
    export INTERNAL_PROXY_PROTOCOL_PORT=${INTERNAL_PROXY_PROTOCOL_PORT:-14445}

    # 显示模式信息
    if [ "$NAT_MODE" = "nat-direct" ]; then
        print_info "NAT直连模式配置："
        print_info "  MTProxy端口: ${EXTERNAL_PROXY_PORT}"
        print_info "  Web管理端口: ${EXTERNAL_WEB_PORT}"
        print_info "  无HAProxy层，Nginx直接监听外部端口"
    else
        print_info "NAT+HAProxy模式配置："
        print_info "  MTProxy端口: ${EXTERNAL_PROXY_PORT}"
        print_info "  Web管理端口: ${EXTERNAL_WEB_PORT}"
        print_info "  PROXY Protocol内部端口: ${INTERNAL_PROXY_PROTOCOL_PORT}"
    fi
}

# 检查端口冲突
check_ports() {
    local ports=("${EXTERNAL_PROXY_PORT}" "${EXTERNAL_WEB_PORT}")

    # 如果是HAProxy模式，额外检查PROXY Protocol端口
    if [ "$NAT_MODE" = "nat-haproxy" ]; then
        ports+=("${INTERNAL_PROXY_PROTOCOL_PORT}")
    fi

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

    # 对于非help命令，先选择模式
    if [ "$command" != "help" ] && [ "$command" != "-h" ] && [ "$command" != "--help" ]; then
        select_nat_mode
        COMPOSE_FILE=$(get_compose_file)
        print_info "使用配置文件: $COMPOSE_FILE"
    fi

    case "$command" in
        "up"|"start")
            print_info "启动NAT模式服务..."
            check_env
            check_ports
            docker-compose -f "$COMPOSE_FILE" up -d
            print_success "NAT模式启动完成 (${NAT_MODE})"
            if [ "$NAT_MODE" = "nat-haproxy" ]; then
                print_info "HAProxy处理外部连接，nginx通过PROXY Protocol获取真实IP"
            else
                print_info "Nginx直接监听外部端口"
            fi
            ;;
        "down"|"stop")
            print_info "停止NAT模式服务..."
            docker-compose -f "$COMPOSE_FILE" down
            print_success "服务已停止"
            ;;
        "restart")
            print_info "重启NAT模式服务..."
            docker-compose -f "$COMPOSE_FILE" restart
            print_success "服务已重启"
            ;;
        "logs")
            shift
            docker-compose -f "$COMPOSE_FILE" logs -f "$@"
            ;;
        "ps"|"status")
            docker-compose -f "$COMPOSE_FILE" ps
            ;;
        "build")
            print_info "构建NAT模式镜像..."
            docker-compose -f "$COMPOSE_FILE" build --no-cache
            print_success "镜像构建完成"
            ;;
        "exec")
            shift
            docker-compose -f "$COMPOSE_FILE" exec "$@"
            ;;
        "test-ip")
            print_info "测试真实IP获取..."
            if [ "$NAT_MODE" = "nat-haproxy" ]; then
                print_info "检查HAProxy状态："
                docker-compose -f "$COMPOSE_FILE" exec haproxy haproxy -vv
                print_info "检查nginx PROXY Protocol日志："
                docker-compose -f "$COMPOSE_FILE" exec mtproxy-whitelist tail -20 /var/log/nginx/proxy_protocol_access.log 2>/dev/null || \
                    print_warning "日志文件不存在或无法访问"
            else
                print_info "检查nginx访问日志："
                docker-compose -f "$COMPOSE_FILE" exec mtproxy-whitelist tail -20 /var/log/nginx/access.log 2>/dev/null || \
                    print_warning "日志文件不存在或无法访问"
            fi
            ;;
        "help"|"-h"|"--help")
            echo "NAT模式管理脚本 - 支持两种部署模式"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  up, start     启动服务 (会提示选择模式)"
            echo "  down, stop    停止服务"
            echo "  restart       重启服务"
            echo "  logs          查看日志"
            echo "  ps, status    查看状态"
            echo "  build         构建镜像"
            echo "  exec          执行容器命令"
            echo "  test-ip       测试IP获取"
            echo "  help          显示帮助"
            echo ""
            echo "环境变量:"
            echo "  USE_HAPROXY=true|false  自动选择模式，跳过交互提示"
            echo "  示例: USE_HAPROXY=false $0 up"
            echo ""
            echo "部署模式:"
            echo "  1. NAT + HAProxy (推荐)"
            echo "     ✅ HAProxy前端代理，处理外部连接"
            echo "     ✅ PROXY Protocol传递真实客户端IP"
            echo "     ✅ nginx白名单验证真实IP而非NAT网关IP"
            echo "     ✅ 适用于需要精确IP控制的场景"
            echo ""
            echo "  2. NAT直连模式"
            echo "     ✅ 无HAProxy层，简化架构"
            echo "     ✅ Nginx直接监听外部端口"
            echo "     ✅ 适用于不需要PROXY Protocol的环境"
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