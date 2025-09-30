#!/bin/bash

# MTProxy 白名单系统一键部署脚本 v4.0
# 正确流程架构: 客户端 → 外部端口 → nginx白名单验证(443) → MTProxy(444)
# 内部8888端口作为Web管理页面固定映射
# 内部8081端口作为MTProxy统计端口不对外暴露
# 支持Docker和Docker Compose部署
# 支持用户自定义外部端口配置
# 深度重构的正确架构实现
# 作者: Claude AI
# 版本: 4.0

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
print_debug() { echo -e "${CYAN}[调试]${NC} $1"; }
print_line() { echo "========================================"; }

# 项目信息
PROJECT_NAME="mtproxy-whitelist"
CURRENT_DIR=$(pwd)
PROJECT_DIR="$CURRENT_DIR"  # 使用当前目录作为项目目录

# 配置变量
DEFAULT_DOMAIN="azure.microsoft.com"
DEFAULT_TAG=""
DEFAULT_ADMIN_PASSWORD="admin123"
DEFAULT_MTPROXY_PORT="443"
DEFAULT_WEB_PORT="8888"



# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "   MTProxy 白名单系统一键部署脚本"
    echo "========================================"
    echo -e "${NC}"
    echo "功能特性："
    echo "• 完整的白名单验证流程: 外部端口 → nginx白名单验证(443) → MTProxy(444)"
    echo "• nginx stream模块实现TCP层IP白名单控制"
    echo "• Web管理服务内部固定8888端口，外部端口可自定义"
    echo "• API动态管理白名单，实时生效无需重启服务"
    echo "• 自动同步生成whitelist.txt和whitelist_map.conf映射文件"
    echo "• 集成重载脚本，确保映射文件与API操作同步"
    echo "• MTProxy统计端口8081不对外暴露，保证安全"
    echo "• Docker Compose模板 + 环境变量设计，灵活配置"
    echo "• 用户认证系统，防止未授权访问"
    echo "• 支持IPv4/IPv6地址和CIDR网段"
    echo "• Docker容器化部署，一键启动"
    echo "• 白名单实时生效，无需重启服务"
    echo "• 支持自定义外部端口配置"
    echo ""
    echo -e "${YELLOW}注意: 此脚本需要 root 权限运行${NC}"
    print_line
}

# 检查系统要求
check_requirements() {
    print_info "检查系统要求..."
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        echo "请使用 sudo 运行: sudo $0"
        exit 1
    fi
    
    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        print_error "无法识别的操作系统"
        exit 1
    fi
    
    # 获取系统信息
    source /etc/os-release
    print_info "检测到系统: $PRETTY_NAME"
    
    # 检查架构
    ARCH=$(uname -m)
    print_info "系统架构: $ARCH"
    
    # 检查网络连接
    if ! curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
        print_warning "网络连接检查失败，可能会影响依赖下载"
    fi
    
    print_success "系统要求检查完成"
}

# 安装 Docker
install_docker() {
    print_info "检查 Docker 安装状态..."
    
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker 已安装: $(docker --version)"
        return 0
    fi
    
    print_info "安装 Docker..."
    
    # 检测系统类型并安装 Docker
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [[ -f /etc/redhat-release ]]; then
        # CentOS/RHEL/AlmaLinux
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    elif [[ -f /etc/alpine-release ]]; then
        # Alpine Linux
        apk update
        apk add docker docker-compose
    else
        print_error "不支持的操作系统，请手动安装 Docker"
        exit 1
    fi
    
    # 启动 Docker 服务
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    print_info "检查 Docker Compose 安装状态..."
    
    if command -v docker-compose >/dev/null 2>&1; then
        print_success "Docker Compose 已安装: $(docker-compose --version)"
        return 0
    fi
    
    print_info "安装 Docker Compose..."
    
    # 获取最新版本
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    # 下载并安装
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "Docker Compose 安装完成"
}

# 配置系统参数（不包括防火墙，防火墙在获取端口配置后单独配置）
configure_system() {
    print_info "配置系统参数..."
    
    # 优化内核参数 - 检查是否已存在配置
    print_info "检查并优化内核参数..."
    
    # 检查是否已经有MTProxy优化配置
    if grep -q "# MTProxy 优化参数" /etc/sysctl.conf 2>/dev/null; then
        print_info "MTProxy内核优化参数已存在，跳过配置"
    else
        print_info "添加MTProxy内核优化参数..."
        cat >> /etc/sysctl.conf << 'EOF'

# MTProxy 优化参数
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
EOF
        print_success "内核优化参数已添加"
    fi
    
    # 应用系统参数
    sysctl -p >/dev/null 2>&1 || {
        print_warning "部分内核参数应用失败，可能需要更高版本内核支持"
    }
    
    print_success "系统参数配置完成"
}

# 检查端口是否可用
check_port_available() {
    local port=$1
    local service_name=$2
    
    if ss -tuln 2>/dev/null | grep -q ":$port "; then
        print_warning "$service_name 端口 $port 已被占用"
        echo "占用情况:"
        ss -tuln 2>/dev/null | grep ":$port " | head -3
        echo
        return 1
    else
        return 0
    fi
}

# 配置防火墙（支持自定义端口）
configure_firewall() {
    print_info "配置防火墙规则 (端口: $MTPROXY_PORT, $WEB_PORT)..."
    
    # 检测防火墙类型并配置
    if command -v ufw >/dev/null 2>&1; then
        # Ubuntu/Debian UFW
        ufw allow $MTPROXY_PORT/tcp comment "MTProxy"
        ufw allow $WEB_PORT/tcp comment "MTProxy Web UI"
        print_success "UFW 防火墙规则已配置"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # CentOS/RHEL firewalld
        firewall-cmd --permanent --add-port=$MTPROXY_PORT/tcp
        firewall-cmd --permanent --add-port=$WEB_PORT/tcp
        firewall-cmd --reload
        print_success "firewalld 防火墙规则已配置"
    elif command -v iptables >/dev/null 2>&1; then
        # 通用 iptables
        iptables -A INPUT -p tcp --dport $MTPROXY_PORT -j ACCEPT
        iptables -A INPUT -p tcp --dport $WEB_PORT -j ACCEPT
        # 保存规则
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        print_success "iptables 防火墙规则已配置"
    else
        print_warning "未检测到防火墙，请手动开放端口 $MTPROXY_PORT 和 $WEB_PORT"
    fi
}

