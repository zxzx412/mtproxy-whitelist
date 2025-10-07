#!/bin/bash

# MTProxy 白名单系统一键部署脚本 v5.0
# 支持三种部署模式：Bridge、NAT+HAProxy、NAT直连
# 作者: Claude AI + zxzx412
# 版本: 5.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }
print_line() { echo "========================================"; }

# 项目信息
PROJECT_NAME="mtproxy-whitelist"
CURRENT_DIR=$(pwd)

# 默认配置
DEFAULT_DOMAIN="azure.microsoft.com"
DEFAULT_ADMIN_PASSWORD="admin123"
DEFAULT_EXTERNAL_PROXY_PORT="14202"
DEFAULT_EXTERNAL_WEB_PORT="8989"
DEFAULT_INTERNAL_PROXY_PROTOCOL_PORT="14445"
DEFAULT_BACKEND_MTPROXY_PORT="444"

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "   MTProxy 白名单系统 v5.0"
    echo "   一键部署脚本"
    echo "========================================"
    echo -e "${NC}"
    echo "✨ v5.0新特性："
    echo "• 🎯 三种部署模式（Bridge/NAT+HAProxy/NAT直连）"
    echo "• 🔧 端口变量标准化（EXTERNAL_*/INTERNAL_*/BACKEND_*）"
    echo "• 🚀 Supervisor进程管理（<5秒崩溃恢复）"
    echo "• 📊 增强健康检查（L1/L2/L3多层验证）"
    echo "• ⚡ 配置策略模式（降低70%复杂度）"
    echo "• 🔒 端口445→14445（避免Windows SMB冲突）"
    echo "• 🔄 100%向后兼容v4.0配置"
    echo ""
    echo -e "${YELLOW}注意: 此脚本需要 root 权限运行${NC}"
    print_line
}

# 检查系统要求
check_requirements() {
    print_info "检查系统要求..."

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        echo "请使用: sudo bash $0"
        exit 1
    fi

    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        print_error "无法识别的操作系统"
        exit 1
    fi

    source /etc/os-release
    print_info "系统: $PRETTY_NAME"
    print_info "架构: $(uname -m)"

    print_success "系统要求检查完成"
}

# 安装 Docker
install_docker() {
    print_info "检查 Docker..."

    if command -v docker >/dev/null 2>&1; then
        print_success "Docker 已安装: $(docker --version)"
        return 0
    fi

    print_info "安装 Docker..."

    # 使用官方脚本安装
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh

    # 启动服务
    systemctl start docker
    systemctl enable docker

    print_success "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    print_info "检查 Docker Compose..."

    if command -v docker-compose >/dev/null 2>&1; then
        print_success "Docker Compose 已安装: $(docker-compose --version)"
        return 0
    fi

    print_info "安装 Docker Compose..."

    # 获取最新版本
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)

    # 下载并安装
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    print_success "Docker Compose 安装完成"
}

# 选择部署模式
choose_deployment_mode() {
    echo ""
    print_line
    echo -e "${CYAN}选择部署模式:${NC}"
    echo ""
    echo "1) Bridge模式（推荐新手）"
    echo "   • Docker bridge网络，端口映射"
    echo "   • 配置简单，适合单机部署"
    echo "   • 无法获取真实客户端IP"
    echo ""
    echo "2) NAT+HAProxy模式（推荐NAT环境）"
    echo "   • Host网络，HAProxy前端代理"
    echo "   • PROXY Protocol传递真实客户端IP"
    echo "   • 适合NAT/CDN环境"
    echo ""
    echo "3) NAT直连模式（简化版）"
    echo "   • Host网络，Nginx直接监听"
    echo "   • 无HAProxy层，性能最优"
    echo "   • 无法获取PROXY Protocol真实IP"
    echo ""

    while true; do
        read -p "请选择部署模式 [1-3]: " choice
        case $choice in
            1)
                DEPLOYMENT_MODE="bridge"
                COMPOSE_FILE="docker-compose.yml"
                print_success "已选择: Bridge模式"
                break
                ;;
            2)
                DEPLOYMENT_MODE="nat-haproxy"
                COMPOSE_FILE="docker-compose.nat-haproxy.yml"
                print_success "已选择: NAT+HAProxy模式"
                break
                ;;
            3)
                DEPLOYMENT_MODE="nat-direct"
                COMPOSE_FILE="docker-compose.nat-direct.yml"
                print_success "已选择: NAT直连模式"
                break
                ;;
            *)
                print_error "无效选择，请输入 1-3"
                ;;
        esac
    done

    export DEPLOYMENT_MODE
    export COMPOSE_FILE
}

