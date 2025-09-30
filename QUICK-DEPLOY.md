# 快速部署HAProxy+NAT模式

## 一键部署命令

```bash
# 在Linux服务器上执行
./deploy.sh

# 然后选择：
# 2. NAT模式 (host) - 适用于NAT环境/内网映射
# 系统会自动启用HAProxy+PROXY Protocol
```

## 部署流程说明

选择NAT模式后，deploy.sh会自动完成以下操作：

1. **自动启用HAProxy** - 检测NAT模式，自动设置HAPROXY_ENABLED=true
2. **停止现有服务** - 清理所有相关容器
3. **检查配置文件** - 验证HAProxy和nginx配置文件
4. **配置环境变量** - 设置端口和PROXY Protocol参数
5. **检查端口冲突** - 确保端口可用
6. **构建镜像** - 重新构建最新配置
7. **启动服务** - 启动HAProxy和MTProxy服务
8. **等待就绪** - 等待服务完全启动
9. **验证部署** - 检查端口监听和配置正确性
10. **显示结果** - 提供管理命令和验证方法

## 端口配置

### 对外端口（客户端连接）
- **14202**: MTProxy客户端连接端口
- **8787**: Web管理界面端口

### 内部端口（不对外暴露）
- **445**: PROXY Protocol专用端口（HAProxy → nginx）
- **444**: MTProxy实际运行端口
- **8080**: API内部端口

## 网络流向

```
客户端 → HAProxy:14202 → nginx:445 (PROXY Protocol) → MTProxy:444
管理员 → HAProxy:8787 → nginx内部 → Web界面
```

## 验证部署成功

### 1. 检查端口监听
```bash
netstat -tlnp | grep -E ":(14202|8787) "
# 应该看到HAProxy进程监听这两个端口
```

### 2. 检查容器状态
```bash
docker-compose -f docker-compose.nat.yml ps
# 应该看到haproxy和mtproxy-whitelist都是Up状态
```

### 3. 验证真实IP获取
```bash
docker exec mtproxy-whitelist tail -f /var/log/nginx/proxy_protocol_access.log
# 应该显示真实客户端IP，而不是172.16.5.6
```

### 4. 测试HAProxy配置
```bash
docker exec mtproxy-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
# 应该显示配置正确
```

## 管理命令

```bash
# 查看日志
docker-compose -f docker-compose.nat.yml logs -f

# 查看IP获取日志
docker exec mtproxy-whitelist tail -f /var/log/nginx/proxy_protocol_access.log

# 测试HAProxy模式
./deploy.sh test-haproxy

# 停止服务
docker-compose -f docker-compose.nat.yml down

# 重启服务
docker-compose -f docker-compose.nat.yml restart
```

## 故障排除

如果部署后仍然获取内网IP，请检查：

1. **HAProxy是否正常运行**
   ```bash
   docker ps | grep haproxy
   netstat -tlnp | grep 14202
   ```

2. **客户端是否连接正确端口**
   - 确保连接14202端口（HAProxy），不是直连nginx端口

3. **PROXY Protocol配置**
   ```bash
   docker exec mtproxy-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
   docker exec mtproxy-whitelist nginx -t
   ```

4. **重新部署**
   ```bash
   ./deploy.sh
   # 选择 "2. NAT模式"