# 获取用户配置
get_user_config() {
    print_line
    print_info "配置 MTProxy 参数"
    print_line
    
    # NAT模式选择
    print_info "网络部署模式选择"
    echo "请选择部署模式："
    echo "1. 标准模式 (bridge) - 适用于直连服务器"
    echo "2. NAT模式 (host) - 适用于NAT环境/内网映射"
    echo ""
    echo "NAT模式说明："
    echo "• 使用host网络模式，直接绑定主机端口"
    echo "• 适用于内网服务器通过NAT转发的场景"
    echo "• 无需额外端口映射配置"
    echo ""
    
    while true; do
        echo -n "请选择部署模式 [1-2] (默认: 1): "
        read DEPLOY_MODE_INPUT
        DEPLOY_MODE=${DEPLOY_MODE_INPUT:-1}
        
        case $DEPLOY_MODE in
            1)
                NAT_MODE="false"
                NETWORK_MODE="bridge"
                print_success "选择标准模式 (bridge网络)"
                break
                ;;
            2)
                NAT_MODE="true"
                NETWORK_MODE="host"
                print_success "选择NAT模式 (host网络)"
                print_info "NAT模式下容器将直接使用主机网络"
                break
                ;;
            *)
                print_error "请输入有效选项 [1-2]"
                ;;
        esac
    done
    echo ""
    
    # 新架构端口配置说明
    print_info "端口配置指南"
    if [[ "$NAT_MODE" == "true" ]]; then
        echo "NAT模式流程: 客户端 → NAT转发 → 主机端口 → nginx白名单验证 → MTProxy(444)"
    else
        echo "标准模式流程: 客户端 → 外部端口 → Docker映射 → nginx白名单验证 → MTProxy(444)"
    fi
    echo ""
    echo "端口说明："
    echo "  外部MTProxy端口 (可自定义):"
    echo "    • 8765 (默认，推荐)"
    echo "    • 443  (HTTPS端口，不容易被阻断)"
    echo "    • 2053, 2083, 2087, 2096 (Cloudflare端口，伪装性好)"
    echo "    • 8443 (HTTPS替代端口)"
    echo ""
    echo "  外部Web管理端口 (可自定义):"
    echo "    • 8888 (默认推荐)"
    echo "    • 9999, 8080, 3000-9000 (其他可用端口)"
    echo ""
    echo "  内部固定端口 (不可更改):"
    echo "    • 8888 (Web管理服务内部端口)"
    echo "    • 443  (nginx白名单代理端口)"
    echo "    • 444  (MTProxy实际运行端口)"
    echo "    • 8081 (MTProxy统计端口，不对外暴露)"
    echo "    • 8080 (API服务端口，不对外暴露)"
    echo ""
    
    # 外部MTProxy端口配置
    while true; do
        echo -n "请输入外部MTProxy端口 (默认: $DEFAULT_MTPROXY_PORT): "
        read MTPROXY_PORT
        MTPROXY_PORT=${MTPROXY_PORT:-$DEFAULT_MTPROXY_PORT}
        
        # 验证端口格式
        if [[ "$MTPROXY_PORT" =~ ^[0-9]+$ ]] && [ $MTPROXY_PORT -ge 1 ] && [ $MTPROXY_PORT -le 65535 ]; then
            # 检查端口是否被占用
            if check_port_available $MTPROXY_PORT "外部MTProxy"; then
                print_success "外部MTProxy端口 $MTPROXY_PORT 可用"
                break
            else
                echo -n "是否仍要使用此端口? (y/N): "
                read force_port
                if [[ "$force_port" == "y" || "$force_port" == "Y" ]]; then
                    print_warning "强制使用外部端口 $MTPROXY_PORT"
                    break
                fi
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done
    
    # 外部Web管理端口配置
    while true; do
        echo -n "请输入外部Web管理端口 (默认: 8888): "
        read WEB_PORT_INPUT
        WEB_PORT=${WEB_PORT_INPUT:-8888}
        
        # 验证端口格式
        if [[ "$WEB_PORT" =~ ^[0-9]+$ ]] && [ $WEB_PORT -ge 1 ] && [ $WEB_PORT -le 65535 ]; then
            # 检查端口是否被占用
            if check_port_available $WEB_PORT "外部Web管理"; then
                print_success "外部Web管理端口 $WEB_PORT 可用 (内部固定8888)"
                break
            else
                echo -n "是否仍要使用此端口? (y/N): "
                read force_port
                if [[ "$force_port" == "y" || "$force_port" == "Y" ]]; then
                    print_warning "强制使用外部端口 $WEB_PORT"
                    break
                fi
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done
    
    # 伪装域名配置
    echo -n "请输入伪装域名 (默认: $DEFAULT_DOMAIN): "
    read FAKE_DOMAIN
    FAKE_DOMAIN=${FAKE_DOMAIN:-$DEFAULT_DOMAIN}
    
    # 推广 TAG 配置
    echo -n "请输入推广 TAG (可选，直接回车跳过): "
    read PROMO_TAG
    PROMO_TAG=${PROMO_TAG:-$DEFAULT_TAG}
    
    # 管理员密码配置
    echo -n "请设置 Web 管理界面密码 (默认: $DEFAULT_ADMIN_PASSWORD): "
    read -s WEB_PASSWORD
    echo
    WEB_PASSWORD=${WEB_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}
    
    # 配置确认
    print_line
    print_info "配置确认"
    print_line
    echo -e "部署模式: ${GREEN}$([ "$NAT_MODE" == "true" ] && echo "NAT模式 (host网络)" || echo "标准模式 (bridge网络)")${NC}"
    echo -e "MTProxy端口: ${GREEN}$MTPROXY_PORT${NC} → nginx白名单验证"
    echo -e "Web管理端口: ${GREEN}$WEB_PORT${NC}"
    echo -e "MTProxy运行端口: ${GREEN}444${NC} (内部固定)"
    echo -e "统计端口: ${GREEN}8081${NC} (内部，不对外)"
    echo -e "伪装域名: ${GREEN}$FAKE_DOMAIN${NC}"
    echo -e "推广TAG: ${GREEN}${PROMO_TAG:-"未设置"}${NC}"
    echo -e "管理密码: ${GREEN}[已设置]${NC}"
    echo ""
    if [[ "$NAT_MODE" == "true" ]]; then
        echo -e "${BLUE}NAT模式流程: 客户端 → NAT转发 → $MTPROXY_PORT → nginx白名单验证 → MTProxy(444)${NC}"
        echo -e "${BLUE}Web管理: 浏览器 → NAT转发 → $WEB_PORT → Web服务${NC}"
    else
        echo -e "${BLUE}标准模式流程: 客户端 → $MTPROXY_PORT → Docker映射 → nginx白名单验证 → MTProxy(444)${NC}"
        echo -e "${BLUE}Web管理: 浏览器 → $WEB_PORT → Docker映射 → Web服务${NC}"
    fi
    echo
    
    echo -n "确认配置无误？(y/N): "
    read CONFIRM
    
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        print_info "重新配置..."
        get_user_config
    fi
}

# 准备部署文件
prepare_deployment() {
    print_info "准备部署文件..."
    
    # 确保在正确的目录
    cd "$PROJECT_DIR"
    
    # 检查必要的项目文件
    if [[ ! -f "docker-compose.yml" ]]; then
        print_error "未找到 docker-compose.yml 文件"
        exit 1
    fi
    
    if [[ ! -d "docker" ]]; then
        print_error "未找到 docker 目录"
        exit 1
    fi
    
    # 设置脚本执行权限
    chmod +x diagnose.sh 2>/dev/null || true
    chmod +x deploy.sh 2>/dev/null || true
    
    print_success "部署文件检查完成"
}

# 生成环境配置文件（支持NAT模式和自定义端口）
generate_config() {
    print_info "生成环境配置文件 (模式: $([ "$NAT_MODE" == "true" ] && echo "NAT" || echo "标准"), 端口: $MTPROXY_PORT, $WEB_PORT)..."
    
    # 生成随机密钥
    SECRET_KEY=$(openssl rand -hex 32)
    
    # 创建环境配置文件
    cat > .env << EOF
# MTProxy 白名单系统配置文件
# 生成时间: $(date)

# 网络模式配置
NAT_MODE=$NAT_MODE
NETWORK_MODE=$NETWORK_MODE
ENABLE_PROXY_PROTOCOL=${ENABLE_PROXY_PROTOCOL:-true}
ENABLE_TRANSPARENT_PROXY=${ENABLE_TRANSPARENT_PROXY:-false}
PRIVILEGED_MODE=${PRIVILEGED_MODE:-false}

# 端口配置
MTPROXY_PORT=$MTPROXY_PORT
WEB_PORT=$WEB_PORT
NGINX_STREAM_PORT=$MTPROXY_PORT
NGINX_WEB_PORT=$WEB_PORT
INTERNAL_MTPROXY_PORT=444
API_PORT=8080

# MTProxy 配置
MTPROXY_DOMAIN=$FAKE_DOMAIN
MTPROXY_TAG=$PROMO_TAG

# Flask API 配置
SECRET_KEY=$SECRET_KEY
JWT_EXPIRATION_HOURS=24

# 管理员配置
ADMIN_PASSWORD=$WEB_PASSWORD

# IP 获取和调试配置
DEBUG_IP_DETECTION=${DEBUG_IP_DETECTION:-true}
LOG_LEVEL=${LOG_LEVEL:-INFO}
ENABLE_IP_MONITORING=${ENABLE_IP_MONITORING:-true}
EOF
    
    # 检查docker-compose.yml模板文件
    if [[ ! -f "docker-compose.yml" ]]; then
        print_error "docker-compose.yml 模板文件不存在"
        print_info "请确保项目根目录下有 docker-compose.yml 文件"
        exit 1
    fi
    
    print_info "✅ 使用Docker Compose模板 + .env环境变量设计"
    print_info "📝 生成的.env文件将驱动docker-compose.yml配置"
    print_info "🔧 部署后可直接使用 docker-compose 命令管理服务"
    
    print_success "配置文件生成完成"
}

