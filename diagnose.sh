#!/bin/bash

# MTProxy 白名单系统诊断脚本
# 用于排查 web 页面访问问题

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

# 获取配置
PROJECT_DIR="/opt/mtproxy-whitelist"
cd "$PROJECT_DIR" || {
    print_error "无法切换到项目目录: $PROJECT_DIR"
    exit 1
}

# 读取环境配置
if [[ -f ".env" ]]; then
    source .env
    WEB_PORT=${WEB_PORT:-8888}
    MTPROXY_PORT=${MTPROXY_PORT:-443}
else
    print_warning "未找到 .env 配置文件"
    WEB_PORT=8888
    MTPROXY_PORT=443
fi

print_line
echo -e "${PURPLE}MTProxy 白名单系统诊断工具${NC}"
print_line

print_info "配置信息："
echo "  项目目录: $PROJECT_DIR"
echo "  Web管理端口: $WEB_PORT"
echo "  MTProxy端口: $MTPROXY_PORT"
echo

# 1. 检查 Docker 容器状态
print_info "1. 检查 Docker 容器状态"
if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose ps | grep -q mtproxy-whitelist; then
        print_success "容器存在"
        docker-compose ps | grep mtproxy-whitelist
        
        if docker-compose ps | grep mtproxy-whitelist | grep -q "Up"; then
            print_success "容器运行中"
        else
            print_error "容器已停止"
            print_info "尝试启动容器..."
            docker-compose up -d
        fi
    else
        print_error "未找到容器"
    fi
else
    print_error "未安装 docker-compose"
fi
echo

# 2. 检查端口监听
print_info "2. 检查端口监听状态"
if command -v ss >/dev/null 2>&1; then
    echo "系统端口监听状态："
    ss -tuln | grep -E ":($WEB_PORT|$MTPROXY_PORT) "
    
    if ss -tuln | grep -q ":$WEB_PORT "; then
        print_success "Web管理端口 $WEB_PORT 正在监听"
    else
        print_warning "Web管理端口 $WEB_PORT 未监听"
    fi
    
    if ss -tuln | grep -q ":$MTPROXY_PORT "; then
        print_success "MTProxy端口 $MTPROXY_PORT 正在监听"
    else
        print_warning "MTProxy端口 $MTPROXY_PORT 未监听"
    fi
else
    print_warning "未找到 ss 命令，无法检查端口"
fi
echo

# 3. 检查服务状态
print_info "3. 检查容器内服务状态"
if docker-compose exec -T mtproxy-whitelist supervisorctl status 2>/dev/null; then
    print_success "成功获取服务状态"
else
    print_error "无法获取服务状态"
fi
echo

# 4. 测试 Web 连通性
print_info "4. 测试 Web 管理界面连通性"
for i in {1..3}; do
    print_info "尝试 $i/3: 测试 http://localhost:$WEB_PORT"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost:$WEB_PORT 2>/dev/null || echo "000")
    print_info "HTTP 响应码: $HTTP_CODE"
    
    case $HTTP_CODE in
        200)
            print_success "Web界面正常响应"
            break
            ;;
        000)
            print_error "连接失败 - 服务可能未启动"
            ;;
        502)
            print_error "网关错误 - API服务可能未启动"
            ;;
        404)
            print_warning "页面未找到 - 检查静态文件"
            ;;
        *)
            print_warning "未预期的响应码: $HTTP_CODE"
            ;;
    esac
    
    if [[ $i -lt 3 ]]; then
        print_info "等待 5 秒后重试..."
        sleep 5
    fi
done
echo

# 5. 检查日志
print_info "5. 检查关键日志"
print_info "Nginx 错误日志 (最后 5 行):"
docker-compose exec -T mtproxy-whitelist tail -n 5 /var/log/nginx/error.log 2>/dev/null || print_warning "无法读取nginx错误日志"
echo

print_info "Flask API 日志 (最后 5 行):"
docker-compose exec -T mtproxy-whitelist tail -n 5 /var/log/supervisor/mtproxy-api_stderr.log 2>/dev/null || print_warning "无法读取API错误日志"
echo

