#!/bin/bash

# MTProxy 白名单系统 - 容器内 NAT 白名单修复脚本
# 专门处理容器环境下的白名单配置和 IP 获取优化

set -e

# 配置路径
WHITELIST_FILE="/data/nginx/whitelist.txt"
MAP_FILE="/data/nginx/whitelist_map.conf"
NGINX_CONF="/etc/nginx/nginx.conf"
LOG_FILE="/var/log/nginx/stream_access.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] NAT-WHITELIST: $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

# 检测容器网络环境
detect_container_network() {
    log "检测容器网络环境..."
    
    local network_info=""
    
    # 检测网络接口
    local interfaces
    interfaces=$(ip addr show | grep -E "inet.*scope global" | awk '{print $2}' | cut -d'/' -f1)
    
    # 检测默认网关
    local gateway
    gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    # 检测是否为 Docker 网络
    local is_docker_network=false
    if [[ "$gateway" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ "$gateway" =~ ^10\. ]]; then
        is_docker_network=true
    fi
    
    log "网络接口: $interfaces"
    log "默认网关: $gateway"
    log "Docker 网络: $is_docker_network"
    
    echo "$interfaces|$gateway|$is_docker_network"
}

# 获取真实的客户端 IP 范围
get_real_client_networks() {
    log "分析真实客户端网络范围..."
    
    local client_networks=()
    
    # 从日志中分析客户端 IP 模式
    if [[ -f "$LOG_FILE" ]]; then
        log "分析现有连接日志..."
        
        # 提取所有客户端 IP
        local ips
        ips=$(awk '{print $1}' "$LOG_FILE" 2>/dev/null | sort | uniq)
        
        for ip in $ips; do
            # 跳过内网和回环地址
            if [[ ! "$ip" =~ ^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
                # 这是外网 IP，分析其网段
                local network
                network=$(echo "$ip" | cut -d'.' -f1-3).0/24
                client_networks+=("$network")
            fi
        done
    fi
    
    # 添加常见的公网 IP 范围（用于测试）
    if [[ ${#client_networks[@]} -eq 0 ]]; then
        log "未发现历史连接，添加默认公网范围..."
        client_networks+=(
            "0.0.0.0/0"  # 允许所有 IP（需要手动配置具体白名单）
        )
    fi
    
    printf '%s\n' "${client_networks[@]}" | sort | uniq
}

# 创建智能白名单配置
create_smart_whitelist() {
    log "创建智能白名单配置..."
    
    # 确保目录存在
    mkdir -p "$(dirname "$WHITELIST_FILE")"
    mkdir -p "$(dirname "$MAP_FILE")"
    
    # 检测网络环境
    local network_info
    network_info=$(detect_container_network)
    local gateway
    gateway=$(echo "$network_info" | cut -d'|' -f2)
    
    # 创建基础白名单
    cat > "$WHITELIST_FILE" << EOF
# MTProxy 白名单配置 - NAT 环境优化版本
# 自动生成时间: $(date)
# 网络环境: 容器网络，网关 $gateway

# === 基础配置 ===
# 本地回环地址
127.0.0.1
::1

# 容器网络地址
$gateway

# === Docker 网络范围 ===
# Docker 默认网络范围（用于内部通信）
172.17.0.0/16
172.18.0.0/16
172.19.0.0/16
172.20.0.0/16

# === 客户端 IP 配置区域 ===
# 请在下方添加允许访问的客户端 IP 地址
# 支持单个 IP 和 CIDR 网段格式
# 示例:
# 192.168.1.100        # 单个 IP
# 192.168.1.0/24       # 整个网段
# 10.0.0.0/8           # 大网段

EOF

    # 添加检测到的客户端网络
    local client_networks
    client_networks=$(get_real_client_networks)
    
    if [[ -n "$client_networks" ]]; then
        echo "# === 检测到的客户端网络 ===" >> "$WHITELIST_FILE"
        echo "$client_networks" >> "$WHITELIST_FILE"
    fi
    
    log "智能白名单配置已创建: $WHITELIST_FILE"
}

# 生成优化的 nginx 映射配置
generate_optimized_map() {
    log "生成优化的 nginx 映射配置..."
    
    # 创建临时文件
    local tmp_map
    tmp_map=$(mktemp)
    
    # 生成文件头
    cat > "$tmp_map" << EOF
# MTProxy 白名单映射文件 - NAT 环境优化版本
# 自动生成时间: $(date)
# 此文件支持 PROXY Protocol 和真实 IP 获取

# === 默认配置 ===
default 0;

# === 本地和容器网络 ===
127.0.0.1 1;
::1 1;
EOF

    # 处理白名单文件
    local ip_count=0
    if [[ -f "$WHITELIST_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过空行和注释
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                local ip
                ip=$(echo "$line" | xargs)  # 去除前后空格
                
                if [[ -n "$ip" ]]; then
                    # 验证 IP 格式
                    if [[ "$ip" =~ ^[0-9a-fA-F.:\/]+$ ]]; then
                        echo "$ip 1;" >> "$tmp_map"
                        ip_count=$((ip_count + 1))
                    else
                        warning "跳过无效 IP 格式: $ip"
                    fi
                fi
            fi
        done < "$WHITELIST_FILE"
    fi
    
    # 原子性写入
    if mv "$tmp_map" "$MAP_FILE"; then
        chmod 644 "$MAP_FILE"
        log "映射文件生成成功: $MAP_FILE (共 $ip_count 条规则)"
    else
        error "无法写入映射文件: $MAP_FILE"
        rm -f "$tmp_map"
        return 1
    fi
}

# 优化 nginx 配置以支持 NAT 环境
optimize_nginx_for_nat() {
    log "优化 nginx 配置以支持 NAT 环境..."
    
    # 备份原始配置
    if [[ -f "$NGINX_CONF" ]]; then
        cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 检查是否已经优化过
    if grep -q "# NAT-OPTIMIZED" "$NGINX_CONF" 2>/dev/null; then
        log "nginx 配置已经过 NAT 优化"
        return 0
    fi
    
    # 创建 NAT 优化的配置
    cat > "$NGINX_CONF" << 'EOF'
# NAT-OPTIMIZED nginx 配置
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;
load_module /usr/lib/nginx/modules/ngx_stream_module.so;

events { 
    worker_connections 1024; 
    use epoll;
    multi_accept on;
}

# HTTP 服务器 - Web 管理界面
http {
    include /etc/nginx/mime.types;
    
    # 真实 IP 获取配置 - HTTP 模块完整支持
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
    
    # 信任的代理 IP 范围（扩展 Docker 网络）
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 192.168.0.0/16;
    set_real_ip_from 127.0.0.1;
    
    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    
    server {
        listen 0.0.0.0:8888;
        root /usr/share/nginx/html;
        index index.html;
        
        # 真实 IP 传递
        location /api/ { 
            proxy_pass http://127.0.0.1:8080; 
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # NAT 环境特殊头部
            proxy_set_header X-Original-IP $remote_addr;
            proxy_set_header X-Container-IP $server_addr;
        }
        
        location /health { 
            return 200 "OK"; 
        }
        
        # IP 检测和诊断接口
        location /api/ip-info {
            add_header Content-Type application/json;
            return 200 '{"remote_addr":"$remote_addr","real_ip":"$realip_remote_addr","forwarded_for":"$http_x_forwarded_for","server_addr":"$server_addr"}';
        }
        
        location /reload-whitelist {
            proxy_pass http://127.0.0.1:8080/api/reload;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}

# Stream 服务器 - MTProxy 白名单代理 (NAT 优化)
stream {
    # 日志格式 - NAT 环境增强版
    log_format nat_enhanced '$remote_addr|proxy:$proxy_protocol_addr|server:$server_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time whitelist:$allowed upstream:$upstream_addr';
    log_format nat_debug '$remote_addr|proxy:$proxy_protocol_addr|realip:$realip_remote_addr [$time_local] $protocol $status whitelist:$allowed connection:$connection';
    
    access_log /var/log/nginx/stream_access.log nat_enhanced;
    error_log /var/log/nginx/stream_error.log info;

    # 真实 IP 获取策略 - 多层回退机制
    map $proxy_protocol_addr $detected_real_ip {
        default $remote_addr;
        ~^.+$ $proxy_protocol_addr;
    }
    
    # 进一步处理，支持 X-Forwarded-For 类似的逻辑
    map $detected_real_ip $final_client_ip {
        default $detected_real_ip;
        ~^(172\.(1[6-9]|2[0-9]|3[01])\.|10\.|192\.168\.) $remote_addr;
    }

    # 白名单映射 - 使用最终确定的客户端 IP
    geo $final_client_ip $allowed {
        default 0;
        include /data/nginx/whitelist_map.conf;
    }

    # 后端服务器组定义
    map $allowed $backend_pool {
        default reject_backend;
        1 mtproxy_backend;
    }

    upstream mtproxy_backend {
        server 127.0.0.1:444 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    upstream reject_backend {
        server 127.0.0.1:9999;
    }

    # 主要代理服务器 - 支持 PROXY Protocol
    server {
        listen 0.0.0.0:443 proxy_protocol;
        proxy_pass $backend_pool;
        proxy_timeout 10s;
        proxy_connect_timeout 3s;
        proxy_responses 1;
        
        # 启用连接复用
        proxy_socket_keepalive on;
        
        access_log /var/log/nginx/whitelist_access.log nat_enhanced;
    }
    
    # 备用服务器 - 不使用 PROXY Protocol（兼容性）
    server {
        listen 0.0.0.0:444;
        proxy_pass $backend_pool;
        proxy_timeout 10s;
        proxy_connect_timeout 3s;
        proxy_responses 1;
        
        access_log /var/log/nginx/whitelist_fallback.log nat_enhanced;
    }
}
EOF

    log "nginx 配置已优化为 NAT 环境"
}

# 创建 NAT 环境监控工具
create_nat_monitoring_tools() {
    log "创建 NAT 环境监控工具..."
    
    # 创建实时 IP 分析工具
    cat > /usr/local/bin/analyze-nat-ips.sh << 'EOF'
#!/bin/bash

echo "=== MTProxy NAT 环境 IP 分析 ==="
echo "分析时间: $(date)"
echo

# 分析容器网络环境
echo "1. 容器网络环境:"
echo "   本机 IP: $(hostname -I | awk '{print $1}')"
echo "   网关 IP: $(ip route | grep default | awk '{print $3}')"
echo "   DNS 服务器: $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | head -1)"

echo
echo "2. 最近连接分析 (最后20条):"
if [[ -f /var/log/nginx/stream_access.log ]]; then
    tail -20 /var/log/nginx/stream_access.log | while read line; do
        remote_ip=$(echo "$line" | awk -F'|' '{print $1}')
        proxy_ip=$(echo "$line" | awk -F'|' '{print $2}' | cut -d':' -f2)
        server_ip=$(echo "$line" | awk -F'|' '{print $3}' | cut -d':' -f2)
        whitelist=$(echo "$line" | grep -o 'whitelist:[01]' | cut -d':' -f2)
        
        if [[ "$proxy_ip" != "" && "$proxy_ip" != "$remote_ip" ]]; then
            echo "   真实IP: $proxy_ip (代理: $remote_ip) -> 服务器: $server_ip [白名单: $whitelist]"
        else
            echo "   直连IP: $remote_ip -> 服务器: $server_ip [白名单: $whitelist]"
        fi
    done
else
    echo "   无日志文件"
fi

echo
echo "3. IP 类型统计:"
if [[ -f /var/log/nginx/stream_access.log ]]; then
    echo "   总连接数: $(wc -l < /var/log/nginx/stream_access.log)"
    echo "   PROXY Protocol 连接: $(grep -c 'proxy:' /var/log/nginx/stream_access.log)"
    echo "   白名单通过: $(grep -c 'whitelist:1' /var/log/nginx/stream_access.log)"
    echo "   白名单拒绝: $(grep -c 'whitelist:0' /var/log/nginx/stream_access.log)"
fi

echo
echo "4. 当前白名单配置:"
if [[ -f /data/nginx/whitelist_map.conf ]]; then
    echo "   白名单规则数: $(grep -c ' 1;' /data/nginx/whitelist_map.conf)"
    echo "   最近更新: $(stat -c %y /data/nginx/whitelist_map.conf)"
else
    echo "   白名单文件不存在"
fi

echo
echo "=== 分析完成 ==="
EOF

    chmod +x /usr/local/bin/analyze-nat-ips.sh
    
    # 创建白名单优化建议工具
    cat > /usr/local/bin/whitelist-suggestions.sh << 'EOF'
#!/bin/bash

echo "=== MTProxy 白名单优化建议 ==="
echo

# 分析被拒绝的 IP
echo "1. 最近被拒绝的 IP (可能需要添加到白名单):"
if [[ -f /var/log/nginx/stream_access.log ]]; then
    grep 'whitelist:0' /var/log/nginx/stream_access.log | \
    awk -F'|' '{print $1}' | sort | uniq -c | sort -nr | head -10 | \
    while read count ip; do
        echo "   $ip (尝试 $count 次)"
    done
else
    echo "   无日志数据"
fi

echo
echo "2. 建议添加的网段:"
if [[ -f /var/log/nginx/stream_access.log ]]; then
    grep 'whitelist:0' /var/log/nginx/stream_access.log | \
    awk -F'|' '{print $1}' | \
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | \
    awk -F'.' '{print $1"."$2"."$3".0/24"}' | \
    sort | uniq -c | sort -nr | head -5 | \
    while read count network; do
        echo "   $network (包含 $count 个被拒绝的 IP)"
    done
fi

echo
echo "3. 当前配置状态:"
echo "   配置文件: /data/nginx/whitelist.txt"
echo "   映射文件: /data/nginx/whitelist_map.conf"
echo "   nginx 配置: /etc/nginx/nginx.conf"

echo
echo "4. 推荐操作:"
echo "   - 通过 Web 界面添加常用 IP: http://服务器IP:8888"
echo "   - 运行诊断: diagnose-ip.sh"
echo "   - 实时监控: monitor-client-ips.sh"
echo "   - 重载配置: /usr/local/bin/reload-whitelist.sh"

echo
echo "=== 建议完成 ==="
EOF

    chmod +x /usr/local/bin/whitelist-suggestions.sh
    
    log "NAT 环境监控工具创建完成"
}

# 测试 NAT 白名单配置
test_nat_whitelist() {
    log "测试 NAT 白名单配置..."
    
    local test_results=()
    
    # 测试文件存在性
    if [[ -f "$WHITELIST_FILE" ]]; then
        test_results+=("✓ 白名单文件存在")
    else
        test_results+=("✗ 白名单文件不存在")
    fi
    
    if [[ -f "$MAP_FILE" ]]; then
        test_results+=("✓ 映射文件存在")
    else
        test_results+=("✗ 映射文件不存在")
    fi
    
    # 测试 nginx 配置
    if nginx -t >/dev/null 2>&1; then
        test_results+=("✓ nginx 配置有效")
    else
        test_results+=("✗ nginx 配置无效")
    fi
    
    # 测试网络连通性
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        test_results+=("✓ 外网连通性正常")
    else
        test_results+=("✗ 外网连通性异常")
    fi
    
    # 显示测试结果
    echo
    echo "=== NAT 白名单配置测试结果 ==="
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    echo "================================="
    echo
    
    # 统计白名单规则
    if [[ -f "$MAP_FILE" ]]; then
        local rule_count
        rule_count=$(grep -c ' 1;' "$MAP_FILE" 2>/dev/null || echo "0")
        log "当前白名单规则数: $rule_count"
    fi
}

# 修复 NAT 白名单问题
fix_nat_whitelist_issues() {
    log "修复 NAT 白名单问题..."
    
    # 创建必要的目录
    mkdir -p /data/nginx /var/log/nginx
    
    # 修复文件权限
    if [[ -f "$WHITELIST_FILE" ]]; then
        chmod 644 "$WHITELIST_FILE"
    fi
    
    if [[ -f "$MAP_FILE" ]]; then
        chmod 644 "$MAP_FILE"
    fi
    
    # 确保 nginx 用户可以访问文件
    chown -R nginx:nginx /data/nginx /var/log/nginx 2>/dev/null || true
    
    # 重新生成配置
    create_smart_whitelist
    generate_optimized_map
    
    # 测试并重载 nginx
    if nginx -t; then
        if pgrep nginx >/dev/null; then
            nginx -s reload
            log "nginx 配置已重载"
        else
            log "nginx 未运行，跳过重载"
        fi
    else
        error "nginx 配置测试失败"
        return 1
    fi
    
    log "NAT 白名单问题修复完成"
}

# 显示使用说明
show_usage() {
    cat << EOF
MTProxy 容器内 NAT 白名单修复脚本

用法: $0 [选项]

选项:
    fix         修复 NAT 白名单问题 (默认)
    create      创建智能白名单配置
    optimize    优化 nginx 配置
    test        测试当前配置
    monitor     创建监控工具
    analyze     分析当前 IP 连接状态
    suggest     显示白名单优化建议
    help        显示此帮助

文件路径:
    白名单文件: $WHITELIST_FILE
    映射文件:   $MAP_FILE
    nginx 配置: $NGINX_CONF

示例:
    $0 fix                      # 修复所有 NAT 白名单问题
    $0 create                   # 重新创建智能白名单
    $0 test                     # 测试当前配置
    $0 analyze                  # 分析 IP 连接状态

注意:
    - 此脚本在容器内运行
    - 需要适当的文件权限
    - 建议配合主机端的 fix-nat-ip.sh 使用
EOF
}

# 主函数
main() {
    case "${1:-fix}" in
        "fix")
            fix_nat_whitelist_issues
            create_nat_monitoring_tools
            test_nat_whitelist
            ;;
        "create")
            create_smart_whitelist
            generate_optimized_map
            ;;
        "optimize")
            optimize_nginx_for_nat
            ;;
        "test")
            test_nat_whitelist
            ;;
        "monitor")
            create_nat_monitoring_tools
            ;;
        "analyze")
            if [[ -f /usr/local/bin/analyze-nat-ips.sh ]]; then
                /usr/local/bin/analyze-nat-ips.sh
            else
                error "分析工具不存在，请先运行 'fix' 或 'monitor' 命令"
            fi
            ;;
        "suggest")
            if [[ -f /usr/local/bin/whitelist-suggestions.sh ]]; then
                /usr/local/bin/whitelist-suggestions.sh
            else
                error "建议工具不存在，请先运行 'fix' 或 'monitor' 命令"
            fi
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
}

# 只有直接执行时才运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi