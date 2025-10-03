# MTProxy 白名单系统 v5.0 快速参考

## 端口速查表

| 端口 | 变量名 | 监听范围 | 用途 | 模式 |
|-----|-------|---------|------|------|
| **14202** | EXTERNAL_PROXY_PORT | 0.0.0.0 | 客户端连接（HAProxy/Nginx） | 全部 |
| **8989** | EXTERNAL_WEB_PORT | 0.0.0.0 | Web管理界面 | 全部 |
| **14445** | INTERNAL_PROXY_PROTOCOL_PORT | 127.0.0.1 | PROXY Protocol内部端口 | NAT-HAProxy |
| **444** | BACKEND_MTPROXY_PORT | 0.0.0.0 | MTProxy实际服务 | 全部 |
| **8080** | INTERNAL_API_PORT | 127.0.0.1 | Flask API | 全部 |
| **8081** | INTERNAL_MTPROXY_STATS_PORT | 127.0.0.1 | MTProxy统计 | 全部 |

---

## 常用命令

### 启动/停止服务

```bash
# Bridge模式
docker-compose up -d
docker-compose down

# NAT模式（交互式选择）
./docker-compose-nat.sh up
./docker-compose-nat.sh down

# NAT+HAProxy模式
USE_HAPROXY=true ./docker-compose-nat.sh up

# NAT直连模式
USE_HAPROXY=false ./docker-compose-nat.sh up
```

### 查看状态

```bash
# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f mtproxy-whitelist

# 健康检查
docker exec mtproxy-whitelist /usr/local/bin/health-check.sh
```

### 配置管理

```bash
# 验证配置
docker/validate-config.sh

# 测试docker-compose配置
docker-compose config

# 重新加载nginx
docker-compose exec mtproxy-whitelist nginx -s reload

# 重新加载白名单
docker-compose exec mtproxy-whitelist /usr/local/bin/reload-whitelist.sh
```

### 调试命令

```bash
# 进入容器
docker-compose exec mtproxy-whitelist sh

# 查看端口监听
docker-compose exec mtproxy-whitelist ss -tlnp

# 查看进程
docker-compose exec mtproxy-whitelist ps aux

# 查看nginx配置
docker-compose exec mtproxy-whitelist cat /etc/nginx/nginx.conf

# 测试IP获取（NAT模式）
./docker-compose-nat.sh test-ip
```

---

## 部署模式选择

### Bridge模式（推荐新手）
```bash
DEPLOYMENT_MODE=bridge
docker-compose up -d
```
- ✅ 配置简单
- ✅ 端口隔离
- ❌ 无法在NAT环境获取真实IP

### NAT+HAProxy模式（推荐NAT环境）
```bash
DEPLOYMENT_MODE=nat-haproxy
docker-compose -f docker-compose.nat-haproxy.yml up -d
```
- ✅ PROXY Protocol获取真实IP
- ✅ 白名单验证真实客户端IP
- ❌ 配置相对复杂

### NAT直连模式（简化版）
```bash
DEPLOYMENT_MODE=nat-direct
docker-compose -f docker-compose.nat-direct.yml up -d
```
- ✅ 简化架构
- ✅ 性能最优
- ❌ 无PROXY Protocol（无法获取真实IP）

---

## 配置模板

### .env最小配置
```bash
DEPLOYMENT_MODE=bridge
EXTERNAL_PROXY_PORT=14202
EXTERNAL_WEB_PORT=8989
MTPROXY_DOMAIN=azure.microsoft.com
ADMIN_PASSWORD=your_secure_password
```

### .env完整配置
```bash
# 部署模式
DEPLOYMENT_MODE=bridge

# 外部端口
EXTERNAL_PROXY_PORT=14202
EXTERNAL_WEB_PORT=8989

# 内部端口（高级）
INTERNAL_PROXY_PROTOCOL_PORT=14445
BACKEND_MTPROXY_PORT=444
INTERNAL_API_PORT=8080

# 业务配置
MTPROXY_DOMAIN=azure.microsoft.com
MTPROXY_TAG=
SECRET_KEY=your_secret_key
JWT_EXPIRATION_HOURS=24
ADMIN_PASSWORD=your_secure_password
```

---

## 故障排查检查清单

### ❌ 容器无法启动
```bash
# 1. 检查端口占用
netstat -tuln | grep -E "14202|8989|444"

# 2. 检查Docker日志
docker-compose logs mtproxy-whitelist

# 3. 验证配置文件
docker/validate-config.sh

# 4. 重新构建镜像
docker-compose build --no-cache
```

### ❌ 客户端无法连接
```bash
# 1. 检查IP是否在白名单
docker-compose exec mtproxy-whitelist cat /data/nginx/whitelist.txt

# 2. 测试端口连通性
telnet 服务器IP 14202

# 3. 查看nginx日志
docker-compose logs mtproxy-whitelist | grep -E "reject|allow"

# 4. 检查防火墙
iptables -L -n | grep 14202
```

