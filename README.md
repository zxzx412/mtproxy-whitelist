# MTProxy 白名单系统 v4.0

🛡️ 基于 nginx stream 模块的 MTProxy 白名单代理系统，支持通过 Web 界面动态管理 IP 白名单。

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

```
Internet ──┐
           │
           ▼
    ┌─────────────┐
    │   Nginx     │ (Port 443)
    │   Stream    │
    │  (白名单检查) │
    └─────┬───────┘
          │ (仅白名单IP通过)
          ▼
    ┌─────────────┐
    │  MTProxy    │ (127.0.0.1:444)
    │   服务      │
    └─────────────┘

Web管理端口:
    ┌─────────────┐
    │   Nginx     │ (Port 8888)
    │  HTTP代理   │
    └─────┬───────┘
          │
          ▼
    ┌─────────────┐    ┌─────────────┐
    │  Web界面    │    │  Flask API  │ (127.0.0.1:8080)
    │  (静态文件)  │    │   服务      │
    └─────────────┘    └─────────────┘
```

## 🚀 快速开始

### 方法一：一键部署（推荐）

```bash
# 下载项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist


# 运行一键部署脚本
sudo ./deploy.sh
```

### 方法二：Docker Compose 部署

```bash
# 克隆项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist
cp .env.example .env
# 启动服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```


## 📋 系统要求

- **操作系统**: Linux (Ubuntu 18.04+, CentOS 7+, Debian 9+, Alpine Linux)
- **内存**: 最低 512MB RAM
- **磁盘**: 最低 1GB 可用空间
- **网络**: 公网 IP 地址
- **端口**: 443 (MTProxy), 8888 (Web 管理) - 可在部署时自定义

## 🔧 配置说明

### 环境变量

| 变量名 | 描述 | 默认值 |
|--------|------|--------|
| `MTPROXY_DOMAIN` | 伪装域名 | `azure.microsoft.com` |
| `MTPROXY_TAG` | 推广 TAG | 空 |
| `SECRET_KEY` | Flask 密钥 | 自动生成 |
| `JWT_EXPIRATION_HOURS` | JWT 过期时间(小时) | `24` |
| `ADMIN_PASSWORD` | 管理员密码 | `admin123` |
| `MTPROXY_PORT` | MTProxy代理端口 | `443` |
| `WEB_PORT` | Web管理界面端口 | `8888` |

### 端口配置

> 💡 **新功能**: 支持在部署时自定义端口，避免端口冲突

**默认端口**:
- **443**: MTProxy 代理端口（对外，可自定义）
- **444**: MTProxy 内部端口
- **8888**: Web 管理界面端口（可自定义）
- **8080**: API 服务端口（内部）

**推荐端口选择**:
- MTProxy: 443, 2053, 2083, 2087, 2096, 8443
- Web管理: 8888, 9999, 8080, 3000-9000

## 🌐 Web 管理界面

访问 `http://YOUR_SERVER_IP:8888` 打开 Web 管理界面。

### 默认登录信息
- **用户名**: `admin`
- **密码**: `admin123` (建议修改)

### 功能特性
- 📊 实时统计显示
- ➕ 添加/删除 IP 地址
- 🔍 搜索和过滤功能
- 📥 导出白名单配置
- 📱 响应式设计

## 📱 Telegram 连接

部署完成后，使用以下格式的链接连接 Telegram：

```
https://t.me/proxy?server=YOUR_SERVER_IP&port=443&secret=YOUR_SECRET
tg://proxy?server=YOUR_SERVER_IP&port=443&secret=YOUR_SECRET
```

> ⚠️ **重要**: 只有添加到白名单的 IP 地址才能连接代理服务！

## 🛠️ 管理命令

部署完成后，可以使用以下命令管理服务：

```bash
# 查看服务状态
mtproxy-whitelist status

# 启动服务
mtproxy-whitelist start

# 停止服务
mtproxy-whitelist stop

# 重启服务
mtproxy-whitelist restart

# 查看日志
mtproxy-whitelist logs

# 更新服务
mtproxy-whitelist update

# 显示访问信息
mtproxy-whitelist info

# 显示端口配置
mtproxy-whitelist ports

# 系统诊断（排查问题）
bash diagnose.sh
```

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
2. **限制管理端口**: 建议通过防火墙限制 8888 端口的访问
3. **定期备份**: 定期备份白名单配置和数据库
4. **监控日志**: 定期检查访问日志，发现异常行为
5. **更新系统**: 保持系统和依赖项目的最新版本

## 🐛 故障排除

### 常见问题

#### 1. 无法访问 Web 管理界面
```bash
# 检查服务状态
docker-compose ps

# 检查端口监听
ss -tuln | grep 8888

# 查看日志
docker-compose logs mtproxy-whitelist
```

#### 2. MTProxy 连接失败
- 确认 IP 已添加到白名单
- 检查防火墙设置
- 验证代理配置参数

#### 3. 白名单不生效
```bash
# 检查 nginx 配置
docker-compose exec mtproxy-whitelist nginx -t

# 重载 nginx 配置
docker-compose exec mtproxy-whitelist nginx -s reload
```

### 日志位置

- **应用日志**: `/var/log/supervisor/`
- **Nginx 日志**: `/var/log/nginx/`
- **系统日志**: `docker-compose logs`

## 📁 项目结构

```
mtproxy-whitelist/
├── README.md                 # 项目说明文档
├── deploy.sh                 # 一键部署脚本
├── docker/                   # Docker 配置文件
│   ├── Dockerfile           # Docker 镜像定义
│   ├── docker-compose.yml   # 容器编排配置
│   ├── supervisord.conf     # 进程管理配置
│   └── entrypoint.sh        # 容器启动脚本
├── nginx/                    # Nginx 配置文件
│   ├── nginx.conf           # 主配置文件
│   ├── stream.conf          # Stream 模块配置
│   ├── whitelist.conf       # 白名单配置
│   └── reload_nginx.sh      # Nginx 重载脚本
├── web/                      # Web 前端文件
│   ├── index.html           # 主页面
│   ├── styles.css           # 样式文件
│   └── app.js               # JavaScript 逻辑
├── api/                      # Flask API 服务
│   ├── app.py               # 主应用文件
│   ├── requirements.txt     # Python 依赖
│   └── start.sh             # 启动脚本
├── scripts/                  # 管理脚本
│   ├── mtproxy_enhanced.sh  # 原始脚本
│   └── mtproxy_whitelist.sh # 白名单增强脚本
└── docs/                     # 文档目录
    ├── architecture.md      # 架构文档
    ├── api.md               # API 文档
    └── troubleshooting.md   # 故障排除指南
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

---

📞 **技术支持**: 如遇问题，请提交 [Issue](https://github.com/zxzx412/mtproxy-whitelist/issues)

🌟 **如果这个项目对您有帮助，请给个 Star！**