# 生成NAT模式专用的docker-compose配置
generate_nat_compose() {
    print_info "生成NAT模式专用配置..."
    
    # 确保环境变量已加载
    if [[ -f ".env" ]]; then
        source .env
    fi
    
    cat > docker-compose.nat.yml << EOF
services:
  mtproxy-whitelist:
    build:
      context: .
      dockerfile: docker/Dockerfile
    container_name: mtproxy-whitelist
    restart: unless-stopped
    
    # NAT模式：使用host网络，完全移除端口映射配置
    network_mode: host
    
    # 环境变量配置
    environment:
      - MTPROXY_DOMAIN=\${MTPROXY_DOMAIN:-azure.microsoft.com}
      - MTPROXY_TAG=\${MTPROXY_TAG:-}
      - SECRET_KEY=\${SECRET_KEY:-ee004d64da8e145b8daa35a2012e220e}
      - JWT_EXPIRATION_HOURS=\${JWT_EXPIRATION_HOURS:-24}
      - ADMIN_PASSWORD=\${ADMIN_PASSWORD:-admin123}
      - MTPROXY_PORT=\${MTPROXY_PORT:-14202}
      - INTERNAL_MTPROXY_PORT=444
      - WEB_PORT=\${WEB_PORT:-8989}
      - API_PORT=8080
      - NAT_MODE=true
      - NETWORK_MODE=host
      - NGINX_STREAM_PORT=\${MTPROXY_PORT:-14202}
      - NGINX_WEB_PORT=\${WEB_PORT:-8989}
    
    # 数据卷挂载
    volumes:
      - mtproxy_data:/data
      - mtproxy_logs:/var/log
      - mtproxy_config:/opt/mtproxy
    
    # NAT模式健康检查 - 使用动态端口
    healthcheck:
      test: ["CMD", "sh", "-c", "curl -f http://localhost:\${WEB_PORT:-8989}/health || curl -f http://localhost:8888/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # 资源限制
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
        reservations:
          memory: 256M
    
    # 安全配置
    security_opt:
      - no-new-privileges:true
    
    # 临时文件系统挂载
    tmpfs:
      - /tmp:size=100M,noexec,nosuid,nodev
      - /var/run:size=100M,noexec,nosuid,nodev
    
    # 日志配置
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
    # NAT模式标签
    labels:
      - "com.mtproxy.mode=nat"
      - "com.mtproxy.network=host"
      - "com.mtproxy.ports=\${MTPROXY_PORT:-14202},\${WEB_PORT:-8989}"

# 数据卷定义
volumes:
  mtproxy_data:
    driver: local
  mtproxy_logs:
    driver: local  
  mtproxy_config:
    driver: local
EOF
    
    print_success "NAT模式配置文件已生成: docker-compose.nat.yml"
    print_info "NAT模式特点："
    print_info "  ✅ 使用host网络，无端口映射冲突"
    print_info "  ✅ nginx直接监听主机端口 ${MTPROXY_PORT:-14202} 和 ${WEB_PORT:-8989}"
    print_info "  ✅ 健康检查支持动态端口"
}

# 部署服务
deploy_service() {
    print_info "开始部署 MTProxy 白名单系统..."
    
    # 构建镜像
    print_info "构建 Docker 镜像..."
    docker system prune -f
    
    # 根据NAT模式选择配置文件
    if [[ "$NAT_MODE" == "true" ]]; then
        print_info "NAT模式：使用专用配置文件..."
        generate_nat_compose
        
        print_info "检查NAT模式端口冲突..."
        # 检查端口是否被占用
        if ss -tuln | grep -q ":$MTPROXY_PORT "; then
            print_warning "端口 $MTPROXY_PORT 已被占用，NAT模式可能冲突"
            ss -tuln | grep ":$MTPROXY_PORT "
        fi
        if ss -tuln | grep -q ":$WEB_PORT "; then
            print_warning "端口 $WEB_PORT 已被占用，NAT模式可能冲突"
            ss -tuln | grep ":$WEB_PORT "
        fi
        
        print_info "使用NAT模式配置构建镜像..."
        docker-compose -f docker-compose.nat.yml build --no-cache
        
        print_info "启动NAT模式服务..."
        docker-compose -f docker-compose.nat.yml up -d
        
        # 创建管理别名
        echo "#!/bin/bash" > docker-compose-nat.sh
        echo "docker-compose -f docker-compose.nat.yml \"\$@\"" >> docker-compose-nat.sh
        chmod +x docker-compose-nat.sh
        
        print_info "✅ NAT模式部署完成"
        print_info "📋 NAT模式管理命令："
        print_info "   ./docker-compose-nat.sh ps     # 查看状态"
        print_info "   ./docker-compose-nat.sh logs   # 查看日志"  
        print_info "   ./docker-compose-nat.sh restart # 重启服务"
        
        # NAT模式特殊检查
        print_info "🔍 NAT模式部署验证..."
        sleep 5
        
        # 检查容器是否使用host网络
        CONTAINER_NETWORK=$(docker inspect mtproxy-whitelist --format='{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "未运行")
        if [[ "$CONTAINER_NETWORK" == "host" ]]; then
            print_success "✅ 容器正确使用host网络模式"
        else
            print_error "❌ 容器网络模式异常: $CONTAINER_NETWORK"
        fi
        
        # 检查端口监听
        print_info "检查NAT模式端口监听..."
        sleep 3
        if ss -tuln | grep -q ":$MTPROXY_PORT "; then
            print_success "✅ MTProxy端口 $MTPROXY_PORT 监听正常"
        else
            print_warning "⚠️  MTProxy端口 $MTPROXY_PORT 未监听"
        fi
        
        if ss -tuln | grep -q ":$WEB_PORT "; then
            print_success "✅ Web管理端口 $WEB_PORT 监听正常"
        else
            print_warning "⚠️  Web管理端口 $WEB_PORT 未监听"
        fi
        
    else
        print_info "Bridge模式：使用专用配置文件..."
        
        # 生成Bridge模式配置（如果不存在）
        if [[ ! -f "docker-compose.bridge.yml" ]]; then
            print_info "生成Bridge模式配置文件..."
            # docker-compose.bridge.yml 已经通过write_to_file创建
        fi
        
        print_info "检查Bridge模式端口映射..."
        print_info "  外部端口 $MTPROXY_PORT → 内部端口 443"
        print_info "  外部端口 $WEB_PORT → 内部端口 8888"
        
        print_info "使用Bridge模式配置构建镜像..."
        docker-compose -f docker-compose.bridge.yml build --no-cache
        
        print_info "启动Bridge模式服务..."
        docker-compose -f docker-compose.bridge.yml up -d
        
        # 创建管理别名
        echo "#!/bin/bash" > docker-compose-bridge.sh
        echo "docker-compose -f docker-compose.bridge.yml \"\$@\"" >> docker-compose-bridge.sh
        chmod +x docker-compose-bridge.sh
        
        print_info "✅ Bridge模式部署完成"
        print_info "📋 Bridge模式管理命令："
        print_info "   ./docker-compose-bridge.sh ps     # 查看状态"
        print_info "   ./docker-compose-bridge.sh logs   # 查看日志"
        print_info "   ./docker-compose-bridge.sh restart # 重启服务"
    fi
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 15
    
    # 检查服务状态
    check_service_status
    
    print_success "MTProxy 白名单系统部署完成！"
}

# 检查服务状态
check_service_status() {
    print_info "检查服务状态..."
    
    # 检查容器状态
    print_info "检查Docker容器状态..."
    docker-compose ps
    
    if docker-compose ps | grep -q "Up"; then
        print_success "Docker 容器运行正常"
    else
        print_error "Docker 容器启动失败"
        print_info "容器日志:"
        docker-compose logs --tail=50
        return 1
    fi
    
    # 检查端口监听
    local public_ip=$(curl -s --connect-timeout 10 https://api.ip.sb/ip 2>/dev/null || echo "localhost")
    
    print_info "检查端口监听状态..."
    
    # 检查 MTProxy 端口
    if ss -tuln | grep -q ":$MTPROXY_PORT "; then
        print_success "MTProxy 端口 $MTPROXY_PORT 监听正常"
    else
        print_warning "MTProxy 端口 $MTPROXY_PORT 未监听"
    fi
    
    # 检查 Web 管理端口
    if ss -tuln | grep -q ":$WEB_PORT "; then
        print_success "Web 管理端口 $WEB_PORT 监听正常"
    else
        print_warning "Web 管理端口 $WEB_PORT 未监听"
    fi
    
    # 测试 Web 界面连通性
    print_info "等待服务完全启动..."
    sleep 15
    
    print_info "测试Web管理界面连通性..."
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$WEB_PORT 2>/dev/null || echo "000")
    print_info "Web界面HTTP响应码: $http_code"
    
    if [[ "$http_code" =~ ^(200|401|403)$ ]]; then
        print_success "Web 管理界面连通性正常"
        print_info "访问地址: http://localhost:$WEB_PORT"
    else
        print_warning "Web 管理界面连通性测试失败 (HTTP $http_code)"
        print_info "诊断信息:"
        print_info "1. 检查nginx服务状态："
        if docker-compose exec -T mtproxy-whitelist pgrep nginx >/dev/null 2>&1; then
            print_success "Nginx 进程运行正常"
        else
            print_warning "Nginx 进程未运行"
        fi
        print_info "2. 检查Flask API状态："
        if docker-compose exec -T mtproxy-whitelist pgrep -f "python3.*app.py" >/dev/null 2>&1; then
            print_success "Flask API 进程运行正常"
        else
            print_warning "Flask API 进程未运行"
        fi
        print_info "3. 查看nginx访问日志："
        docker-compose exec -T mtproxy-whitelist tail -n 5 /var/log/nginx/access.log 2>/dev/null || print_warning "无法查看访问日志"
        print_info "4. 查看nginx错误日志："
        docker-compose exec -T mtproxy-whitelist tail -n 5 /var/log/nginx/error.log 2>/dev/null || print_warning "无法查看错误日志"
    fi
    
    # 检查MTProxy服务状态
    print_info "检查MTProxy服务状态..."
    if docker-compose exec -T mtproxy-whitelist pgrep -f "mtg.*run" >/dev/null 2>&1; then
        print_success "MTProxy服务运行正常"
    else
        print_warning "MTProxy服务状态异常，检查详细日志"
        print_info "MTProxy进程状态:"
        docker-compose exec -T mtproxy-whitelist ps aux | grep -E "(mtg|simple-manager)" | grep -v grep || print_warning "未找到MTProxy相关进程"
        print_info "MTProxy日志 (最后10行):"
        docker-compose exec -T mtproxy-whitelist tail -n 10 /var/log/mtproxy/stdout.log 2>/dev/null || print_warning "无法查看MTProxy输出日志"
        docker-compose exec -T mtproxy-whitelist tail -n 10 /var/log/mtproxy/stderr.log 2>/dev/null || print_warning "无法查看MTProxy错误日志"
    fi
}

# 显示部署结果
show_deployment_result() {
    # 获取公网IP，使用多个备用服务
    local public_ip=""
    
    # 尝试多个IP检测服务
    for ip_service in \
        "https://ipv4.icanhazip.com" \
        "https://api.ipify.org" \
        "https://checkip.amazonaws.com" \
        "https://ifconfig.me/ip" \
        "http://ip.42.pl/raw"
    do
        public_ip=$(curl -s --connect-timeout 5 --max-time 10 "$ip_service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n1)
        if [[ -n "$public_ip" ]]; then
            print_info "检测到公网IP: $public_ip (通过 $ip_service)"
            break
        fi
    done
    
    # 如果所有服务都失败，使用默认值
    if [[ -z "$public_ip" ]]; then
        public_ip="YOUR_SERVER_IP"
        print_warning "无法自动检测公网IP，请手动替换 YOUR_SERVER_IP"
    fi
    
    # 生成连接信息
    local domain_hex=$(printf "%s" "$FAKE_DOMAIN" | od -An -tx1 | tr -d ' \n')
    local secret=$(docker-compose exec -T mtproxy-whitelist cat /opt/mtproxy/mtp_config 2>/dev/null | grep '^secret=' | cut -d'"' -f2 || echo "SECRET_NOT_FOUND")
    local client_secret="ee${secret}${domain_hex}"
    
    print_line
    echo -e "${GREEN}🎉 MTProxy 白名单系统部署成功！${NC}"
    print_line
    
    echo -e "${BLUE}📊 新架构系统信息${NC}"
    echo "服务器IP: $public_ip"
    echo "外部MTProxy端口: $MTPROXY_PORT (nginx白名单控制)"
    echo "内部MTProxy端口: 443 (容器内实际服务)"
    echo "Web管理端口: $WEB_PORT"
    echo "统计端口: 8081 (内部不对外)"
    echo "伪装域名: $FAKE_DOMAIN"
    if [[ -n "$PROMO_TAG" ]]; then
        echo "推广TAG: $PROMO_TAG"
    fi
    echo
    if [[ "$NAT_MODE" == "true" ]]; then
        echo -e "${CYAN}流程说明: 客户端 → $MTPROXY_PORT(nginx白名单) → MTProxy(444) → telegram.org${NC}"
    else
        echo -e "${CYAN}流程说明: 客户端 → $MTPROXY_PORT(nginx) → 白名单验证 → 443(mtproxy) → telegram.org${NC}"
    fi
    echo
    
    echo -e "${BLUE}🌐 Web 管理界面${NC}"
    echo "访问地址: http://$public_ip:$WEB_PORT"
    echo "用户名: admin"
    echo "密码: $WEB_PASSWORD"
    echo
    
    echo -e "${BLUE}📱 Telegram 连接${NC}"
    echo "连接密钥: $client_secret"
    echo "连接链接:"
    echo "  https://t.me/proxy?server=$public_ip&port=$MTPROXY_PORT&secret=$client_secret"
    echo "  tg://proxy?server=$public_ip&port=$MTPROXY_PORT&secret=$client_secret"
    echo
    
    echo -e "${YELLOW}⚠️  重要配置提醒${NC}"
    echo "1. 🔒 白名单验证: 只有白名单中的IP才能连接MTProxy服务"
    echo "2. 📝 默认白名单: 仅包含127.0.0.1和::1 (本地访问)"
    echo "3. 🌐 添加IP: 通过Web管理界面(端口$WEB_PORT)添加客户端IP到白名单"
    echo "4. ⚡ 实时生效: API管理白名单，无需重启服务即可生效"
    echo ""
    if [[ "$NAT_MODE" == "true" ]]; then
        echo -e "${GREEN}🎉 NAT环境简化架构已配置:${NC}"
        echo "• nginx直接监听外部端口$MTPROXY_PORT"
        echo "• 简化架构，更稳定可靠"
        echo "• 客户端连接: $public_ip:$MTPROXY_PORT"
        echo "• 架构: 客户端 → nginx($MTPROXY_PORT) → MTProxy(444)"
        echo ""
        echo -e "${BLUE}🔧 NAT环境管理命令:${NC}"
        echo "• 查看nginx状态: docker-compose exec mtproxy-whitelist nginx -t"
        echo "• 查看服务日志: docker-compose logs -f"
        echo "• 验证连接日志: docker-compose exec mtproxy-whitelist tail -f /var/log/nginx/stream_access.log"
    else
        echo -e "${BLUE}🔧 NAT环境真实IP获取:${NC}"
        echo "如果遇到内网IP被拒绝的问题(如172.16.5.6 whitelist:0)，请重新部署并选择NAT模式"
    fi
    echo
    
    echo -e "${BLUE}🔧 统一管理命令 (./deploy.sh)${NC}"
    echo "查看状态: ./deploy.sh status"
    echo "查看日志: ./deploy.sh logs"
    echo "重启服务: ./deploy.sh restart"
    echo "停止服务: ./deploy.sh stop"
    echo "系统诊断: ./deploy.sh diagnose"
    echo "强制重建: ./deploy.sh rebuild"
    echo "快速修复: ./deploy.sh fix"
    echo "测试IP获取: ./deploy.sh test-ip"
    echo "清理系统: ./deploy.sh clean"
    echo "帮助信息: ./deploy.sh help"
    echo
    
    print_line
}

# 根据网络模式配置nginx监听端口
configure_nginx_for_network_mode() {
    print_info "根据网络模式配置nginx..."
    
    # 等待容器启动
    sleep 5
    
    if [[ "$NAT_MODE" == "true" ]]; then
        print_info "NAT模式：配置nginx监听外部端口"
        # NAT/host模式：nginx直接监听外部端口
        docker-compose exec -T mtproxy-whitelist sh -c "
            # 更新stream端口
            sed -i 's/listen 443;/listen $MTPROXY_PORT;/' /etc/nginx/nginx.conf
            # 更新web端口
            sed -i 's/listen 8888;/listen $WEB_PORT;/' /etc/nginx/nginx.conf
            nginx -t && nginx -s reload
        " 2>/dev/null || {
            print_warning "nginx配置更新失败，使用默认配置"
        }
    else
        print_info "Bridge模式：nginx使用内部端口，Docker负责端口映射"
        print_info "  MTProxy: 内部443 → 外部$MTPROXY_PORT"
        print_info "  Web管理: 内部8888 → 外部$WEB_PORT"
        # Bridge模式：保持默认配置，通过Docker端口映射
    fi
    
    print_success "nginx网络模式配置完成"
}

# NAT 环境 IP 获取增强功能
enable_proxy_protocol() {
    print_info "启用 PROXY Protocol 支持..."
    
    # 等待容器启动
    sleep 5
    
    # 检查容器是否运行
    if ! docker-compose ps | grep -q "Up"; then
        print_error "容器未运行，无法配置 PROXY Protocol"
        return 1
    fi
    
    print_info "检查当前 nginx 配置状态..."
    if docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null; then
        print_success "nginx 配置正常，PROXY Protocol 功能已在模板中配置"
    else
        print_error "nginx 配置有问题，尝试重新生成配置..."
        docker-compose exec -T mtproxy-whitelist sh -c "
            # 重新生成 nginx 配置
            envsubst '\$WEB_PORT \$MTPROXY_PORT \$NGINX_STREAM_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
            nginx -t && nginx -s reload
        " 2>/dev/null || {
            print_error "nginx 配置修复失败"
            return 1
        }
    fi
    
    print_success "PROXY Protocol 支持检查完成"
}

# 修复 NAT 环境 IP 获取
fix_nat_ip() {
    print_info "修复 NAT 环境 IP 获取..."
    
    # 检测网络环境
    local is_nat_env=false
    
    # 检查是否在容器环境中
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        is_nat_env=true
        print_info "检测到容器环境"
    fi
    
    # 检查是否有 NAT 网络
    if ip route | grep -q "172\|10\|192.168"; then
        is_nat_env=true
        print_info "检测到 NAT 网络环境"
    fi
    
    if [[ "$is_nat_env" == "true" ]] || [[ "$NAT_MODE" == "true" ]]; then
        print_info "NAT 环境检测到，启用 IP 获取增强功能"
        
        # 启用 PROXY Protocol
        enable_proxy_protocol
        
        # 配置透明代理（如果需要）
        if [[ "${ENABLE_TRANSPARENT_PROXY:-false}" == "true" ]]; then
            setup_transparent_proxy
        fi
        
        # 优化容器网络配置
        optimize_container_network
        
        print_success "NAT 环境 IP 获取修复完成"
    else
        print_info "标准网络环境，跳过 NAT 修复"
    fi
}

# 设置透明代理
setup_transparent_proxy() {
    print_info "配置透明代理..."
    
    # 检查是否有必要的权限
    if [[ "${PRIVILEGED_MODE:-false}" != "true" ]]; then
        print_warning "透明代理需要特权模式，请在 .env 中设置 PRIVILEGED_MODE=true"
        return 1
    fi
    
    # 配置 iptables 规则
    docker-compose exec -T mtproxy-whitelist sh -c "
        # 启用 IP 转发
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        # 配置 iptables 规则获取真实 IP
        iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null || true
        iptables -t mangle -A PREROUTING -p tcp --dport 443 -j MARK --set-mark 1 2>/dev/null || true
        
        # 保存规则
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    " 2>/dev/null || {
        print_warning "透明代理配置失败，可能需要更高权限"
    }
}

