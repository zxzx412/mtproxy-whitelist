#!/usr/bin/env bash
set -euo pipefail

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[信息]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[成功]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
log_err()  { echo -e "${RED}[错误]${NC} $*"; }

is_cmd() { command -v "$1" >/dev/null 2>&1; }

is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

get_public_ip() {
  if is_cmd curl; then
    curl -s https://ipv4.icanhazip.com | tr -d '\r'
  elif is_cmd wget; then
    wget -qO- https://ipv4.icanhazip.com | tr -d '\r'
  else
    echo "unknown"
  fi
}

check_haproxy_listen() {
  log_info "检查 haproxy 是否监听 14202..."
  local found=""

  if is_cmd ss; then
    found="$(ss -tuln | awk '{print $5}' | grep -E '(^|:)(14202)$' || true)"
  elif is_cmd netstat; then
    found="$(netstat -tlnp 2>/dev/null | awk '{print $4}' | grep -E '(^|:)(14202)$' || true)"
  fi

  if [[ -n "$found" ]]; then
    log_ok "端口 14202 正在监听"
  else
    log_err "端口 14202 未监听；请运行 ./deploy.sh restart 并确保 mtproxy-haproxy 常驻"
  fi

  if is_cmd docker; then
    local hp_state
    hp_state="$(docker ps --format '{{.Names}} {{.Status}}' | grep '^mtproxy-haproxy ' || true)"
    if [[ -n "$hp_state" ]]; then
      log_ok "容器状态: $hp_state"
    else
      log_err "mtproxy-haproxy 容器未运行"
    fi
  fi
}

check_gost_presence() {
  log_info "检查是否存在 gost 转发进程或端口..."
  local has_gost="false"

  if is_cmd pgrep; then
    if pgrep -fl gost >/dev/null 2>&1; then
      log_warn "检测到 gost 进程："
      pgrep -fl gost || true
      has_gost="true"
    fi
  fi

  # 常见端口：14201 为你反馈中出现的 gost 监听端口
  local ports_output=""
  if is_cmd ss; then
    ports_output="$(ss -tulnp 2>/dev/null | grep -E ':(14201|14202)\b' || true)"
  elif is_cmd netstat; then
    ports_output="$(netstat -tulnp 2>/dev/null | grep -E ':(14201|14202)\b' || true)"
  fi
  if [[ -n "$ports_output" ]]; then
    echo "$ports_output" | while read -r line; do
      if echo "$line" | grep -qi gost; then
        log_warn "端口由 gost 监听：$line"
        has_gost="true"
      fi
    done
  fi

  if [[ "$has_gost" == "true" ]]; then
    log_err "存在 gost 中间转发；请停止/绕过 gost，确保公网 14202 直达 haproxy:14202"
  else
    log_ok "未检测到 gost 干预 14201/14202"
  fi
}

check_nat_dnat_rules() {
  log_info "检查本机防火墙/NAT 转发规则，确认无本机侧二次转发到非 14202..."
  local has_tools="false"
  if is_cmd iptables; then
    has_tools="true"
    log_info "iptables -t nat 规则："
    iptables -t nat -S 2>/dev/null | sed 's/^/- /'
    # 简单提示检查
    if iptables -t nat -S 2>/dev/null | grep -E 'DNAT|REDIRECT' | grep -E '14201|9999' >/dev/null 2>&1; then
      log_warn "检测到可能的 NAT/重定向到 14201 或 9999，请确认公网 14202 未被本机规则绕行"
    fi
  fi

  if is_cmd nft; then
    has_tools="true"
    log_info "nftables 规则集（节选含 14201/14202/9999）："
    nft list ruleset 2>/dev/null | grep -E '14201|14202|9999' -n || log_info "无匹配端口规则"
  fi

  if [[ "$has_tools" == "false" ]]; then
    log_warn "未安装 iptables/nft，跳过本机 NAT 规则检查"
  fi
}

