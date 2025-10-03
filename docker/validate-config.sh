#!/bin/bash
# MTProxy 白名单系统配置验证脚本
# 用于部署前验证环境配置的正确性

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误计数
ERRORS=0
WARNINGS=0

# 加载.env文件（如果存在）
if [ -f .env ]; then
    echo "加载配置文件: .env"
    source .env
elif [ -f .env.example ]; then
    echo "⚠️  警告: 未找到.env文件，使用.env.example"
    source .env.example
    WARNINGS=$((WARNINGS + 1))
else
    echo "❌ 错误: 未找到.env或.env.example文件"
    exit 1
fi

echo ""
echo "=========================================="
echo "MTProxy 配置验证"
echo "=========================================="
echo ""

# ===== 1. 验证部署模式 =====
validate_deployment_mode() {
    echo "【1】验证部署模式..."

    # 兼容旧的NAT_MODE
    if [ -n "$NAT_MODE" ] && [ -z "$DEPLOYMENT_MODE" ]; then
        echo -e "${YELLOW}⚠️  警告: NAT_MODE已废弃，请使用DEPLOYMENT_MODE${NC}"
        WARNINGS=$((WARNINGS + 1))

        if [ "$NAT_MODE" = "true" ]; then
            if [ "${HAPROXY_ENABLED:-false}" = "true" ]; then
                DEPLOYMENT_MODE="nat-haproxy"
            else
                DEPLOYMENT_MODE="nat-direct"
            fi
        else
            DEPLOYMENT_MODE="bridge"
        fi
        echo "   自动转换为: DEPLOYMENT_MODE=${DEPLOYMENT_MODE}"
    fi

    case "${DEPLOYMENT_MODE:-bridge}" in
        bridge)
            echo -e "${GREEN}✓${NC} 部署模式: bridge (Docker桥接网络)"
            ;;
        nat-direct)
            echo -e "${GREEN}✓${NC} 部署模式: nat-direct (NAT直连，主机网络)"
            ;;
        nat-haproxy)
            echo -e "${GREEN}✓${NC} 部署模式: nat-haproxy (NAT+HAProxy，PROXY Protocol)"
            ;;
        *)
            echo -e "${RED}✗${NC} 错误: 未知部署模式 '${DEPLOYMENT_MODE}'"
            echo "   支持的模式: bridge, nat-direct, nat-haproxy"
            ERRORS=$((ERRORS + 1))
            ;;
    esac
}

# ===== 2. 验证端口配置 =====
validate_ports() {
    echo ""
    echo "【2】验证端口配置..."

    # 检查旧变量名
    if [ -n "$MTPROXY_PORT" ]; then
        echo -e "${YELLOW}⚠️  警告: MTPROXY_PORT已废弃，请使用EXTERNAL_PROXY_PORT${NC}"
        WARNINGS=$((WARNINGS + 1))
        EXTERNAL_PROXY_PORT="${EXTERNAL_PROXY_PORT:-$MTPROXY_PORT}"
    fi

    if [ -n "$WEB_PORT" ]; then
        echo -e "${YELLOW}⚠️  警告: WEB_PORT已废弃，请使用EXTERNAL_WEB_PORT${NC}"
        WARNINGS=$((WARNINGS + 1))
        EXTERNAL_WEB_PORT="${EXTERNAL_WEB_PORT:-$WEB_PORT}"
    fi

    # 设置默认值
    EXTERNAL_PROXY_PORT="${EXTERNAL_PROXY_PORT:-14202}"
    EXTERNAL_WEB_PORT="${EXTERNAL_WEB_PORT:-8989}"
    INTERNAL_PROXY_PROTOCOL_PORT="${INTERNAL_PROXY_PROTOCOL_PORT:-14445}"
    BACKEND_MTPROXY_PORT="${BACKEND_MTPROXY_PORT:-444}"

    # 检查端口445废弃警告
    if [ "${PROXY_PROTOCOL_PORT:-}" = "445" ]; then
        echo -e "${YELLOW}⚠️  警告: 端口445已废弃（Windows SMB冲突），建议使用14445${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    # 验证端口范围
    local ports=(
        "EXTERNAL_PROXY_PORT:${EXTERNAL_PROXY_PORT}:代理端口"
        "EXTERNAL_WEB_PORT:${EXTERNAL_WEB_PORT}:Web管理端口"
        "INTERNAL_PROXY_PROTOCOL_PORT:${INTERNAL_PROXY_PROTOCOL_PORT}:PROXY Protocol端口"
        "BACKEND_MTPROXY_PORT:${BACKEND_MTPROXY_PORT}:MTProxy后端端口"
    )

    for port_spec in "${ports[@]}"; do
        IFS=':' read -r name value desc <<< "$port_spec"

        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}✗${NC} 错误: $desc ($name) 不是有效数字: $value"
            ERRORS=$((ERRORS + 1))
            continue
        fi

        if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
            echo -e "${RED}✗${NC} 错误: $desc ($name) 超出范围(1-65535): $value"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${GREEN}✓${NC} $desc: $value"
        fi
    done

    # 检查端口冲突
    if [ "$EXTERNAL_PROXY_PORT" = "$EXTERNAL_WEB_PORT" ]; then
        echo -e "${RED}✗${NC} 错误: 代理端口和Web端口不能相同"
        ERRORS=$((ERRORS + 1))
    fi
}

