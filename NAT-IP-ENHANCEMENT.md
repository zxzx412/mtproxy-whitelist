# MTProxy 白名单系统 - NAT 环境 IP 获取增强功能

## 🎯 概述

本增强功能解决了 MTProxy 白名单系统在 NAT 环境下无法正确获取真实客户端 IP 的问题，通过多种技术手段实现了可靠的 IP 获取机制。

## 🚀 核心特性

### ✅ 已实现的功能

1. **PROXY Protocol 支持**
   - 完整的 PROXY Protocol v1/v2 支持
   - 自动检测和解析真实客户端 IP
   - 支持 TCP 和 UDP 协议

2. **多层 IP 获取机制**
   - PROXY Protocol 优先级最高
   - 回退到 X-Forwarded-For 头部
   - 最终回退到 remote_addr

3. **智能白名单管理**
   - 自动检测网络环境
   - 智能生成白名单配置
   - 支持 CIDR 网段和单个 IP

4. **实时监控和诊断**
   - 实时 IP 连接监控
   - 详细的连接统计分析
   - 自动化诊断工具

5. **透明代理支持**
   - iptables 规则自动配置
   - SO_ORIGINAL_DST 支持
   - 网络层面的 IP 保持

## 📁 功能集成说明

### 核心功能（已集成到 deploy.sh）

| 功能 | 命令 | 描述 |
|------|------|------|
| NAT IP 获取修复 | `./deploy.sh fix-nat-ip` | 修复 NAT 环境下的 IP 获取问题 |
| PROXY Protocol 支持 | `./deploy.sh enable-proxy-protocol` | 启用 PROXY Protocol 支持 |
| IP 获取测试 | `./deploy.sh test-nat-ip` | 测试 NAT IP 获取功能 |
| IP 获取诊断 | `./deploy.sh diagnose-ip` | 运行 IP 获取诊断 |

### 配置文件

| 文件名 | 功能描述 |
|--------|----------|
| `deploy.sh` | 集成了所有 NAT IP 获取功能的主部署脚本 |
| `docker/fix-nat-whitelist.sh` | 容器内白名单优化脚本 |
| `docker/nginx.conf.template` | 增强的 nginx 配置模板 |
| `docker/entrypoint.sh` | 更新的容器启动脚本 |
| `docker-compose.yml` | 支持 NAT 的 Docker 配置 |

## 🛠️ 快速部署

### 方法一：一键部署（推荐）

```bash
# 下载项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist

# 运行集成的部署脚本（选择 NAT 模式）
sudo ./deploy.sh
```

### 方法二：手动配置 NAT 功能

```bash
# 1. 正常部署服务
sudo ./deploy.sh

# 2. 修复 NAT IP 获取（如果需要）
sudo ./deploy.sh fix-nat-ip

# 3. 启用 PROXY Protocol（如果需要）
sudo ./deploy.sh enable-proxy-protocol

# 4. 测试 NAT IP 获取功能
sudo ./deploy.sh test-nat-ip

# 5. 运行诊断（如果遇到问题）
sudo ./deploy.sh diagnose-ip
```

## 🔧 配置选项

### 环境变量

```bash
# NAT 模式配置
NAT_MODE=true                    # 启用 NAT 模式
ENABLE_PROXY_PROTOCOL=true       # 启用 PROXY Protocol
ENABLE_TRANSPARENT_PROXY=false   # 启用透明代理
NETWORK_MODE=bridge              # Docker 网络模式
PRIVILEGED_MODE=false            # 特权模式

# 调试配置
DEBUG_IP_DETECTION=true          # 启用 IP 检测调试
LOG_LEVEL=INFO                   # 日志级别
ENABLE_IP_MONITORING=true        # 启用 IP 监控
```

### Docker Compose 配置

```yaml
services:
  mtproxy-whitelist:
    # 网络配置
    network_mode: "${NETWORK_MODE:-bridge}"
    
    # 特权和能力
    privileged: ${PRIVILEGED_MODE:-false}
    cap_add:
      - NET_ADMIN
      - NET_RAW
      - SYS_ADMIN
    
    # 系统控制
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.route_localnet=1
```

## 📊 监控和诊断

### 实时监控命令

```bash
# 实时监控客户端 IP 连接
mtproxy-whitelist monitor-ips

# 查看客户端 IP 统计
mtproxy-whitelist ip-stats

# 运行 IP 获取诊断
mtproxy-whitelist diagnose-ip

# 测试 NAT IP 获取功能
mtproxy-whitelist test-nat-ip

# 修复 NAT IP 获取问题
mtproxy-whitelist fix-nat-ip
```

### 直接 Docker 命令

```bash
# 实时监控客户端 IP 连接
docker exec mtproxy-whitelist /usr/local/bin/monitor-client-ips.sh

# 查看客户端 IP 统计
docker exec mtproxy-whitelist /usr/local/bin/ip-stats.sh

# 运行系统诊断
docker exec mtproxy-whitelist /usr/local/bin/diagnose-ip.sh
```

### 日志分析

