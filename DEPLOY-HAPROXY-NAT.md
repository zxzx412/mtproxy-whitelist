# HAProxy+NAT模式部署指南

## 问题分析
从netstat输出可以看到当前部署存在以下问题：
1. HAProxy服务没有运行（缺少14202端口监听）
2. nginx直接监听14203端口（应该仅供HAProxy内部使用）
3. 仍然获取内网IP 172.16.5.6

## 解决方案

### 1. 停止当前服务
```bash
# 停止所有相关服务
docker-compose down
docker-compose -f docker-compose.nat.yml down
docker stop mtproxy-whitelist mtproxy-haproxy 2>/dev/null || true
docker rm mtproxy-whitelist mtproxy-haproxy 2>/dev/null || true
```

### 2. 重新部署HAProxy+NAT模式
```bash
# 使用优化的NAT配置重新部署
docker-compose -f docker-compose.nat.yml up -d --build

# 或使用部署脚本
./deploy.sh deploy-haproxy
```

### 3. 验证部署结果

#### 检查端口监听（期望结果）
```bash
netstat -tlnp | grep -E ":(14202|8787) "
# 应该看到：
# tcp 0 0 0.0.0.0:14202 0.0.0.0:* LISTEN [haproxy进程]
# tcp 0 0 0.0.0.0:8787  0.0.0.0:* LISTEN [haproxy进程]
```

#### 检查服务状态
```bash
docker-compose -f docker-compose.nat.yml ps
# 应该看到haproxy和mtproxy-whitelist都是Up状态
```

#### 检查HAProxy配置
```bash
docker exec mtproxy-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
# 应该显示配置正确
```

#### 检查真实IP获取
```bash
docker exec mtproxy-whitelist tail -f /var/log/nginx/proxy_protocol_access.log
# 应该看到真实IP而不是172.16.5.6
```

## 端口配置说明

### 对外端口（客户端连接）
- **14202**: MTProxy客户端连接端口（HAProxy监听）
- **8787**: Web管理界面端口（HAProxy转发）

### 内部端口（不对外暴露）
- **14203**: PROXY Protocol专用端口（HAProxy → nginx）
- **444**: MTProxy实际运行端口
- **8080**: API内部端口

## 网络流向

```
客户端 → HAProxy:14202 → nginx:14203 (PROXY Protocol) → MTProxy:444
管理员 → HAProxy:8787 → nginx内部 → Web界面
```

## 故障排除

### 如果HAProxy无法启动
```bash
# 检查配置文件
docker run --rm -v $(pwd)/docker/haproxy.cfg:/test.cfg haproxy:2.8-alpine haproxy -c -f /test.cfg

# 检查端口冲突
ss -tuln | grep -E ":(14202|8787) "
```

### 如果仍然获取内网IP
```bash
# 确认HAProxy正在转发PROXY Protocol
docker exec mtproxy-haproxy netstat -tlnp
docker logs mtproxy-haproxy

# 确认nginx配置正确
docker exec mtproxy-whitelist nginx -t
```

### 重置部署
```bash
# 完全重置
docker-compose -f docker-compose.nat.yml down -v
docker system prune -f
./deploy.sh deploy-haproxy