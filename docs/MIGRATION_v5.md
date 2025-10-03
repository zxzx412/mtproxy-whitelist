# MTProxy 白名单系统 v5.0 迁移指南

## 概述

v5.0进行了重大架构重构，主要改进：
- ✅ 端口变量标准化（EXTERNAL_*, INTERNAL_*, BACKEND_*）
- ✅ 配置策略模式（entrypoint.sh复杂度从15降至<5）
- ✅ Supervisor进程管理（MTProxy崩溃恢复从30秒降至<5秒）
- ✅ 三种部署模式明确化（bridge/nat-direct/nat-haproxy）
- ✅ 端口445改为14445（避免Windows SMB冲突）

**向后兼容性**: 🎯 100%保证，所有旧配置继续工作。

---

## 快速迁移（3分钟）

### 步骤1：备份配置
```bash
cp .env .env.v4.backup
docker-compose down
```

### 步骤2：拉取最新代码
```bash
git checkout refactor/nat-mode
git pull
```

### 步骤3：重新启动
```bash
docker-compose up -d
```

**完成！** 系统已升级到v5.0，所有旧配置自动兼容。

---

## 详细变更说明

### 1. 端口变量重命名

#### 为什么重命名？
v4.0的变量名语义模糊（如MTPROXY_PORT在不同上下文含义不同），导致配置混乱。

#### 新命名规范
- **EXTERNAL_*** - 外部可访问端口（客户端连接）
- **INTERNAL_*** - 内部通信端口（容器间）
- **BACKEND_*** - 后端服务端口（实际监听）

#### 完整映射表

| v4.0变量 | v5.0变量 | 默认值 | 兼容性 |
|---------|---------|--------|--------|
| `MTPROXY_PORT` | `EXTERNAL_PROXY_PORT` | 14202 | ✅ 保留别名 |
| `WEB_PORT` | `EXTERNAL_WEB_PORT` | 8989 | ✅ 保留别名 |
| `PROXY_PROTOCOL_PORT=445` | `INTERNAL_PROXY_PROTOCOL_PORT` | 14445 | ⚠️ 自动改为14445 |
| `INTERNAL_MTPROXY_PORT` | `BACKEND_MTPROXY_PORT` | 444 | ✅ 保留别名 |

#### 示例：更新.env（可选）
```bash
# v4.0配置（仍然有效）
MTPROXY_PORT=14202
WEB_PORT=8989

# v5.0推荐配置（可选更新）
EXTERNAL_PROXY_PORT=14202
EXTERNAL_WEB_PORT=8989
```

**无需修改**：系统自动识别旧变量名。

---

### 2. 端口445废弃说明

**为什么废弃445端口？**
- 445是Windows SMB端口，容易冲突
- 许多NAT网关和防火墙默认封禁445端口

**自动迁移**：
- 检测到`PROXY_PROTOCOL_PORT=445`会自动改为14445
- 显示警告但不中断服务
- 建议手动更新配置为`INTERNAL_PROXY_PROTOCOL_PORT=14445`

---

### 3. 部署模式标准化

#### v4.0配置方式（仍然有效）
```bash
# Bridge模式
NAT_MODE=false

# NAT+HAProxy模式
NAT_MODE=true
HAPROXY_ENABLED=true

# NAT直连模式（v4.0不支持）
NAT_MODE=true
HAPROXY_ENABLED=false
```

#### v5.0推荐配置方式
```bash
# Bridge模式（默认）
DEPLOYMENT_MODE=bridge

# NAT+HAProxy模式（推荐NAT环境）
DEPLOYMENT_MODE=nat-haproxy

# NAT直连模式（新增，简化版）
DEPLOYMENT_MODE=nat-direct
```

**自动转换**：旧的`NAT_MODE`会自动转换为`DEPLOYMENT_MODE`。

---

### 4. 新增功能

#### NAT直连模式
不需要HAProxy层，Nginx直接监听外部端口。

**适用场景**：
- 不需要PROXY Protocol
- 追求极致性能（减少一层跳转）
- 简化架构

**使用方法**：
```bash
# 方法1：环境变量
export DEPLOYMENT_MODE=nat-direct
docker-compose -f docker-compose.nat-direct.yml up -d

# 方法2：管理脚本
USE_HAPROXY=false ./docker-compose-nat.sh up
```

#### Supervisor进程管理
**优势**：
- MTProxy崩溃自动重启（<5秒，原30秒）
- 优雅停止（SIGTERM）
- 统一日志管理
- 进程依赖控制

**无需配置**：自动启用，向后兼容原Bash启动方式。

