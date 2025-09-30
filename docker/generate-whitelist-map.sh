#!/bin/bash

# 统一的白名单映射文件生成脚本
# 由entrypoint.sh和reload-whitelist.sh共同使用，避免代码重复

# 使用较温和的错误处理，避免容器崩溃
set -e

# 默认路径配置
WHITELIST_FILE="${WHITELIST_FILE:-/data/nginx/whitelist.txt}"
MAP_FILE="${MAP_FILE:-/data/nginx/whitelist_map.conf}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] generate-whitelist-map: $1"
}

# 简化的IP验证逻辑（避免复杂正则导致死循环）
validate_ip() {
    local ip="$1"  # 必须接收参数
    
    # IPv4 格式: 包含点号
    if [[ "$ip" =~ \. ]]; then
        return 0  # 192.168.1.0/24 包含点号，通过验证
    fi
    
    # IPv6 格式: 包含冒号  
    if [[ "$ip" =~ : ]]; then
        return 0  # 2001:db8::/32 包含冒号，通过验证
    fi
    
    # 默认拒绝
    return 1
}

# 生成白名单映射文件
generate_whitelist_map() {
    log "开始生成nginx白名单映射配置..."
    
    # 确保目标目录存在
    mkdir -p "$(dirname "$MAP_FILE")"
    
    # 创建临时文件
    local tmp_map
    tmp_map=$(mktemp)
    
    # 清理函数 - 避免变量作用域问题
    cleanup_temp_file() {
        local temp_file="$1"
        rm -f "$temp_file"
    }
    
    # 生成文件头
    cat > "$tmp_map" << EOF
# 白名单映射文件 - 自动生成 $(date)
# 格式: IP地址 1; (允许访问)
# 此文件由 generate-whitelist-map.sh 统一生成，请勿手动修改
EOF
    
    local ip_count=0  # 从0开始计数，避免重复
    
    # 使用关联数组去重
    declare -A seen_ips
    
    # 处理白名单文件中的IP
    if [[ -f "$WHITELIST_FILE" ]]; then
        log "读取白名单文件: $WHITELIST_FILE"
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过空行和注释行
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                # 清理IP地址前后空格
                local ip
                ip=$(echo "$line" | xargs)
                
                if [[ -n "$ip" ]]; then
                    # 检查是否已经处理过这个IP（去重）
                    if [[ -z "${seen_ips[$ip]}" ]]; then
                        seen_ips[$ip]=1
                        
                        # 调试：输出读取到的原始IP
                        log "调试：从文件读取到IP: '$ip'"
                        
                        # 处理IP并添加到映射文件
                        echo "${ip} 1;" >> "$tmp_map"
                        ip_count=$((ip_count + 1))
                        
                        # 调试：确认写入的内容
                        log "调试：写入映射文件: '${ip} 1;'"
                    else
                        log "调试：跳过重复IP: '$ip'"
                    fi
                fi
            fi
        done < "$WHITELIST_FILE"
    else
        log "警告: 白名单文件不存在: $WHITELIST_FILE"
    fi
    
    # 原子性写入（移动临时文件到目标位置）
    if mv "$tmp_map" "$MAP_FILE"; then
        log "映射文件生成成功: $MAP_FILE"
        log "总计IP条目数: $ip_count"
        
        # 设置正确的文件权限
        chmod 644 "$MAP_FILE"
        # mv成功时临时文件已被移动，无需清理
        return 0
    else
        log "错误: 无法写入映射文件: $MAP_FILE"
        # 清理临时文件
        cleanup_temp_file "$tmp_map"
        return 1
    fi
}

# 主函数
main() {
    case "${1:-generate}" in
        "generate")
            generate_whitelist_map
            ;;
        "test")
            if [[ -f "$MAP_FILE" ]]; then
                log "映射文件存在: $MAP_FILE"
                log "文件大小: $(stat -c%s "$MAP_FILE" 2>/dev/null || echo "未知") bytes"
                log "条目数量: $(grep -c " 1;" "$MAP_FILE" 2>/dev/null || echo "0")"
                return 0
            else
                log "错误: 映射文件不存在: $MAP_FILE"
                return 1
            fi
            ;;
        "help"|"-h"|"--help")
            echo "用法: $0 [generate|test|help]"
            echo "  generate  - 生成白名单映射文件 (默认)"
            echo "  test      - 检查映射文件状态"
            echo "  help      - 显示此帮助信息"
            echo ""
            echo "环境变量:"
            echo "  WHITELIST_FILE - 白名单文件路径 (默认: /data/nginx/whitelist.txt)"
            echo "  MAP_FILE       - 映射文件路径 (默认: /data/nginx/whitelist_map.conf)"
            ;;
        *)
            log "错误: 未知命令: $1"
            log "使用 '$0 help' 查看帮助"
            return 1
            ;;
    esac
}

# 只有直接执行时才运行main函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