```bash
# 查看 nginx stream 日志
docker exec mtproxy-whitelist tail -f /var/log/nginx/stream_access.log

# 查看 IP 统计
docker exec mtproxy-whitelist ip-stats.sh

# 查看容器日志
docker-compose logs -f mtproxy-whitelist
```

## 🔍 IP 获取机制详解

### 1. PROXY Protocol 机制

```nginx
# nginx 配置
server {
    listen 0.0.0.0:443 proxy_protocol;
    
    # 使用 PROXY Protocol 获取的 IP
    set $real_ip $proxy_protocol_addr;
}
```

### 2. 多层回退策略

```nginx
# 真实 IP 获取策略
map $proxy_protocol_addr $detected_real_ip {
    default $remote_addr;
    ~^.+$ $proxy_protocol_addr;
}

# 过滤内网 IP
map $detected_real_ip $final_client_ip {
    default $detected_real_ip;
    ~^172\.(1[6-9]|2[0-9]|3[01])\. $remote_addr;
    ~^10\. $remote_addr;
    ~^192\.168\. $remote_addr;
}
```

### 3. 白名单匹配

```nginx
# 使用最终确定的客户端 IP
geo $final_client_ip $allowed {
    default 0;
    include /data/nginx/whitelist_map.conf;
}
```

## 🚨 故障排除

### 常见问题

#### 1. IP 获取不正确

**症状**: 白名单显示的都是内网 IP (172.x.x.x)

**解决方案**:
```bash
# 检查 PROXY Protocol 状态
docker exec mtproxy-whitelist diagnose-ip.sh

# 启用 PROXY Protocol
docker exec mtproxy-whitelist enable-proxy-protocol.sh enable

# 重启服务
docker-compose restart
```

#### 2. 白名单不生效

**症状**: 添加了 IP 但仍然被拒绝

**解决方案**:
```bash
# 检查白名单配置
docker exec mtproxy-whitelist cat /data/nginx/whitelist_map.conf

# 重新生成白名单
docker exec mtproxy-whitelist fix-nat-whitelist.sh fix

# 重载 nginx
docker exec mtproxy-whitelist nginx -s reload
```

#### 3. 容器权限不足

**症状**: iptables 操作失败

**解决方案**:
```bash
# 启用特权模式
echo "PRIVILEGED_MODE=true" >> .env
docker-compose down && docker-compose up -d

# 或添加必要权限
# 在 docker-compose.yml 中添加:
cap_add:
  - NET_ADMIN
  - NET_RAW
```

### 诊断命令

```bash
# 完整系统诊断
./deploy.sh diagnose-ip

# NAT IP 获取测试
./deploy.sh test-nat-ip

# 修复 NAT IP 获取
./deploy.sh fix-nat-ip

# 启用 PROXY Protocol
./deploy.sh enable-proxy-protocol

# 容器内诊断
docker exec mtproxy-whitelist /usr/local/bin/diagnose-ip.sh

# 使用管理脚本诊断
mtproxy-whitelist diagnose-ip
```

## 📈 性能优化

### nginx 优化配置

```nginx
# 连接复用
upstream mtproxy_backend {
    server 127.0.0.1:444;
    keepalive 32;
}

# 启用 socket keepalive
server {
    proxy_socket_keepalive on;
}
```

### 系统参数优化

```bash
# 内核参数
net.ipv4.ip_forward=1
net.ipv4.conf.all.route_localnet=1
net.netfilter.nf_conntrack_acct=1
```

## 🔐 安全考虑

### 1. 权限控制

- 最小权限原则
- 仅在必要时启用特权模式
- 定期审查 iptables 规则

### 2. IP 验证

- 严格的 IP 格式验证
- 防止 IP 欺骗攻击
- 白名单定期审查

### 3. 日志监控

- 详细的连接日志
- 异常 IP 访问告警
- 定期日志分析

## 📚 技术原理

### PROXY Protocol 工作原理

1. **客户端连接**: 客户端连接到负载均衡器
2. **协议封装**: 负载均衡器在 TCP 流前添加 PROXY 头
3. **头部解析**: nginx 解析 PROXY 头获取真实 IP
4. **白名单匹配**: 使用真实 IP 进行白名单验证

### 透明代理原理

1. **流量拦截**: iptables 拦截目标端口流量
2. **地址重定向**: REDIRECT 到透明代理端口
3. **原始地址保持**: SO_ORIGINAL_DST 保持原始目标
4. **真实 IP 传递**: 通过 socket 选项获取真实源 IP

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 开发环境设置

```bash
# 克隆项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist

# 测试 NAT 功能
./deploy-nat-enhanced.sh deploy

# 运行测试
./deploy-nat-enhanced.sh test
```

### 提交规范

- 功能分支: `feature/nat-enhancement-xxx`
- 修复分支: `fix/nat-issue-xxx`
- 文档分支: `docs/nat-documentation`

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

---

🌟 **如果这个 NAT 增强功能对您有帮助，请给个 Star！**

📞 **技术支持**: 如遇问题，请提交 [Issue](https://github.com/zxzx412/mtproxy-whitelist/issues)