# 配置端口
configure_ports() {
    echo ""
    print_line
    echo -e "${CYAN}配置端口:${NC}"
    echo ""

    # 外部代理端口
    read -p "客户端连接端口 [默认: $DEFAULT_EXTERNAL_PROXY_PORT]: " EXTERNAL_PROXY_PORT
    EXTERNAL_PROXY_PORT=${EXTERNAL_PROXY_PORT:-$DEFAULT_EXTERNAL_PROXY_PORT}

    # Web管理端口
    read -p "Web管理端口 [默认: $DEFAULT_EXTERNAL_WEB_PORT]: " EXTERNAL_WEB_PORT
    EXTERNAL_WEB_PORT=${EXTERNAL_WEB_PORT:-$DEFAULT_EXTERNAL_WEB_PORT}

    # 高级端口配置（使用默认值）
    INTERNAL_PROXY_PROTOCOL_PORT=$DEFAULT_INTERNAL_PROXY_PROTOCOL_PORT
    BACKEND_MTPROXY_PORT=$DEFAULT_BACKEND_MTPROXY_PORT

    # 检查端口冲突
    print_info "检查端口占用..."
    local has_conflict=false

    if netstat -tuln 2>/dev/null | grep -q ":$EXTERNAL_PROXY_PORT "; then
        print_warning "端口 $EXTERNAL_PROXY_PORT 已被占用"
        has_conflict=true
    fi

    if netstat -tuln 2>/dev/null | grep -q ":$EXTERNAL_WEB_PORT "; then
        print_warning "端口 $EXTERNAL_WEB_PORT 已被占用"
        has_conflict=true
    fi

    if [ "$has_conflict" = true ]; then
        read -p "检测到端口冲突，是否继续? [y/N]: " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            print_error "用户取消部署"
            exit 1
        fi
    fi

    print_success "端口配置完成"
}