#### 增强健康检查
```bash
# 多层次健康检查
docker exec mtproxy-whitelist /usr/local/bin/health-check.sh

# L1: 进程检查
# L2: 端口监听检查
# L3: 服务响应检查
```

---

## 启动时的警告信息

### 警告1：废弃变量警告
```
⚠️  警告: MTPROXY_PORT已废弃，请使用EXTERNAL_PROXY_PORT
```

**原因**：使用了v4.0变量名
**影响**：无，系统仍正常工作
**解决**：可选更新.env使用新变量名

### 警告2：端口445警告
```
⚠️  警告: 端口445已废弃（Windows SMB冲突），自动改用14445
```

**原因**：`PROXY_PROTOCOL_PORT=445`
**影响**：端口自动改为14445
**解决**：更新.env设置`INTERNAL_PROXY_PROTOCOL_PORT=14445`

### 警告3：NAT_MODE转换警告
```
⚠️  警告: NAT_MODE已废弃，自动转换为DEPLOYMENT_MODE=nat-haproxy
```

**原因**：使用旧的`NAT_MODE`变量
**影响**：自动转换，无功能影响
**解决**：可选更新为`DEPLOYMENT_MODE`

---

## 故障排查

### 问题1：找不到策略文件
```
❌ 错误：策略文件不存在 /etc/mtproxy/strategies/bridge.conf
```

**原因**：Docker镜像未更新
**解决**：
```bash
docker-compose build --no-cache
docker-compose up -d
```

### 问题2：Supervisor启动失败
```
❌ Supervisor进程已停止
```

**原因**：配置文件格式错误或依赖缺失
**解决**：
```bash
# 查看Supervisor日志
docker-compose logs mtproxy-whitelist | grep supervisor

# 回退到传统启动模式（临时）
docker-compose exec mtproxy-whitelist rm /etc/supervisor/supervisord.conf
docker-compose restart
```

### 问题3：健康检查持续失败
```
unhealthy: health check failed
```

**原因**：服务启动时间过长或端口配置错误
**解决**：
```bash
# 检查服务状态
docker-compose exec mtproxy-whitelist /usr/local/bin/health-check.sh

# 查看详细日志
docker-compose logs mtproxy-whitelist
```

---

## 回滚到v4.0

如果遇到严重问题，可以快速回滚：

```bash
# 停止服务
docker-compose down

# 回滚代码
git checkout main

# 恢复配置
cp .env.v4.backup .env

# 重新启动
docker-compose up -d
```

---

## 配置更新建议

虽然v5.0完全向后兼容，但建议逐步更新配置以获得更好的可维护性：

### 优先级P0（推荐立即更新）
```bash
# 更新端口445（避免冲突）
INTERNAL_PROXY_PROTOCOL_PORT=14445
```

### 优先级P1（建议1个月内更新）
```bash
# 更新部署模式变量
DEPLOYMENT_MODE=bridge  # 或 nat-haproxy / nat-direct
```

### 优先级P2（建议3个月内更新）
```bash
# 更新所有端口变量名
EXTERNAL_PROXY_PORT=14202
EXTERNAL_WEB_PORT=8989
INTERNAL_PROXY_PROTOCOL_PORT=14445
BACKEND_MTPROXY_PORT=444
```

---

## v6.0预告（预计6个月后）

以下特性将在v6.0**移除**：
- ❌ `MTPROXY_PORT`别名
- ❌ `WEB_PORT`别名
- ❌ `NAT_MODE`变量
- ❌ 端口445自动转换

**请在v6.0发布前完成配置更新。**

---

## 验证清单

升级后请验证以下功能：

- [ ] 容器启动成功（`docker-compose ps`）
- [ ] Web管理界面可访问（http://服务器IP:WEB_PORT）
- [ ] API健康检查通过（`curl http://localhost:8989/api/health`）
- [ ] 白名单功能正常（添加/删除IP）
- [ ] MTProxy连接正常（Telegram客户端测试）
- [ ] 日志正常输出（`docker-compose logs`）

---

## 获取帮助

- **架构文档**: `docs/ARCHITECTURE_v5.md`
- **端口说明**: `docs/PORT_ALLOCATION.md`
- **部署模式对比**: `docs/DEPLOYMENT_MODES.md`
- **快速参考**: `docs/QUICK_REFERENCE.md`
- **问题反馈**: [GitHub Issues](https://github.com/zxzx412/mtproxy-whitelist/issues)

---

**升级愉快！如有问题，请参考故障排查部分或提交Issue。** 🚀