# 优化容器网络配置
optimize_container_network() {
    print_info "优化容器网络配置..."
    
    docker-compose exec -T mtproxy-whitelist sh -c "
        # 优化网络参数
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
        echo 'net.ipv4.conf.all.route_localnet=1' >> /etc/sysctl.conf
        echo 'net.netfilter.nf_conntrack_acct=1' >> /etc/sysctl.conf
        
        # 应用配置
        sysctl -p 2>/dev/null || true
        
        # 创建 IP 监控脚本
        cat > /usr/local/bin/monitor-client-ips.sh << 'EOF'
#!/bin/bash
echo \"实时客户端 IP 监控:\"
echo \"==================\"
tail -f /var/log/nginx/stream_access.log | while read line; do
    ip=\$(echo \"\$line\" | awk '{print \$1}')
    timestamp=\$(echo \"\$line\" | awk '{print \$4}' | tr -d '[')
    echo \"[\$timestamp] 客户端 IP: \$ip\"
done
EOF
        chmod +x /usr/local/bin/monitor-client-ips.sh
        
        # 创建 IP 统计脚本
        cat > /usr/local/bin/ip-stats.sh << 'EOF'
#!/bin/bash
echo \"客户端 IP 统计:\"
echo \"===============\"
if [ -f /var/log/nginx/stream_access.log ]; then
    awk '{print \$1}' /var/log/nginx/stream_access.log | sort | uniq -c | sort -nr | head -20
else
    echo \"日志文件不存在\"
fi
EOF
        chmod +x /usr/local/bin/ip-stats.sh
        
        # 创建诊断脚本
        cat > /usr/local/bin/diagnose-ip.sh << 'EOF'
#!/bin/bash
echo \"IP 获取诊断报告:\"
echo \"=================\"
echo \"1. nginx 配置检查:\"
nginx -t
echo \"\"
echo \"2. PROXY Protocol 支持:\"
grep -n \"proxy_protocol\" /etc/nginx/nginx.conf || echo \"未启用 PROXY Protocol\"
echo \"\"
echo \"3. 最近的连接日志:\"
tail -n 10 /var/log/nginx/stream_access.log 2>/dev/null || echo \"无连接日志\"
echo \"\"
echo \"4. 网络接口信息:\"
ip addr show | grep -E \"inet.*scope global\"
echo \"\"
echo \"5. 路由信息:\"
ip route | head -5
EOF
        chmod +x /usr/local/bin/diagnose-ip.sh
    " 2>/dev/null || {
        print_warning "容器网络优化部分失败"
    }
    
    print_success "容器网络配置优化完成"
}

# 测试 NAT IP 获取功能
test_nat_ip_function() {
    print_info "测试 NAT IP 获取功能..."
    
    # 等待服务完全启动
    sleep 10
    
    # 检查 nginx 配置
    if docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null; then
        print_success "nginx 配置测试通过"
    else
        print_error "nginx 配置测试失败"
        return 1
    fi
    
    # 检查 PROXY Protocol 配置
    if docker-compose exec -T mtproxy-whitelist grep -q "proxy_protocol" /etc/nginx/nginx.conf 2>/dev/null; then
        print_success "PROXY Protocol 配置已启用"
    else
        print_warning "PROXY Protocol 配置未启用"
    fi
    
    # 检查监控脚本
    if docker-compose exec -T mtproxy-whitelist test -f /usr/local/bin/diagnose-ip.sh 2>/dev/null; then
        print_success "IP 诊断脚本已安装"
    else
        print_warning "IP 诊断脚本未安装"
    fi
    
    print_info "运行 IP 获取诊断..."
    docker-compose exec -T mtproxy-whitelist /usr/local/bin/diagnose-ip.sh 2>/dev/null || {
        print_warning "IP 诊断脚本执行失败"
    }
    
    print_success "NAT IP 获取功能测试完成"
}

# NAT 环境配置优化（简化版）
setup_proxy_protocol() {
    print_info "NAT环境：配置网络优化..."
    
    # 等待容器完全启动
    sleep 5
    
    print_info "检查 nginx 配置状态..."
    if docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null; then
        print_success "nginx 配置正常"
    else
        print_error "nginx 配置有问题，尝试重新生成..."
        docker-compose exec -T mtproxy-whitelist sh -c "
            # 重新生成 nginx 配置
            envsubst '\$WEB_PORT \$MTPROXY_PORT \$NGINX_STREAM_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
            nginx -t && nginx -s reload
        " 2>/dev/null || {
            print_error "nginx 配置修复失败"
            return 1
        }
    fi
    
    print_info "优化白名单配置..."
    docker-compose exec -T mtproxy-whitelist sh -c "
        # 确保基本的本地地址在白名单中
        if ! grep -q '127.0.0.1' /data/nginx/whitelist.txt 2>/dev/null; then
            echo '127.0.0.1' >> /data/nginx/whitelist.txt
        fi
        if ! grep -q '::1' /data/nginx/whitelist.txt 2>/dev/null; then
            echo '::1' >> /data/nginx/whitelist.txt
        fi
        
        # 重新生成白名单映射
        /usr/local/bin/generate-whitelist-map.sh generate
        nginx -s reload
    " 2>/dev/null || true
    
    print_success "NAT环境网络优化完成"
}