# ===== 3. 验证业务配置 =====
validate_business_config() {
    echo ""
    echo "【3】验证业务配置..."

    # MTProxy域名
    if [ -z "$MTPROXY_DOMAIN" ]; then
        echo -e "${YELLOW}⚠️  警告: MTPROXY_DOMAIN未设置，将使用默认值 azure.microsoft.com${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✓${NC} MTProxy域名: $MTPROXY_DOMAIN"
    fi

    # 管理员密码
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo -e "${RED}✗${NC} 错误: ADMIN_PASSWORD未设置"
        ERRORS=$((ERRORS + 1))
    elif [ "$ADMIN_PASSWORD" = "admin123" ]; then
        echo -e "${YELLOW}⚠️  警告: 使用默认管理员密码，建议修改${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✓${NC} 管理员密码: ******** (已设置)"
    fi

    # SECRET_KEY
    if [ -z "$SECRET_KEY" ]; then
        echo -e "${YELLOW}⚠️  警告: SECRET_KEY未设置，建议设置随机密钥${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}✓${NC} SECRET_KEY: ******** (已设置)"
    fi
}

# ===== 4. 验证策略文件 =====
validate_strategy_files() {
    echo ""
    echo "【4】验证部署策略文件..."

    local mode="${DEPLOYMENT_MODE:-bridge}"
    local strategy_file="docker/strategies/${mode}.conf"

    if [ ! -f "$strategy_file" ]; then
        echo -e "${RED}✗${NC} 错误: 策略文件不存在: $strategy_file"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} 策略文件存在: $strategy_file"

        # 验证策略文件语法
        if bash -n "$strategy_file" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} 策略文件语法正确"
        else
            echo -e "${RED}✗${NC} 错误: 策略文件语法错误"
            ERRORS=$((ERRORS + 1))
        fi
    fi
}

# ===== 5. 验证Docker配置 =====
validate_docker_config() {
    echo ""
    echo "【5】验证Docker环境..."

    # 检查docker命令
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  警告: Docker未安装或不在PATH中${NC}"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    echo -e "${GREEN}✓${NC} Docker: $(docker --version 2>/dev/null | head -1)"

    # 检查docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Docker Compose: $(docker-compose --version 2>/dev/null | head -1)"
    else
        echo -e "${YELLOW}⚠️  警告: docker-compose未安装${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ===== 6. 验证文件权限 =====
validate_permissions() {
    echo ""
    echo "【6】验证文件权限..."

    local scripts=(
        "docker/entrypoint.sh"
        "docker/start-mtproxy.sh"
        "docker/generate-whitelist-map.sh"
    )

    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}✗${NC} 错误: 脚本文件不存在: $script"
            ERRORS=$((ERRORS + 1))
            continue
        fi

        if [ -x "$script" ]; then
            echo -e "${GREEN}✓${NC} $script (可执行)"
        else
            echo -e "${YELLOW}⚠️  警告: $script 不可执行，可能需要 chmod +x${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
}

# ===== 执行所有验证 =====
main() {
    validate_deployment_mode
    validate_ports
    validate_business_config
    validate_strategy_files
    validate_docker_config
    validate_permissions

    # 显示总结
    echo ""
    echo "=========================================="
    echo "验证总结"
    echo "=========================================="

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ 配置验证通过，无错误和警告${NC}"
        exit 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "${YELLOW}⚠️  配置验证通过，但有 $WARNINGS 个警告${NC}"
        exit 0
    else
        echo -e "${RED}❌ 配置验证失败: $ERRORS 个错误, $WARNINGS 个警告${NC}"
        echo ""
        echo "请修复以上错误后重试"
        exit 1
    fi
}

main "$@"
