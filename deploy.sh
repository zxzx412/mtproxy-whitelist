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

# 部署服务
deploy_service() {
    print_info "开始部署 MTProxy 白名单系统..."
    
    # 构建镜像
    print_info "构建 Docker 镜像..."
    docker system prune -f
    docker-compose build --no-cache
    
    # 处理NAT模式配置冲突
    if [[ "$NAT_MODE" == "true" ]]; then
        print_info "NAT模式：处理host网络模式配置..."
        # 备份原配置
        if [[ ! -f "docker-compose.yml.backup" ]]; then
            cp docker-compose.yml docker-compose.yml.backup
        fi
        # 移除端口映射配置（host网络模式不兼容）
        sed '/# 端口映射 - 仅在bridge模式下使用/,/- "${WEB_PORT:-8888}:${WEB_PORT:-8888}"/d' docker-compose.yml.backup > docker-compose.yml
        print_info "已移除端口映射配置，使用host网络直接绑定"
    fi
    
    # 启动服务
    print_info "启动服务容器..."
    docker-compose up -d
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 10
    
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
    
    echo -e "${BLUE}🔧 常用命令${NC}"
    echo "查看服务状态: docker-compose ps"
    echo "查看服务日志: docker-compose logs -f"
    echo "重启服务: docker-compose restart"
    echo "停止服务: docker-compose down"
    echo "更新服务: docker-compose pull && docker-compose up -d"
    echo "系统诊断: bash diagnose.sh (排查访问问题)"
    echo "管理工具: mtproxy-whitelist status"
    echo "重新构建: docker-compose build --no-cache && docker-compose up -d"
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
    
    # 备份 nginx 配置
    docker-compose exec -T mtproxy-whitelist sh -c "
        if [ ! -f /etc/nginx/nginx.conf.backup ]; then
            cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
        fi
    " 2>/dev/null || true
    
    # 更新 nginx 配置支持 PROXY Protocol
    docker-compose exec -T mtproxy-whitelist sh -c "
        # 更新 stream 配置支持 proxy_protocol
        sed -i '/listen.*443/s/listen.*443.*/listen 443 proxy_protocol;/' /etc/nginx/nginx.conf
        
        # 添加 realip 配置
        if ! grep -q 'real_ip_header proxy_protocol' /etc/nginx/nginx.conf; then
            sed -i '/stream {/a\\    real_ip_header proxy_protocol;' /etc/nginx/nginx.conf
        fi
        
        # 更新日志格式使用真实 IP
        sed -i 's/\$remote_addr/\$proxy_protocol_addr/g' /etc/nginx/nginx.conf
        
        # 更新 geo 配置使用真实 IP
        sed -i 's/geo \$remote_addr/geo \$proxy_protocol_addr/g' /etc/nginx/nginx.conf
    " 2>/dev/null
    
    # 测试配置
    if docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null; then
        docker-compose exec -T mtproxy-whitelist nginx -s reload 2>/dev/null
        print_success "PROXY Protocol 配置完成"
    else
        print_error "nginx 配置测试失败，恢复备份"
        docker-compose exec -T mtproxy-whitelist sh -c "
            if [ -f /etc/nginx/nginx.conf.backup ]; then
                cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
                nginx -s reload
            fi
        " 2>/dev/null || true
        return 1
    fi
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

# 配置PROXY Protocol支持（NAT环境自动启用）
setup_proxy_protocol() {
    print_info "NAT环境检测：配置PROXY Protocol支持..."
    
    # 等待容器完全启动
    sleep 10
    
    print_info "备份nginx配置..."
    docker-compose exec -T mtproxy-whitelist sh -c "
        if [ ! -f /etc/nginx/nginx.conf.backup ]; then
            cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
        fi
    " 2>/dev/null || true
    
    print_info "更新nginx配置支持PROXY protocol..."
    docker-compose exec -T mtproxy-whitelist sh -c "
        # 更新stream server配置
        sed -i '/listen 443;/c\\        listen 443 proxy_protocol;' /etc/nginx/nginx.conf
        sed -i '/listen \${MTPROXY_PORT};/c\\        listen \${MTPROXY_PORT} proxy_protocol;' /etc/nginx/nginx.conf
        
        # 更新日志格式使用proxy_protocol_addr
        sed -i 's/\$remote_addr/\$proxy_protocol_addr/g' /etc/nginx/nginx.conf
        
        # 更新geo配置使用proxy_protocol_addr
        sed -i 's/geo \$remote_addr/geo \$proxy_protocol_addr/g' /etc/nginx/nginx.conf
    " 2>/dev/null
    
    # 测试配置
    if docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null; then
        docker-compose exec -T mtproxy-whitelist nginx -s reload 2>/dev/null
        print_success "PROXY Protocol配置完成"
    else
        print_error "nginx配置测试失败，恢复备份"
        docker-compose exec -T mtproxy-whitelist sh -c "
            cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
            nginx -s reload
        " 2>/dev/null || true
        return 1
    fi
    
    # 创建HAProxy配置
    print_info "生成HAProxy前端代理配置..."
    cat > haproxy.cfg << EOF
# MTProxy HAProxy前端代理配置
# NAT环境下获取真实客户端IP

global
    daemon
    log stdout local0 info
    maxconn 4096

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    retries 3
    timeout connect 5s
    timeout client 300s
    timeout server 300s

# MTProxy前端
frontend mtproxy_frontend
    bind *:$MTPROXY_PORT
    default_backend mtproxy_backend

# MTProxy后端 - PROXY protocol
backend mtproxy_backend
    server nginx 127.0.0.1:443 send-proxy-v2 check maxconn 1000
EOF
    
    # 创建HAProxy启动脚本
    cat > start-haproxy.sh << 'EOF'
#!/bin/bash
echo "🚀 启动HAProxy前端代理..."

# 停止可能存在的HAProxy容器
docker stop mtproxy-haproxy 2>/dev/null || true
docker rm mtproxy-haproxy 2>/dev/null || true

# 启动HAProxy容器
docker run -d \
    --name mtproxy-haproxy \
    --network host \
    -v "$(pwd)/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
    --restart unless-stopped \
    haproxy:2.8

echo "✅ HAProxy已启动"
echo "📊 查看状态: docker logs mtproxy-haproxy"
EOF
    
    chmod +x start-haproxy.sh
    
    print_info "启动HAProxy前端代理..."
    ./start-haproxy.sh >/dev/null 2>&1 || {
        print_warning "HAProxy自动启动失败，请手动运行: ./start-haproxy.sh"
    }
    
    print_success "NAT环境PROXY Protocol配置完成"
}


# 创建管理脚本
create_management_script() {
    print_info "创建管理脚本..."
    
    cat > /usr/local/bin/mtproxy-whitelist << EOF
#!/bin/bash

# MTProxy 白名单系统管理脚本 (自定义端口版)

# 查找项目目录
if [[ -f "/opt/mtproxy-whitelist/docker-compose.yml" ]]; then
    PROJECT_DIR="/opt/mtproxy-whitelist"
elif [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
    PROJECT_DIR="$PROJECT_DIR"
else
    echo "错误: 找不到 docker-compose.yml 文件"
    echo "请在项目根目录运行此命令"
    exit 1
fi

cd "\$PROJECT_DIR" || exit 1

case "\$1" in
    start)
        echo "启动 MTProxy 白名单系统..."
        docker-compose up -d
        ;;
    stop)
        echo "停止 MTProxy 白名单系统..."
        docker-compose down
        ;;
    restart)
        echo "重启 MTProxy 白名单系统..."
        docker-compose restart
        ;;
    status)
        echo "MTProxy 白名单系统状态:"
        docker-compose ps
        echo ""
        echo "端口监听状态:"
        ss -tuln | grep -E "(:$MTPROXY_PORT |:$WEB_PORT )"
        ;;
    logs)
        echo "查看 MTProxy 白名单系统日志:"
        docker-compose logs -f --tail=100
        ;;
    update)
        echo "更新 MTProxy 白名单系统..."
        docker-compose pull
        docker-compose up -d
        ;;
    info)
        echo "MTProxy 白名单系统信息:"
        PUBLIC_IP=\$(curl -s --connect-timeout 10 https://api.ip.sb/ip 2>/dev/null || echo "YOUR_SERVER_IP")
        echo "Web 管理界面: http://\$PUBLIC_IP:$WEB_PORT"
        echo "代理端口: $MTPROXY_PORT"
        echo "管理端口: $WEB_PORT"
        ;;
    ports)
        echo "端口配置信息:"
        echo "MTProxy 代理端口: $MTPROXY_PORT"
        echo "Web 管理端口: $WEB_PORT"
        echo ""
        echo "防火墙规则:"
        echo "  sudo ufw allow $MTPROXY_PORT/tcp"
        echo "  sudo ufw allow $WEB_PORT/tcp"
        ;;
    test-nat-ip)
        echo "测试 NAT IP 获取功能..."
        bash "\$PROJECT_DIR/deploy.sh" test-nat-ip
        ;;
    fix-nat-ip)
        echo "修复 NAT IP 获取..."
        bash "\$PROJECT_DIR/deploy.sh" fix-nat-ip
        ;;
    diagnose-ip)
        echo "运行 IP 获取诊断..."
        bash "\$PROJECT_DIR/deploy.sh" diagnose-ip
        ;;
    monitor-ips)
        echo "实时监控客户端 IP..."
        docker-compose exec mtproxy-whitelist /usr/local/bin/monitor-client-ips.sh 2>/dev/null || echo "监控脚本不可用"
        ;;
    ip-stats)
        echo "客户端 IP 统计..."
        docker-compose exec mtproxy-whitelist /usr/local/bin/ip-stats.sh 2>/dev/null || echo "统计脚本不可用"
        ;;
    *)
        echo "用法: \$0 {start|stop|restart|status|logs|update|info|ports|test-nat-ip|fix-nat-ip|diagnose-ip|monitor-ips|ip-stats}"
        echo ""
        echo "基础命令:"
        echo "  start   - 启动服务"
        echo "  stop    - 停止服务"
        echo "  restart - 重启服务"
        echo "  status  - 查看状态"
        echo "  logs    - 查看日志"
        echo "  update  - 更新服务"
        echo "  info    - 显示访问信息"
        echo "  ports   - 显示端口配置"
        echo ""
        echo "NAT IP 获取增强:"
        echo "  test-nat-ip  - 测试 NAT IP 获取功能"
        echo "  fix-nat-ip   - 修复 NAT IP 获取问题"
        echo "  diagnose-ip  - 运行 IP 获取诊断"
        echo "  monitor-ips  - 实时监控客户端 IP"
        echo "  ip-stats     - 查看客户端 IP 统计"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/mtproxy-whitelist
    
    print_success "管理脚本创建完成: mtproxy-whitelist"
}