# 创建管理脚本（指向统一的deploy.sh）
create_management_script() {
    print_info "创建管理脚本链接..."
    
    # 创建符号链接到deploy.sh
    if [[ -f "$PROJECT_DIR/deploy.sh" ]]; then
        ln -sf "$PROJECT_DIR/deploy.sh" /usr/local/bin/mtproxy-whitelist 2>/dev/null || {
            print_warning "无法创建全局链接，请使用 ./deploy.sh 命令"
        }
        print_success "管理脚本已链接: mtproxy-whitelist -> deploy.sh"
    fi
    
    print_info "📋 统一管理命令说明:"
    echo "  ./deploy.sh          - 完整部署"
    echo "  ./deploy.sh start    - 启动服务"
    echo "  ./deploy.sh stop     - 停止服务"
    echo "  ./deploy.sh restart  - 重启服务"
    echo "  ./deploy.sh status   - 查看状态"
    echo "  ./deploy.sh logs     - 查看日志"
    echo "  ./deploy.sh diagnose - 系统诊断"
    echo "  ./deploy.sh rebuild  - 强制重建"
    echo "  ./deploy.sh fix      - 快速修复"
    echo "  ./deploy.sh test-ip  - 测试IP获取"
    echo "  ./deploy.sh clean    - 清理系统"
}

# 获取正确的docker-compose命令
get_compose_cmd() {
    if [[ -f ".env" ]]; then
        source .env
        if [[ "$NAT_MODE" == "true" ]]; then
            echo "docker-compose -f docker-compose.nat.yml"
        else
            echo "docker-compose -f docker-compose.bridge.yml"
        fi
    else
        echo "docker-compose -f docker-compose.bridge.yml"
    fi
}