# 6. 检查配置文件
print_info "6. 检查配置文件"
print_info "Nginx 配置测试:"
docker-compose exec -T mtproxy-whitelist nginx -t 2>/dev/null && print_success "Nginx 配置正确" || print_error "Nginx 配置有误"

print_info "检查环境变量传递:"
docker-compose exec -T mtproxy-whitelist printenv | grep -E "(WEB_PORT|MTPROXY_PORT|FLASK_)" 2>/dev/null || print_warning "无法检查环境变量"
echo

# 6.5. 检查白名单映射文件同步
print_info "6.5. 检查白名单映射文件同步"
print_info "白名单文件状态:"
if docker-compose exec -T mtproxy-whitelist test -f /data/nginx/whitelist.txt 2>/dev/null; then
    print_success "whitelist.txt 存在"
    WHITELIST_ENTRIES=$(docker-compose exec -T mtproxy-whitelist grep -c -v "^#\|^$" /data/nginx/whitelist.txt 2>/dev/null || echo "0")
    print_info "白名单条目数: $WHITELIST_ENTRIES"
else
    print_error "whitelist.txt 不存在"
fi

print_info "映射文件状态:"
if docker-compose exec -T mtproxy-whitelist test -f /data/nginx/whitelist_map.conf 2>/dev/null; then
    print_success "whitelist_map.conf 存在"
    MAP_ENTRIES=$(docker-compose exec -T mtproxy-whitelist grep -c "1;" /data/nginx/whitelist_map.conf 2>/dev/null || echo "0")
    print_info "映射条目数: $MAP_ENTRIES"
    
    # 检查映射文件与白名单文件是否同步
    if [[ "$WHITELIST_ENTRIES" -eq "$MAP_ENTRIES" ]] || [[ $((MAP_ENTRIES - WHITELIST_ENTRIES)) -eq 2 ]]; then
        print_success "映射文件与白名单文件同步正常"
    else
        print_warning "映射文件可能与白名单文件不同步"
        print_info "建议运行: docker-compose exec mtproxy-whitelist /usr/local/bin/reload-whitelist.sh reload"
    fi
else
    print_error "whitelist_map.conf 不存在"
    print_info "建议运行: docker-compose exec mtproxy-whitelist /usr/local/bin/reload-whitelist.sh generate"
fi

print_info "重载脚本状态:"
if docker-compose exec -T mtproxy-whitelist test -x /usr/local/bin/reload-whitelist.sh 2>/dev/null; then
    print_success "重载脚本存在且可执行"
else
    print_error "重载脚本不存在或不可执行"
fi
echo

# 7. 网络测试
print_info "7. 网络连通性测试"
if command -v curl >/dev/null 2>&1; then
    # 测试静态文件
    print_info "测试静态文件访问:"
    curl -s -I http://localhost:$WEB_PORT/index.html | head -n 1
    
    # 测试API接口
    print_info "测试API接口:"
    curl -s -I http://localhost:$WEB_PORT/api/health 2>/dev/null | head -n 1 || print_warning "API健康检查失败"
else
    print_warning "未安装 curl，跳过网络测试"
fi
echo

# 总结和建议
print_line
print_info "诊断完成！常见解决方案："
echo "1. 如果容器未运行: docker-compose up -d"
echo "2. 如果端口冲突: 修改 .env 文件中的端口配置"
echo "3. 如果配置错误: docker-compose down && docker-compose build --no-cache && docker-compose up -d"
echo "4. 查看完整日志: docker-compose logs -f"
echo "5. 重置系统: docker-compose down -v && docker system prune -f"
print_line

# 快速修复选项
echo -n "是否尝试重启服务? (y/N): "
read -r restart_choice
if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
    print_info "重启服务..."
    docker-compose restart
    print_info "等待服务启动..."
    sleep 10
    print_info "重新测试连通性..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://localhost:$WEB_PORT 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|401|403)$ ]]; then
        print_success "重启后服务正常！访问地址: http://localhost:$WEB_PORT"
    else
        print_warning "重启后仍有问题，请查看日志: docker-compose logs -f"
    fi
fi