# 主安装流程
main() {
    # 检查命令行参数
    case "${1:-}" in
        "test-nat-ip")
            print_info "测试 NAT IP 获取功能..."
            if [[ -f ".env" ]]; then
                source .env
            fi
            test_nat_ip_function
            exit 0
            ;;
        "fix-nat-ip")
            print_info "修复 NAT IP 获取..."
            if [[ -f ".env" ]]; then
                source .env
            fi
            fix_nat_ip
            exit 0
            ;;
        "enable-proxy-protocol")
            print_info "启用 PROXY Protocol..."
            enable_proxy_protocol
            exit 0
            ;;
        "diagnose-ip")
            print_info "运行 IP 获取诊断..."
            if docker-compose ps | grep -q "Up"; then
                docker-compose exec mtproxy-whitelist /usr/local/bin/diagnose-ip.sh 2>/dev/null || {
                    print_error "诊断脚本执行失败，请确保服务正在运行"
                }
            else
                print_error "服务未运行，请先启动服务"
            fi
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo "MTProxy 白名单系统部署脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  (无参数)              - 完整部署流程"
            echo "  test-nat-ip          - 测试 NAT IP 获取功能"
            echo "  fix-nat-ip           - 修复 NAT IP 获取问题"
            echo "  enable-proxy-protocol - 启用 PROXY Protocol"
            echo "  diagnose-ip          - 运行 IP 获取诊断"
            echo "  help, -h, --help     - 显示此帮助信息"
            echo ""
            echo "NAT 环境增强功能:"
            echo "  • PROXY Protocol 支持"
            echo "  • 多层 IP 获取回退机制"
            echo "  • 智能白名单管理"
            echo "  • 实时监控和诊断"
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

# 执行主流程
main "$@"