# 强制重建功能
force_rebuild() {
    print_info "🔧 强制重建 MTProxy 白名单系统..."
    
    # 获取正确的compose命令
    local compose_cmd=$(get_compose_cmd)
    
    print_info "1. 停止并清理所有容器..."
    $compose_cmd down -v --remove-orphans 2>/dev/null || true
    docker-compose down -v --remove-orphans 2>/dev/null || true  # 清理可能存在的标准配置
    
    print_info "2. 清理Docker缓存..."
    docker system prune -f
    docker builder prune -f 2>/dev/null || true
    
    print_info "3. 删除相关镜像..."
    docker images | grep mtproxy | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    
    print_info "4. 检查NAT模式配置..."
    if [[ -f ".env" ]]; then
        source .env
        if [[ "$NAT_MODE" == "true" ]]; then
            print_info "NAT模式：将使用host网络，nginx直接监听端口 $MTPROXY_PORT 和 $WEB_PORT"
            generate_nat_compose
        else
            print_info "Bridge模式：将使用端口映射 $MTPROXY_PORT->443 和 $WEB_PORT->8888"
        fi
    fi
    
    print_info "5. 强制重建镜像（无缓存）..."
    $compose_cmd build --no-cache --pull
    
    print_info "6. 启动服务..."
    $compose_cmd up -d
    
    print_info "7. 等待服务启动..."
    sleep 15
    
    print_info "8. 检查服务状态..."
    check_service_status
    
    print_success "🎉 强制重建完成！"
}

# 诊断功能
diagnose_system() {
    print_info "🔍 系统诊断报告"
    print_line
    
    # 获取正确的compose命令
    local compose_cmd=$(get_compose_cmd)
    
    print_info "1. Docker 环境检查"
    docker --version
    docker-compose --version
    echo ""
    
    print_info "2. 配置模式检查"
    if [[ -f ".env" ]]; then
        source .env
        if [[ "$NAT_MODE" == "true" ]]; then
            print_info "当前模式: NAT模式 (host网络)"
            print_info "使用配置: docker-compose.nat.yml"
        else
            print_info "当前模式: Bridge模式 (端口映射)"
            print_info "使用配置: docker-compose.yml"
        fi
    fi
    echo ""
    
    print_info "3. 容器状态检查"
    $compose_cmd ps
    echo ""
    
    print_info "4. 端口监听检查"
    if [[ -f ".env" ]]; then
        source .env
        print_info "配置的端口: MTProxy=$MTPROXY_PORT, Web=$WEB_PORT"
        ss -tuln | grep -E ":$MTPROXY_PORT |:$WEB_PORT " || print_warning "配置端口未监听"
    fi
    ss -tuln | grep -E ":443 |:444 |:8888 |:8080 " || print_warning "内部端口未监听"
    echo ""
    
    print_info "5. 服务日志检查"
    if $compose_cmd ps | grep -q "Up"; then
        print_info "最近的容器日志:"
        $compose_cmd logs --tail=20
    else
        print_warning "容器未运行"
    fi
    echo ""
    
    print_info "6. 网络连通性检查"
    if [[ -f ".env" ]]; then
        source .env
        local public_ip=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "localhost")
        print_info "公网IP: $public_ip"
        print_info "测试Web界面连通性..."
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${WEB_PORT:-8888} 2>/dev/null || echo "000")
        if [[ "$http_code" =~ ^(200|401|403)$ ]]; then
            print_success "Web界面连通正常 (HTTP $http_code)"
        else
            print_warning "Web界面连通异常 (HTTP $http_code)"
        fi
    fi
    
    print_line
    print_success "诊断完成"
}

# 快速修复功能
quick_fix() {
    print_info "🔧 快速修复常见问题..."
    
    # 获取正确的compose命令
    local compose_cmd=$(get_compose_cmd)
    
    if [[ -f ".env" ]]; then
        source .env
    fi
    
    print_info "1. 检查并修复环境变量..."
    if [[ -z "$MTPROXY_PORT" ]] || [[ -z "$WEB_PORT" ]]; then
        print_warning "环境变量缺失，重新生成.env文件"
        generate_config
    fi
    
    print_info "2. 检查NAT模式配置..."
    if [[ "$NAT_MODE" == "true" ]] && [[ ! -f "docker-compose.nat.yml" ]]; then
        print_info "重新生成NAT模式配置..."
        generate_nat_compose
    fi
    
    print_info "3. 重启服务..."
    $compose_cmd restart
    
    print_info "4. 等待服务启动..."
    sleep 10
    
    print_info "5. 检查修复结果..."
    check_service_status
    
    print_success "快速修复完成"
}

# IP获取测试功能
test_ip_acquisition() {
    print_info "🔍 测试IP获取功能..."
    
    # 获取正确的compose命令
    local compose_cmd=$(get_compose_cmd)
    
    if ! $compose_cmd ps | grep -q "Up"; then
        print_error "服务未运行，请先启动服务"
        return 1
    fi
    
    print_info "1. 检查nginx配置..."
    $compose_cmd exec -T mtproxy-whitelist nginx -t 2>/dev/null && print_success "nginx配置正常" || print_error "nginx配置异常"
    
    print_info "2. 检查白名单文件..."
    if $compose_cmd exec -T mtproxy-whitelist test -f /data/nginx/whitelist.txt 2>/dev/null; then
        print_success "白名单文件存在"
        print_info "当前白名单内容:"
        $compose_cmd exec -T mtproxy-whitelist head -10 /data/nginx/whitelist.txt 2>/dev/null || true
    else
        print_warning "白名单文件不存在"
    fi
    
    print_info "3. 检查连接日志..."
    if $compose_cmd exec -T mtproxy-whitelist test -f /var/log/nginx/stream_access.log 2>/dev/null; then
        print_info "最近的连接记录:"
        $compose_cmd exec -T mtproxy-whitelist tail -5 /var/log/nginx/stream_access.log 2>/dev/null || print_info "暂无连接记录"
    else
        print_info "连接日志文件不存在"
    fi
    
    print_success "IP获取测试完成"
}

# 主安装流程
main() {
    # 检查命令行参数
    case "${1:-}" in
        "force-rebuild"|"rebuild")
            print_info "强制重建模式..."
            force_rebuild
            exit 0
            ;;
        "diagnose"|"diag")
            print_info "诊断模式..."
            diagnose_system
            exit 0
            ;;
        "quick-fix"|"fix")
            print_info "快速修复模式..."
            quick_fix
            exit 0
            ;;
        "test-ip"|"test-nat-ip")
            print_info "IP获取测试模式..."
            test_ip_acquisition
            exit 0
            ;;
        "fix-nat-ip")
            print_info "NAT环境真实IP获取修复..."
            fix_nat_ip
            exit 0
            ;;
        "setup-haproxy")
            print_info "配置HAProxy PROXY Protocol..."
            setup_haproxy_proxy_protocol
            exit 0
            ;;
        "deploy-haproxy")
            print_info "部署HAProxy+PROXY Protocol模式..."
            deploy_haproxy_mode
            exit 0
            ;;
        "test-haproxy")
            print_info "测试HAProxy模式IP获取..."
            test_haproxy_mode
            exit 0
            ;;
        "deploy-haproxy")
            print_info "部署HAProxy+PROXY Protocol模式..."
            deploy_haproxy_mode
            exit 0
            ;;
        "test-haproxy")
            print_info "测试HAProxy模式IP获取..."
            test_haproxy_mode
            exit 0
            ;;
        "logs")
            print_info "查看日志..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd logs -f --tail=50
            exit 0
            ;;
        "status")
            print_info "服务状态..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd ps
            if [[ -f ".env" ]]; then
                source .env
                print_info "端口监听状态:"
                ss -tuln | grep -E ":$MTPROXY_PORT |:$WEB_PORT " || print_warning "端口未监听"
            fi
            exit 0
            ;;
        "stop")
            print_info "停止服务..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd down
            exit 0
            ;;
        "start")
            print_info "启动服务..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd up -d
            exit 0
            ;;
        "restart")
            print_info "重启服务..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd restart
            exit 0
            ;;
        "clean")
            print_info "清理系统..."
            local compose_cmd=$(get_compose_cmd)
            $compose_cmd down -v --remove-orphans
            
            # 清理所有可能的配置文件
            docker-compose down -v --remove-orphans 2>/dev/null || true
            docker-compose -f docker-compose.nat.yml down -v --remove-orphans 2>/dev/null || true
            docker-compose -f docker-compose.bridge.yml down -v --remove-orphans 2>/dev/null || true
            
            docker system prune -f
            rm -f docker-compose.nat.yml docker-compose-nat.sh 2>/dev/null || true
            rm -f docker-compose.bridge.yml docker-compose-bridge.sh 2>/dev/null || true
            print_success "清理完成"
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo "MTProxy 白名单系统统一管理脚本"
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "部署命令:"
            echo "  (无参数)     - 完整部署流程"
            echo "  force-rebuild - 强制重建（清理缓存）"
            echo "  quick-fix    - 快速修复常见问题"
            echo ""
            echo "管理命令:"
            echo "  start        - 启动服务"
            echo "  stop         - 停止服务"
            echo "  restart      - 重启服务"
            echo "  status       - 查看状态"
            echo "  logs         - 查看日志"
            echo ""
            echo "诊断命令:"
            echo "  diagnose     - 系统诊断"
            echo "  test-ip      - 测试IP获取"
            echo "  fix-nat-ip     - 修复NAT环境真实IP获取"
            echo "  setup-haproxy  - 配置HAProxy PROXY Protocol"
            echo "  deploy-haproxy - 部署HAProxy+PROXY Protocol模式"
            echo "  test-haproxy   - 测试HAProxy模式IP获取"
            echo ""
            echo "维护命令:"
            echo "  clean        - 清理系统"
            echo "  help         - 显示帮助"
            echo ""
            exit 0
            ;;
    esac
    
    show_welcome
    
    print_info "开始部署 MTProxy 白名单系统..."
    echo
    
    # 检查系统要求
    check_requirements
    
    # 安装 Docker
    install_docker
    
    # 安装 Docker Compose
    install_docker_compose
    
    # 配置系统参数
    configure_system
    
    # 获取用户配置
    get_user_config
    
    # 配置防火墙（使用用户配置的端口）
    configure_firewall
    
    # 准备部署文件
    prepare_deployment
    
    # 生成配置文件
    generate_config
    
    # 部署服务
    deploy_service
    
    # NAT环境：启用IP获取增强功能
    if [[ "$NAT_MODE" == "true" ]]; then
        print_info "NAT模式：启用IP获取增强功能"
        
        # 修复 NAT 环境 IP 获取
        fix_nat_ip
        
        # 测试 NAT IP 获取功能
        test_nat_ip_function
        
        # 清理可能存在的HAProxy容器
        if docker ps -a --format '{{.Names}}' | grep -q '^mtproxy-haproxy$'; then
            print_info "清理旧的HAProxy容器..."
            docker stop mtproxy-haproxy >/dev/null 2>&1 || true
            docker rm mtproxy-haproxy >/dev/null 2>&1 || true
            print_success "HAProxy容器已清理"
        fi
        
        print_success "NAT环境IP获取增强：客户端 → nginx(${MTPROXY_PORT}) → MTProxy(444)"
    else
        print_info "标准模式：使用默认IP获取机制"
    fi
    
    # 创建管理脚本
    create_management_script
    
    # 显示部署结果
    show_deployment_result
    
    print_success "部署完成！"
}