parse_last_nginx_proxy_log() {
  # 解析最后一条 proxy_protocol_access.log，判断真实 IP
  if is_cmd docker; then
    if ! docker exec mtproxy-whitelist test -f /var/log/nginx/proxy_protocol_access.log 2>/dev/null; then
      log_err "容器内缺少 /var/log/nginx/proxy_protocol_access.log"
      return
    fi
    local last
    last="$(docker exec mtproxy-whitelist bash -lc "tail -n 1 /var/log/nginx/proxy_protocol_access.log" 2>/dev/null || true)"
    if [[ -z "$last" ]]; then
      log_warn "暂无最近连接日志"
      return
    fi
    echo "$last"
    # 格式示例: 127.0.0.1|proxy:172.16.5.6|final:172.16.5.6|public:0 [...]
    local proxy_ip final_ip status wl upstream
    proxy_ip="$(echo "$last" | sed -n 's/.*proxy:\([^|]*\).*/\1/p')"
    final_ip="$(echo "$last" | sed -n 's/.*final:\([^|]*\).*/\1/p')"
    status="$(echo "$last" | sed -n 's/.* TCP \([0-9][0-9][0-9]\) .*/\1/p')"
    wl="$(echo "$last" | sed -n 's/.*whitelist:\([01]\).*/\1/p')"
    upstream="$(echo "$last" | sed -n 's/.*upstream:\([^ ]*\).*/\1/p')"

    if [[ "$proxy_ip" == "-" || -z "$proxy_ip" ]]; then
      log_warn "未收到 PROXY Protocol 头（proxy:-），说明请求未通过 haproxy:14202→nginx:445 链路"
    else
      if is_private_ip "$proxy_ip"; then
        log_err "proxy_protocol_addr=$proxy_ip 为内网地址，非真实公网 IP；当前链路仍被上游网关/代理终结"
      else
        log_ok "已获取真实公网 IP：$proxy_ip"
      fi
    fi

    if [[ "$status" == "200" && "$wl" == "1" ]]; then
      log_ok "白名单命中，连接放行（200）。final:$final_ip upstream:$upstream"
    elif [[ "$status" == "502" && "$wl" == "0" ]]; then
      log_warn "白名单未命中，返回 502（拒绝池 upstream:$upstream）。如确认此连接为你的手机公网 IP，请加入白名单。"
    fi
  else
    log_err "未安装 docker，无法解析容器内 nginx 日志"
  fi
}

wait_mobile_and_evaluate() {
  log_info "进入移动网络直连测试模式：请用手机4G/5G直接连接 服务器IP:14202"
  log_info "正在监控最近连接日志，捕获到新记录后自动评估真实IP..."
  local start_ts
  start_ts="$(date +%s)"

  for i in {1..60}; do
    sleep 2
    if is_cmd docker; then
      local last
      last="$(docker exec mtproxy-whitelist bash -lc "tail -n 1 /var/log/nginx/proxy_protocol_access.log" 2>/dev/null || true)"
      if [[ -n "$last" ]]; then
        local ts
        ts="$(echo "$last" | sed -n 's/.*\[\([0-9A-Za-z:\/\+\- ]\+\)\].*/\1/p')"
        echo "$last"
        parse_last_nginx_proxy_log
        break
      fi
    fi
  done
}

main() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "用法: $0 [--wait-mobile]"
    echo "  无参数: 执行一次性诊断"
    echo "  --wait-mobile: 进入移动网络直连监控模式，抓取新日志并评估真实IP"
    exit 0
  fi

  log_info "开始 NAT/真实IP诊断"
  local pub_ip
  pub_ip="$(get_public_ip)"
  log_info "检测到公网IP: ${pub_ip}"

  check_haproxy_listen
  check_gost_presence
  check_nat_dnat_rules

  log_info "解析最近的 nginx PROXY Protocol 日志记录..."
  parse_last_nginx_proxy_log

  if [[ "${1:-}" == "--wait-mobile" ]]; then
    wait_mobile_and_evaluate
  fi

  echo
  log_info "结论与建议："
  echo "- 若 proxy_protocol_addr 显示为公网 IP -> 真实IP获取正常。"
  echo "- 若为内网 IP（如 172.16.x.x） -> 上游转发未使用 PROXY Protocol，或经由 gost/路由器端代理导致源IP丢失；请将公网 14202 直达服务器 14202。"
  echo "- 若 proxy:-（无头） -> 请求未经过 haproxy→nginx(445) 链路，检查端口监听/路由映射、防火墙。"
  echo "- 白名单未命中返回 502 时 -> 将手机的公网IP或所在段加入白名单后再测。"
}

main "$@"