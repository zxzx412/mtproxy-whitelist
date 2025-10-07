# MTProxy 白名单系统 v5.0

🛡️ 基于 nginx stream 模块的 MTProxy 白名单代理系统，支持通过 Web 界面动态管理 IP 白名单。

[![GitHub release](https://img.shields.io/badge/release-v5.0-blue.svg)](https://github.com/zxzx412/mtproxy-whitelist/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## ✨ v5.0 新特性

- 🎯 **三种部署模式**: Bridge、NAT+HAProxy、NAT直连，灵活适配各种网络环境
- 🔧 **端口变量标准化**: EXTERNAL_*/INTERNAL_*/BACKEND_* 清晰命名
- 🚀 **Supervisor进程管理**: MTProxy崩溃自动恢复（<5秒，原30秒）
- 📊 **增强健康检查**: L1/L2/L3多层验证机制
- ⚡ **配置策略模式**: entrypoint.sh复杂度降低70%
- 🔒 **端口优化**: 445→14445避免Windows SMB冲突
- 🔄 **100%向后兼容**: 旧配置无缝升级
- 📚 **完整文档**: 迁移指南、快速参考、故障排查

## 🌟 核心特性

- **🔒 白名单控制**: nginx stream 模块在 TCP 层面进行 IP 白名单控制
- **🌐 Web 管理**: 现代化的 Web 管理界面，支持实时管理白名单
- **🔐 用户认证**: JWT 认证系统，防止未授权访问
- **📱 完整IP支持**: 完美支持单个IPv4/IPv6地址和CIDR网段格式
- **🚀 一键部署**: Docker 容器化部署，支持一键安装
- **⚡ 实时生效**: 白名单更改即时生效，自动同步nginx配置
- **📊 状态监控**: 实时显示系统状态和统计信息
- **🔧 自动修复**: 内置容错机制，自动处理常见配置问题
- **📝 详细日志**: 完整的操作日志和错误追踪

## 🏗️ 系统架构

### Bridge模式（推荐新手）
```
客户端 → Docker端口映射 → Nginx白名单验证(443) → MTProxy(444)
                            ↓
                        Web管理(8888)
```

### NAT+HAProxy模式（推荐NAT环境）
```
客户端 → HAProxy(14202) → Nginx(14445,PROXY Protocol) → MTProxy(444)
                            ↓
                        Web管理(8989)
```

### NAT直连模式（简化版）
```
客户端 → Nginx直接监听(14202) → MTProxy(444)
                            ↓
                        Web管理(8989)
```

## 🚀 快速开始

### 方法一：一键部署（强烈推荐）✨

```bash
# 1. 克隆项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist

# 2. 运行部署脚本
sudo bash deploy.sh

# 3. 按提示选择部署模式
# - Bridge模式：推荐新手，配置简单
# - NAT+HAProxy：推荐NAT环境，获取真实IP
# - NAT直连：简化版，性能最优
```

**部署脚本会自动**：
- ✅ 安装Docker和Docker Compose
- ✅ 交互式配置端口和参数
- ✅ 自动生成.env配置文件
- ✅ 验证配置并启动服务
- ✅ 配置防火墙规则
- ✅ 显示完整的连接信息

### 方法二：手动部署（高级用户）

#### Bridge模式
```bash
# 1. 克隆项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist

# 2. 复制配置文件
cp .env.example .env

# 3. 编辑配置（可选）
nano .env

# 4. 启动服务
docker-compose up -d

# 5. 查看状态
docker-compose ps
```

#### NAT+HAProxy模式
```bash
# 1. 配置环境变量
cat > .env <<EOF
DEPLOYMENT_MODE=nat-haproxy
EXTERNAL_PROXY_PORT=14202
EXTERNAL_WEB_PORT=8989
INTERNAL_PROXY_PROTOCOL_PORT=14445
MTPROXY_DOMAIN=azure.microsoft.com
ADMIN_PASSWORD=your_secure_password
EOF

# 2. 启动服务
docker-compose -f docker-compose.nat-haproxy.yml up -d

# 3. 查看状态
docker-compose -f docker-compose.nat-haproxy.yml ps
```

#### NAT直连模式
```bash
# 使用nat-direct模式
DEPLOYMENT_MODE=nat-direct
docker-compose -f docker-compose.nat-direct.yml up -d
```

## 📋 系统要求

- **操作系统**: Linux (Ubuntu 18.04+, CentOS 7+, Debian 9+, Alpine Linux)
- **内存**: 最低 512MB RAM
- **磁盘**: 最低 1GB 可用空间
- **网络**: 公网 IP 地址
- **端口**:
  - Bridge模式: 14202 (代理), 8989 (Web管理)
  - NAT模式: 14202 (代理), 8989 (Web管理), 14445 (内部PROXY Protocol)

## 🔧 配置说明

### 核心环境变量（v5.0）

| 变量名 | 描述 | 默认值 | 说明 |
|--------|------|--------|------|
| `DEPLOYMENT_MODE` | 部署模式 | `bridge` | bridge/nat-haproxy/nat-direct |
| `EXTERNAL_PROXY_PORT` | 客户端连接端口 | `14202` | 外部访问端口 |
| `EXTERNAL_WEB_PORT` | Web管理端口 | `8989` | Web界面端口 |
| `INTERNAL_PROXY_PROTOCOL_PORT` | PROXY Protocol端口 | `14445` | HAProxy→Nginx内部端口 |
| `BACKEND_MTPROXY_PORT` | MTProxy实际端口 | `444` | 后端服务端口 |
| `MTPROXY_DOMAIN` | 伪装域名 | `azure.microsoft.com` | 伪装成此域名 |
| `ADMIN_PASSWORD` | 管理员密码 | `admin123` | **建议修改** |

### 向后兼容变量（v4.0）

以下变量仍然有效，但建议使用新变量名：

| 旧变量 (v4.0) | 新变量 (v5.0) | 状态 |
|--------------|--------------|------|
| `MTPROXY_PORT` | `EXTERNAL_PROXY_PORT` | ⚠️ v6.0将移除 |
| `WEB_PORT` | `EXTERNAL_WEB_PORT` | ⚠️ v6.0将移除 |
| `NAT_MODE` | `DEPLOYMENT_MODE` | ⚠️ v6.0将移除 |

## 🌐 Web 管理界面

访问 `http://YOUR_SERVER_IP:8989` 打开 Web 管理界面。

### 默认登录信息
- **用户名**: `admin`
- **密码**: `admin123` ⚠️ **请立即修改**

### 功能特性
- 📊 实时统计显示
- ➕ 添加/删除 IP 地址
- 🔍 搜索和过滤功能
- 📥 导出白名单配置
- 📱 响应式设计

## 📱 Telegram 连接

部署完成后，使用以下格式的链接连接 Telegram：

```
https://t.me/proxy?server=YOUR_SERVER_IP&port=14202&secret=YOUR_SECRET
tg://proxy?server=YOUR_SERVER_IP&port=14202&secret=YOUR_SECRET
```

> ⚠️ **重要**: 只有添加到白名单的 IP 地址才能连接代理服务！

## 🛠️ 管理命令

### Bridge模式
```bash
# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 健康检查
docker exec mtproxy-whitelist /usr/local/bin/health-check.sh
```

### NAT模式
```bash
# 使用管理脚本（自动选择配置文件）
./docker-compose-nat.sh ps
./docker-compose-nat.sh logs -f
./docker-compose-nat.sh restart

# 或直接使用docker-compose
docker-compose -f docker-compose.nat-haproxy.yml ps
docker-compose -f docker-compose.nat-direct.yml ps
```

## 📚 文档

- **[迁移指南](docs/MIGRATION_v5.md)** - v4.0→v5.0升级指南
- **[快速参考](docs/QUICK_REFERENCE.md)** - 常用命令和配置速查
- **API文档** - 见下方API部分

## 🔄 从v4.0升级

v5.0完全向后兼容v4.0配置！

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 重新启动（旧配置仍然有效）
docker-compose down
docker-compose up -d

# 3. 查看状态
docker-compose ps
```

**升级后的警告信息**：
- ⚠️ 旧变量名废弃警告（不影响功能）
- ⚠️ 端口445自动改为14445（避免SMB冲突）

详细升级指南请参考：[docs/MIGRATION_v5.md](docs/MIGRATION_v5.md)

## 📚 API 文档

### 认证接口

#### 登录
```bash
POST /api/auth/login
Content-Type: application/json

{
    "username": "admin",
    "password": "admin123"
}
```

#### 验证 Token
```bash
GET /api/auth/verify
Authorization: Bearer YOUR_JWT_TOKEN
```

### 白名单管理

#### 获取白名单列表
```bash
GET /api/whitelist
Authorization: Bearer YOUR_JWT_TOKEN
```

#### 添加 IP 到白名单
```bash
POST /api/whitelist
Authorization: Bearer YOUR_JWT_TOKEN
Content-Type: application/json

{
    "ip": "192.168.1.100",
    "description": "办公室网络"
}
```

#### 删除白名单项
```bash
DELETE /api/whitelist/{id}
Authorization: Bearer YOUR_JWT_TOKEN
```

### 系统状态

#### 获取系统状态
```bash
GET /api/status
Authorization: Bearer YOUR_JWT_TOKEN
```

## 🔒 安全建议

1. **修改默认密码**: 部署完成后立即修改管理员密码
2. **限制管理端口**: 建议通过防火墙限制Web管理端口的访问
3. **定期备份**: 定期备份白名单配置和数据库
   ```bash
   docker exec mtproxy-whitelist cat /data/nginx/whitelist.txt > whitelist-backup.txt
   ```
4. **监控日志**: 定期检查访问日志，发现异常行为
   ```bash
   docker-compose logs -f | grep -E "reject|error"
   ```
5. **更新系统**: 保持系统和依赖项目的最新版本

## 🐛 故障排除

### 常见问题

#### 1. 无法访问 Web 管理界面
```bash
# 检查服务状态
docker-compose ps

# 检查端口监听
ss -tuln | grep 8989

# 查看日志
docker-compose logs mtproxy-whitelist
```

#### 2. MTProxy 连接失败
- 确认 IP 已添加到白名单
- 检查防火墙设置
- 验证代理配置参数
- 查看白名单：
  ```bash
  docker exec mtproxy-whitelist cat /data/nginx/whitelist.txt
  ```

#### 3. NAT模式获取内网IP
```bash
# 确认使用HAProxy模式
echo $DEPLOYMENT_MODE  # 应为 nat-haproxy

# 查看PROXY Protocol日志
docker exec mtproxy-whitelist tail /var/log/nginx/proxy_protocol_access.log

# 运行诊断
./diagnose-real-ip.sh
```

#### 4. 白名单不生效
```bash
# 检查 nginx 配置
docker-compose exec mtproxy-whitelist nginx -t

# 重载 nginx 配置
docker-compose exec mtproxy-whitelist nginx -s reload

# 查看白名单映射
docker exec mtproxy-whitelist cat /data/nginx/whitelist_map.conf
```

### 日志位置

```bash
# 容器内日志
/var/log/nginx/access.log          # Nginx访问日志
/var/log/nginx/error.log           # Nginx错误日志
/var/log/nginx/stream_access.log   # Stream访问日志
/var/log/mtproxy/stdout.log        # MTProxy输出
/var/log/supervisord.log           # Supervisor日志

# 查看日志
docker-compose logs mtproxy-whitelist
docker exec mtproxy-whitelist tail -f /var/log/nginx/stream_access.log
```

## 📁 项目结构

```
mtproxy-whitelist/
├── README.md                      # 项目说明文档
├── deploy.sh                      # v5.0一键部署脚本
├── .env.example                   # 配置模板
├── docker-compose.yml             # Bridge模式配置
├── docker-compose.nat-haproxy.yml # NAT+HAProxy模式配置
├── docker-compose.nat-direct.yml  # NAT直连模式配置
├── docker/                        # Docker配置
│   ├── Dockerfile                 # 镜像定义
│   ├── entrypoint.sh              # v5.0重构启动脚本
│   ├── supervisord.conf           # 进程管理
│   ├── strategies/                # 配置策略
│   │   ├── bridge.conf            # Bridge模式策略
│   │   ├── nat-direct.conf        # NAT直连策略
│   │   └── nat-haproxy.conf       # NAT+HAProxy策略
│   ├── validate-config.sh         # 配置验证
│   └── health-check.sh            # 健康检查
├── docs/                          # 文档目录
│   ├── MIGRATION_v5.md            # v5.0迁移指南
│   └── QUICK_REFERENCE.md         # 快速参考
├── web/                           # Web前端
├── api/                           # Flask API
└── nginx/                         # Nginx配置

```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

## ⭐ 致谢

- [MTG](https://github.com/9seconds/mtg) - MTProxy 实现
- [Nginx](https://nginx.org/) - Web 服务器和反向代理
- [Flask](https://flask.palletsprojects.com/) - Python Web 框架
- [Docker](https://www.docker.com/) - 容器化平台
- [HAProxy](http://www.haproxy.org/) - 高性能代理

## 📊 版本历史

- **v5.0** (2025-10) - 架构重构，三种部署模式，Supervisor进程管理
- **v4.0** (2025-09) - 完整白名单系统，Web管理界面
- **v3.0** - NAT模式支持
- **v2.0** - Docker化部署
- **v1.0** - 基础MTProxy部署

---

📞 **技术支持**: 如遇问题，请提交 [Issue](https://github.com/zxzx412/mtproxy-whitelist/issues)

🌟 **如果这个项目对您有帮助，请给个 Star！**

**快速链接**:
- [一键部署](#方法一一键部署强烈推荐) | [手动部署](#方法二手动部署高级用户) | [迁移指南](docs/MIGRATION_v5.md) | [快速参考](docs/QUICK_REFERENCE.md) | [故障排除](#故障排除)