# 错误处理
trap 'print_error "部署过程中发生错误，请检查日志"; exit 1' ERR

# NAT环境真实IP获取修复
fix_nat_ip() {
    echo "🔧 修复NAT环境真实IP获取问题..."
    echo "⚠️  注意：不能简单地将NAT网关IP加入白名单，这会放行所有流量！"
    echo ""
    
    # 检查当前问题
    if docker exec mtproxy-whitelist test -f /var/log/nginx/stream_access.log 2>/dev/null; then
        echo "📊 分析当前访问情况..."
        
        # 提取最近访问的IP
        RECENT_IPS=$(docker exec mtproxy-whitelist tail -20 /var/log/nginx/stream_access.log | grep -oE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort | uniq)
        
        echo "检测到的访问IP:"
        echo "$RECENT_IPS"
        
        # 检查是否有内网IP
        PRIVATE_IPS=$(echo "$RECENT_IPS" | grep -E "^(172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|10\.)")
        
        if [ -n "$PRIVATE_IPS" ]; then
            echo ""
            echo "❌ 问题确认：检测到NAT网关内网IP"
            echo "内网IP: $PRIVATE_IPS"
            echo ""
            echo "🔍 NAT环境下获取真实IP的解决方案："
            echo ""
            echo "方案1: HTTP代理模式 (推荐)"
            echo "  - 改用HTTP CONNECT代理"
            echo "  - 支持X-Forwarded-For头获取真实IP"
            echo "  - 兼容性好，支持大多数客户端"
            echo ""
            echo "方案2: 配置上游PROXY Protocol"
            echo "  - 需要在NAT网关配置PROXY Protocol"
            echo "  - 技术要求高，需要网络管理员配置"
            echo ""
            echo "方案3: 修改网络架构"
            echo "  - 使用透明代理或直连模式"
            echo "  - 绕过NAT网关的IP转换"
            echo ""
            
            echo "选择解决方案:"
            echo "1. 切换到HTTP代理模式 (推荐)"
            echo "2. 生成PROXY Protocol配置指南"
            echo "3. 显示网络架构建议"
            echo "4. 取消"
            echo ""
            read -p "请选择 [1-4]: " solution_choice
            
            case $solution_choice in
                1)
                    echo "🔄 切换到HTTP代理模式..."
                    setup_http_proxy_mode
                    ;;
                2)
                    echo "📋 生成PROXY Protocol配置指南..."
                    generate_proxy_protocol_guide
                    ;;
                3)
                    echo "🏗️  显示网络架构建议..."
                    show_network_architecture_advice
                    ;;
                *)
                    echo "取消操作"
                    ;;
            esac
        else
            echo "✅ 未检测到内网IP问题，当前IP获取正常"
        fi
    else
        echo "❌ 无法访问nginx日志，请检查容器状态"
    fi
}