### ❌ Web界面无法访问
```bash
# 1. 检查Web端口
curl http://localhost:8989

# 2. 检查nginx监听
docker-compose exec mtproxy-whitelist ss -tlnp | grep 8989

# 3. 检查API健康
curl http://localhost:8989/api/health
```

### ❌ NAT模式获取内网IP
```bash
# 1. 确认使用HAProxy模式
echo $DEPLOYMENT_MODE  # 应该是 nat-haproxy

# 2. 检查HAProxy运行状态
docker-compose ps haproxy

# 3. 查看PROXY Protocol日志
docker-compose exec mtproxy-whitelist tail /var/log/nginx/proxy_protocol_access.log

# 4. 运行IP诊断
./diagnose-real-ip.sh
```

---

## API快速参考

### 登录
```bash
curl -X POST http://localhost:8989/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

### 获取白名单
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8989/api/whitelist
```

### 添加IP
```bash
curl -X POST http://localhost:8989/api/whitelist \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ip":"1.2.3.4","description":"测试IP"}'
```

### 删除IP
```bash
curl -X DELETE http://localhost:8989/api/whitelist/ID \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 健康检查
```bash
curl http://localhost:8989/api/health
```

---

## 环境变量速查

### 核心变量

| 变量 | 说明 | 默认值 |
|-----|------|--------|
| `DEPLOYMENT_MODE` | 部署模式 | bridge |
| `EXTERNAL_PROXY_PORT` | 客户端连接端口 | 14202 |
| `EXTERNAL_WEB_PORT` | Web管理端口 | 8989 |
| `MTPROXY_DOMAIN` | 伪装域名 | azure.microsoft.com |
| `ADMIN_PASSWORD` | 管理员密码 | admin123 |

### 高级变量

| 变量 | 说明 | 默认值 |
|-----|------|--------|
| `INTERNAL_PROXY_PROTOCOL_PORT` | PROXY Protocol端口 | 14445 |
| `BACKEND_MTPROXY_PORT` | MTProxy实际端口 | 444 |
| `SECRET_KEY` | Flask密钥 | 自动生成 |
| `JWT_EXPIRATION_HOURS` | JWT过期时间 | 24 |

### 废弃变量（向后兼容）

| 旧变量 | 新变量 | 状态 |
|-------|-------|------|
| `MTPROXY_PORT` | `EXTERNAL_PROXY_PORT` | v6.0移除 |
| `WEB_PORT` | `EXTERNAL_WEB_PORT` | v6.0移除 |
| `NAT_MODE` | `DEPLOYMENT_MODE` | v6.0移除 |

---

## 日志位置

```bash
# 容器内日志
/var/log/nginx/access.log          # Nginx访问日志
/var/log/nginx/error.log           # Nginx错误日志
/var/log/nginx/stream_access.log   # Stream访问日志
/var/log/mtproxy/stdout.log        # MTProxy标准输出
/var/log/api/stdout.log            # API标准输出
/var/log/supervisord.log           # Supervisor日志

# 查看方式
docker-compose exec mtproxy-whitelist tail -f /var/log/nginx/access.log
docker-compose logs -f mtproxy-whitelist
```

---

## 性能优化

### 限制连接数
```bash
# 修改docker-compose.yml
deploy:
  resources:
    limits:
      memory: 1G
      cpus: '2.0'
```

### 调整Nginx worker
```bash
# 修改nginx.conf.template
worker_processes auto;
worker_connections 4096;
```

### 启用日志缓冲
```bash
# 修改nginx日志配置
access_log /var/log/nginx/access.log buffer=32k;
```

---

## 安全加固

### 1. 修改默认密码
```bash
# .env
ADMIN_PASSWORD=your_strong_password_here
```

### 2. 限制Web端口访问
```bash
# iptables示例
iptables -A INPUT -p tcp --dport 8989 -s 信任IP -j ACCEPT
iptables -A INPUT -p tcp --dport 8989 -j DROP
```

### 3. 启用HTTPS（推荐反向代理）
```bash
# 使用Nginx反向代理
upstream mtproxy_web {
    server localhost:8989;
}

server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://mtproxy_web;
    }
}
```

### 4. 定期备份白名单
```bash
# 添加到crontab
0 2 * * * docker exec mtproxy-whitelist cat /data/nginx/whitelist.txt > /backup/whitelist-$(date +\%Y\%m\%d).txt
```

---

## 性能指标

### 正常运行指标
- 容器内存使用：< 300MB
- CPU使用率：< 10%
- 连接数：根据实际负载
- 健康检查：100%通过

### 监控命令
```bash
# 资源使用
docker stats mtproxy-whitelist

# 连接统计
docker exec mtproxy-whitelist ss -s

# MTProxy统计（如果启用）
curl http://localhost:8081/stats
```

---

## 相关文档

- **迁移指南**: docs/MIGRATION_v5.md
- **架构文档**: docs/ARCHITECTURE_v5.md
- **端口分配**: docs/PORT_ALLOCATION.md
- **部署模式**: docs/DEPLOYMENT_MODES.md