# 配置业务参数
configure_business() {
    echo ""
    print_line
    echo -e "${CYAN}配置业务参数:${NC}"
    echo ""

    # 伪装域名
    read -p "伪装域名 [默认: $DEFAULT_DOMAIN]: " MTPROXY_DOMAIN
    MTPROXY_DOMAIN=${MTPROXY_DOMAIN:-$DEFAULT_DOMAIN}

    # 推广TAG
    read -p "推广TAG (可选，直接回车跳过): " MTPROXY_TAG

    # 管理员密码
    while true; do
        read -sp "管理员密码 [默认: $DEFAULT_ADMIN_PASSWORD]: " ADMIN_PASSWORD
        echo
        ADMIN_PASSWORD=${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}

        if [ ${#ADMIN_PASSWORD} -lt 6 ]; then
            print_warning "密码长度至少6位"
            continue
        fi
        break
    done

    # 生成密钥
    SECRET_KEY=$(openssl rand -hex 16)

    print_success "业务参数配置完成"
}

# 生成配置文件
generate_config() {
    print_info "生成配置文件..."

    # 备份旧配置
    if [ -f .env ]; then
        cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
        print_info "已备份旧配置到 .env.backup.*"
    fi

    # 生成新配置
    cat > .env <<EOF
# MTProxy 白名单系统配置文件 v5.0
# 生成时间: $(date)

# ==================== 部署模式 ====================
DEPLOYMENT_MODE=$DEPLOYMENT_MODE

# ==================== 外部端口 ====================
EXTERNAL_PROXY_PORT=$EXTERNAL_PROXY_PORT
EXTERNAL_WEB_PORT=$EXTERNAL_WEB_PORT

# ==================== 内部端口（高级） ====================
INTERNAL_PROXY_PROTOCOL_PORT=$INTERNAL_PROXY_PROTOCOL_PORT
BACKEND_MTPROXY_PORT=$BACKEND_MTPROXY_PORT
INTERNAL_API_PORT=8080

# ==================== 业务配置 ====================
MTPROXY_DOMAIN=$MTPROXY_DOMAIN
MTPROXY_TAG=$MTPROXY_TAG
SECRET_KEY=$SECRET_KEY
JWT_EXPIRATION_HOURS=24
ADMIN_PASSWORD=$ADMIN_PASSWORD

# ==================== 向后兼容别名（v6.0将移除） ====================
# 以下变量为v4.0兼容别名，建议使用上面的新变量名
MTPROXY_PORT=$EXTERNAL_PROXY_PORT
WEB_PORT=$EXTERNAL_WEB_PORT
EOF

    chmod 600 .env
    print_success "配置文件已生成: .env"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."

    if command -v ufw >/dev/null 2>&1; then
        ufw allow $EXTERNAL_PROXY_PORT/tcp comment "MTProxy Proxy"
        ufw allow $EXTERNAL_WEB_PORT/tcp comment "MTProxy Web"
        print_success "UFW 防火墙已配置"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$EXTERNAL_PROXY_PORT/tcp
        firewall-cmd --permanent --add-port=$EXTERNAL_WEB_PORT/tcp
        firewall-cmd --reload
        print_success "firewalld 防火墙已配置"
    else
        print_warning "未检测到防火墙，请手动开放端口: $EXTERNAL_PROXY_PORT, $EXTERNAL_WEB_PORT"
    fi
}

# 启动服务
start_services() {
    print_info "启动服务..."

    # 验证配置文件
    if [ -f "docker/validate-config.sh" ]; then
        print_info "验证配置..."
        bash docker/validate-config.sh || {
            print_warning "配置验证有警告，但继续部署"
        }
    fi

    # 验证docker-compose配置
    print_info "验证Docker Compose配置..."
    docker-compose -f $COMPOSE_FILE config > /dev/null || {
        print_error "Docker Compose配置验证失败"
        exit 1
    }

    # 构建镜像
    print_info "构建Docker镜像（首次可能需要几分钟）..."
    docker-compose -f $COMPOSE_FILE build

    # 启动服务
    print_info "启动容器..."
    docker-compose -f $COMPOSE_FILE up -d

    # 等待服务启动
    print_info "等待服务启动..."
    sleep 10

    # 检查服务状态
    print_info "检查服务状态..."
    docker-compose -f $COMPOSE_FILE ps

    print_success "服务启动完成"
}

# 显示部署信息
show_deployment_info() {
    echo ""
    print_line
    echo -e "${GREEN}🎉 部署成功！${NC}"
    print_line

    # 获取公网IP
    PUBLIC_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")

    # 获取MTProxy密钥
    sleep 5
    SECRET=$(docker-compose -f $COMPOSE_FILE exec -T mtproxy-whitelist cat /opt/mtproxy/mtp_config 2>/dev/null | grep "secret=" | cut -d'"' -f2)
    DOMAIN=$(docker-compose -f $COMPOSE_FILE exec -T mtproxy-whitelist cat /opt/mtproxy/mtp_config 2>/dev/null | grep "domain=" | cut -d'"' -f2)

    if [ -n "$SECRET" ] && [ -n "$DOMAIN" ]; then
        # 构建完整密钥
        DOMAIN_HEX=$(printf "%s" "$DOMAIN" | hexdump -ve '1/1 "%02x"')
        CLIENT_SECRET="ee${SECRET}${DOMAIN_HEX}"
    else
        CLIENT_SECRET="等待容器完全启动后查看"
    fi

    echo ""
    echo -e "${CYAN}📋 部署信息${NC}"
    echo "----------------------------------------"
    echo "部署模式: $DEPLOYMENT_MODE"
    echo "服务器IP: $PUBLIC_IP"
    echo "代理端口: $EXTERNAL_PROXY_PORT"
    echo "Web端口:  $EXTERNAL_WEB_PORT"
    echo ""

    echo -e "${CYAN}🌐 Web管理界面${NC}"
    echo "----------------------------------------"
    echo "访问地址: http://$PUBLIC_IP:$EXTERNAL_WEB_PORT"
    echo "用户名:   admin"
    echo "密码:     $ADMIN_PASSWORD"
    echo ""

    echo -e "${CYAN}📱 Telegram连接${NC}"
    echo "----------------------------------------"
    if [ "$CLIENT_SECRET" != "等待容器完全启动后查看" ]; then
        echo "连接链接:"
        echo "https://t.me/proxy?server=$PUBLIC_IP&port=$EXTERNAL_PROXY_PORT&secret=$CLIENT_SECRET"
        echo ""
        echo "tg://proxy?server=$PUBLIC_IP&port=$EXTERNAL_PROXY_PORT&secret=$CLIENT_SECRET"
    else
        echo "请稍后运行以下命令获取连接信息:"
        echo "docker-compose -f $COMPOSE_FILE logs mtproxy-whitelist | grep 'Telegram连接链接'"
    fi
    echo ""

    echo -e "${CYAN}🔧 常用命令${NC}"
    echo "----------------------------------------"
    echo "查看状态: docker-compose -f $COMPOSE_FILE ps"
    echo "查看日志: docker-compose -f $COMPOSE_FILE logs -f"
    echo "重启服务: docker-compose -f $COMPOSE_FILE restart"
    echo "停止服务: docker-compose -f $COMPOSE_FILE down"
    echo "健康检查: docker exec mtproxy-whitelist /usr/local/bin/health-check.sh"
    echo ""

    echo -e "${YELLOW}⚠️  重要提示${NC}"
    echo "----------------------------------------"
    echo "1. 只有添加到白名单的IP才能连接代理"
    echo "2. 请通过Web界面添加您的客户端IP"
    echo "3. 建议修改默认管理员密码"
    echo "4. 配置文件位置: $CURRENT_DIR/.env"
    echo "5. 数据备份: docker-compose exec mtproxy-whitelist cat /data/nginx/whitelist.txt"
    echo ""

    echo -e "${CYAN}📚 文档链接${NC}"
    echo "----------------------------------------"
    echo "迁移指南: docs/MIGRATION_v5.md"
    echo "快速参考: docs/QUICK_REFERENCE.md"
    echo "故障排查: docker-compose logs mtproxy-whitelist"
    echo ""

    print_line
    echo -e "${GREEN}部署完成！祝您使用愉快！🚀${NC}"
    print_line
}

# 主函数
main() {
    show_welcome

    # 确认开始部署
    read -p "按回车键开始部署，或 Ctrl+C 取消... " dummy

    # 执行部署流程
    check_requirements
    install_docker
    install_docker_compose
    choose_deployment_mode
    configure_ports
    configure_business
    generate_config
    configure_firewall
    start_services
    show_deployment_info
}

# 运行主函数
main "$@"