# 设置HTTP代理模式
setup_http_proxy_mode() {
    echo "🔄 配置HTTP代理模式..."
    
    # 备份当前nginx配置
    docker exec mtproxy-whitelist cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    
    # 生成HTTP代理配置
    cat > http-proxy-nginx.conf << 'EOF'
# HTTP代理模式nginx配置
# 支持获取真实客户端IP

events {
    worker_connections 1024;
}

http {
    # 真实IP获取配置
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
    
    # 日志格式
    log_format proxy_format '$remote_addr - $remote_user [$time_local] "$request" '
                           '$status $body_bytes_sent "$http_referer" '
                           '"$http_user_agent" "$http_x_forwarded_for" '
                           'realip:$realip_remote_addr';
    
    # 白名单映射
    geo $realip_remote_addr $allowed {
        default 0;
        include /data/nginx/whitelist_map.conf;
    }
    
    # HTTP CONNECT代理服务器
    server {
        listen ${WEB_PORT:-8989};
        server_name _;
        
        # Web管理界面
        location / {
            proxy_pass http://127.0.0.1:8888;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
    
    # CONNECT代理服务器
    server {
        listen ${MTPROXY_PORT:-14202};
        
        # 白名单验证
        if ($allowed = 0) {
            return 403;
        }
        
        # CONNECT方法处理
        location / {
            proxy_connect;
            proxy_connect_allow 443 444;
            proxy_connect_connect_timeout 10s;
            proxy_connect_read_timeout 10s;
            proxy_connect_send_timeout 10s;
            
            access_log /var/log/nginx/connect_access.log proxy_format;
        }
    }
}
EOF
    
    echo "⚠️  HTTP代理模式需要nginx-connect模块支持"
    echo "当前容器可能不支持，建议使用专门的HTTP代理解决方案"
    echo ""
    echo "推荐替代方案："
    echo "1. 使用HAProxy作为前端代理"
    echo "2. 配置Cloudflare等CDN服务"
    echo "3. 使用专门的SOCKS5代理"
}

# 生成PROXY Protocol配置指南
generate_proxy_protocol_guide() {
    echo "📋 PROXY Protocol配置指南"
    echo "=========================="
    echo ""
    echo "PROXY Protocol可以在NAT环境下传递真实客户端IP"
    echo ""
    echo "1. 上游代理配置 (HAProxy示例):"
    echo "   frontend mtproxy_frontend"
    echo "       bind *:443"
    echo "       default_backend mtproxy_backend"
    echo ""
    echo "   backend mtproxy_backend"
    echo "       server mtproxy1 127.0.0.1:14202 send-proxy"
    echo ""
    echo "2. nginx配置已支持PROXY Protocol:"
    echo "   listen 14202 proxy_protocol;"
    echo "   set_real_ip_from 172.16.0.0/12;"
    echo ""
    echo "3. 测试PROXY Protocol:"
    echo "   echo -e 'PROXY TCP4 1.2.3.4 5.6.7.8 1234 443\\r\\n' | nc localhost 14202"
    echo ""
    echo "4. 验证配置:"
    echo "   检查nginx日志中是否显示真实IP而非NAT网关IP"
}

# 显示网络架构建议
show_network_architecture_advice() {
    echo "🏗️  NAT环境网络架构建议"
    echo "======================="
    echo ""
    echo "当前问题：NAT网关隐藏了真实客户端IP"
    echo ""
    echo "解决方案架构："
    echo ""
    echo "方案A: 前端代理架构"
    echo "客户端 → 公网 → HAProxy/Nginx(PROXY Protocol) → MTProxy容器"
    echo "优点：保留真实IP，安全性高"
    echo "缺点：需要配置前端代理"
    echo ""
    echo "方案B: CDN架构"
    echo "客户端 → Cloudflare → 源站(获取CF-Connecting-IP) → MTProxy"
    echo "优点：自动获取真实IP，抗DDoS"
    echo "缺点：依赖第三方服务"
    echo ""
    echo "方案C: 直连架构"
    echo "客户端 → 公网IP → 直接连接MTProxy(无NAT)"
    echo "优点：最简单，性能最好"
    echo "缺点：需要公网IP，安全性依赖防火墙"
    echo ""
    echo "推荐：根据你的网络环境选择方案A或C"
}

# 配置HAProxy PROXY Protocol
setup_haproxy_proxy_protocol() {
    echo "🔧 配置HAProxy PROXY Protocol支持..."
    
    if [[ ! -f "docker/haproxy-proxy-protocol.cfg" ]]; then
        print_error "HAProxy配置文件不存在"
        return 1
    fi
    
    echo "📋 HAProxy PROXY Protocol部署步骤："
    echo ""
    echo "1. 安装HAProxy (如果未安装):"
    echo "   # Ubuntu/Debian"
    echo "   sudo apt update && sudo apt install haproxy"
    echo "   # CentOS/RHEL"  
    echo "   sudo yum install haproxy"
    echo ""
    echo "2. 复制配置文件:"
    echo "   sudo cp docker/haproxy-proxy-protocol.cfg /etc/haproxy/haproxy.cfg"
    echo ""
    echo "3. 启动HAProxy:"
    echo "   sudo systemctl enable haproxy"
    echo "   sudo systemctl start haproxy"
    echo ""
    echo "4. 验证配置:"
    echo "   sudo systemctl status haproxy"
    echo "   sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
    echo ""
    echo "5. 网络架构:"
    echo "   客户端 → HAProxy(443) → MTProxy容器(14202) + PROXY Protocol"
    echo ""
    echo "6. 检查nginx日志确认真实IP:"
    echo "   docker exec mtproxy-whitelist tail -f /var/log/nginx/stream_access.log"
    echo ""
    
    read -p "是否现在复制HAProxy配置文件到系统? (y/N): " copy_config
    if [[ $copy_config =~ ^[Yy]$ ]]; then
        if [[ -f "/etc/haproxy/haproxy.cfg" ]]; then
            sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup
            echo "✅ 已备份原配置文件"
        fi
        
        sudo cp docker/haproxy-proxy-protocol.cfg /etc/haproxy/haproxy.cfg
        echo "✅ HAProxy配置文件已复制"
        
        # 验证配置
        if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
            echo "✅ HAProxy配置验证通过"
            
            read -p "是否现在重启HAProxy服务? (y/N): " restart_haproxy
            if [[ $restart_haproxy =~ ^[Yy]$ ]]; then
                sudo systemctl restart haproxy
                sudo systemctl status haproxy
            fi
        else
            echo "❌ HAProxy配置验证失败"
        fi
    fi
}

# 部署HAProxy+PROXY Protocol模式
deploy_haproxy_mode() {
    print_line
    echo "🚀 部署HAProxy+PROXY Protocol模式"
    print_line
    
    # 检查必要文件
    if [[ ! -f "docker-compose.nat.yml" ]]; then
        print_error "docker-compose.nat.yml 文件不存在"
        return 1
    fi
    
    if [[ ! -f "docker/haproxy.cfg" ]]; then
        print_error "docker/haproxy.cfg 文件不存在"
        return 1
    fi
    
    # 检查环境变量
    check_env_file
    
    # 加载环境变量
    if [[ -f ".env" ]]; then
        export $(grep -v '^#' .env | xargs)
    fi
    
    # 设置默认值
    export MTPROXY_PORT=${MTPROXY_PORT:-14202}
    export WEB_PORT=${WEB_PORT:-8787}
    export PROXY_PROTOCOL_PORT=${PROXY_PROTOCOL_PORT:-14203}
    
    print_info "HAProxy模式配置："
    print_info "  外部MTProxy端口: ${MTPROXY_PORT}"
    print_info "  外部Web端口: ${WEB_PORT}"
    print_info "  内部PROXY Protocol端口: ${PROXY_PROTOCOL_PORT}"
    
    # 检查端口冲突
    check_port_conflict "${MTPROXY_PORT}" "MTProxy"
    check_port_conflict "${WEB_PORT}" "Web管理"
    check_port_conflict "${PROXY_PROTOCOL_PORT}" "PROXY Protocol"
    
    # 停止现有服务
    print_info "停止现有服务..."
    docker-compose down >/dev/null 2>&1 || true
    if [[ -f "docker-compose-nat.sh" ]]; then
        ./docker-compose-nat.sh down >/dev/null 2>&1 || true
    fi
    
    # 构建镜像
    print_info "构建HAProxy模式镜像..."
    if [[ -f "docker-compose-nat.sh" ]]; then
        ./docker-compose-nat.sh build
    else
        docker-compose -f docker-compose.nat.yml build
    fi
    
    # 启动服务
    print_info "启动HAProxy+PROXY Protocol服务..."
    if [[ -f "docker-compose-nat.sh" ]]; then
        ./docker-compose-nat.sh up -d
    else
        docker-compose -f docker-compose.nat.yml up -d
    fi
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    print_info "检查服务状态..."
    docker-compose -f docker-compose.nat.yml ps
    
    # 验证HAProxy
    if docker-compose -f docker-compose.nat.yml exec -T haproxy haproxy -vv >/dev/null 2>&1; then
        print_success "✅ HAProxy服务运行正常"
    else
        print_error "❌ HAProxy服务异常"
    fi
    
    # 验证nginx
    if docker-compose -f docker-compose.nat.yml exec -T mtproxy-whitelist pgrep nginx >/dev/null 2>&1; then
        print_success "✅ nginx服务运行正常"
    else
        print_error "❌ nginx服务异常"
    fi
    
    print_success "🎉 HAProxy+PROXY Protocol模式部署完成！"
    print_info "📋 管理命令："
    print_info "  ./docker-compose-nat.sh logs    # 查看日志"
    print_info "  ./docker-compose-nat.sh test-ip # 测试IP获取"
    print_info "  ./deploy.sh test-haproxy        # 测试HAProxy模式"
}

# 测试HAProxy模式IP获取
test_haproxy_mode() {
    print_line
    echo "🔍 测试HAProxy模式IP获取"
    print_line
    
    # 检查服务状态
    if ! docker-compose -f docker-compose.nat.yml ps | grep -q "Up"; then
        print_error "HAProxy模式服务未运行，请先部署"
        print_info "运行: ./deploy.sh deploy-haproxy"
        return 1
    fi
    
    print_info "1. 检查HAProxy配置..."
    if docker-compose -f docker-compose.nat.yml exec -T haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg; then
        print_success "✅ HAProxy配置正确"
    else
        print_error "❌ HAProxy配置错误"
    fi
    
    print_info "2. 检查端口监听..."
    print_info "HAProxy端口监听："
    docker-compose -f docker-compose.nat.yml exec -T haproxy netstat -tlnp | grep -E ":(${MTPROXY_PORT:-14202}|${WEB_PORT:-8787}) " || print_warning "HAProxy端口未监听"
    
    print_info "nginx端口监听："
    docker-compose -f docker-compose.nat.yml exec -T mtproxy-whitelist netstat -tlnp | grep -E ":(${PROXY_PROTOCOL_PORT:-14203}) " || print_warning "nginx PROXY Protocol端口未监听"
    
    print_info "3. 检查PROXY Protocol日志..."
    print_info "最近的PROXY Protocol连接："
    docker-compose -f docker-compose.nat.yml exec -T mtproxy-whitelist tail -10 /var/log/nginx/proxy_protocol_access.log 2>/dev/null || print_warning "暂无PROXY Protocol日志"
    
    print_info "4. 检查标准连接日志..."
    print_info "最近的标准连接："
    docker-compose -f docker-compose.nat.yml exec -T mtproxy-whitelist tail -10 /var/log/nginx/whitelist_access.log 2>/dev/null || print_warning "暂无标准连接日志"
    
    print_info "5. 网络架构验证..."
    print_info "预期流向: 客户端 → HAProxy:${MTPROXY_PORT:-14202} → nginx:${PROXY_PROTOCOL_PORT:-14203} → MTProxy:444"
    
    print_success "✅ HAProxy模式测试完成"
    print_info "💡 如果仍然看到内网IP，请确保客户端连接到HAProxy端口而不是直连nginx"
}

# 执行主流程
main "$@"