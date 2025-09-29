# MTProxy 白名单系统 - NAT 模式使用指南

## 🎯 快速开始

### 1. 部署系统

```bash
# 克隆项目
git clone https://github.com/zxzx412/mtproxy-whitelist.git
cd mtproxy-whitelist

# 运行部署脚本
sudo ./deploy.sh
```

在部署过程中：
- 选择 **NAT模式 (选项 2)** 以启用 IP 获取增强功能
- 配置端口和其他参数
- 系统将自动启用 PROXY Protocol 和 IP 获取优化

### 2. 验证 NAT IP 获取功能

```bash
# 测试 NAT IP 获取
sudo ./deploy.sh test-nat-ip

# 运行诊断
sudo ./deploy.sh diagnose-ip
```

### 3. 管理和监控

```bash
# 查看服务状态
mtproxy-whitelist status

# 实时监控客户端 IP
mtproxy-whitelist monitor-ips

# 查看 IP 统计
mtproxy-whitelist ip-stats

# 如果遇到 IP 获取问题
mtproxy-whitelist fix-nat-ip
```

## 🔧 NAT 模式特性

### ✅ 自动启用的功能

1. **PROXY Protocol 支持**
   - 自动配置 nginx 支持 PROXY Protocol
   - 获取真实客户端 IP 地址
   - 支持多层代理环境

2. **智能 IP 获取**
   - 多层回退机制：PROXY Protocol → X-Forwarded-For → remote_addr
   - 自动过滤内网 IP
   - 实时 IP 监控和统计

3. **增强诊断工具**
   - 自动安装 IP 监控脚本
   - 实时连接日志分析
   - 网络环境检测

### 🚀 部署架构

**NAT 模式流程：**
```
客户端 → NAT转发 → 服务器端口 → nginx(PROXY Protocol) → MTProxy
```

**IP 获取流程：**
```
1. 检测 PROXY Protocol 头部 → 获取真实 IP
2. 如果没有，检查 X-Forwarded-For → 获取代理传递的 IP  
3. 最后回退到 remote_addr → 获取直连 IP
```

## 📊 监控和诊断

### 实时监控

```bash
# 实时查看客户端连接
mtproxy-whitelist monitor-ips

# 查看连接统计
mtproxy-whitelist ip-stats

# 查看服务日志
mtproxy-whitelist logs
```

### 故障诊断

```bash
# 完整诊断报告
mtproxy-whitelist diagnose-ip

# 如果 IP 获取异常
mtproxy-whitelist fix-nat-ip

# 重新启用 PROXY Protocol
sudo ./deploy.sh enable-proxy-protocol
```

## ⚠️ 常见问题

### 1. 白名单显示内网 IP (172.x.x.x)

**原因：** PROXY Protocol 未正确配置或上游代理未发送 PROXY 头部

**解决：**
```bash
# 重新配置 PROXY Protocol
sudo ./deploy.sh enable-proxy-protocol

# 检查诊断信息
mtproxy-whitelist diagnose-ip
```

### 2. 客户端无法连接

**原因：** 客户端 IP 未在白名单中

**解决：**
```bash
# 查看客户端 IP
mtproxy-whitelist monitor-ips

# 通过 Web 界面添加 IP 到白名单
# 访问: http://服务器IP:Web端口
```

### 3. IP 获取不准确

**原因：** 网络环境复杂，需要调整配置

**解决：**
```bash
# 运行修复脚本
mtproxy-whitelist fix-nat-ip

# 查看详细诊断
mtproxy-whitelist diagnose-ip
```

## 🔐 安全建议

1. **定期检查白名单**
   - 定期审查白名单中的 IP 地址
   - 移除不再需要的 IP

2. **监控异常连接**
   - 使用 `mtproxy-whitelist monitor-ips` 监控连接
   - 注意异常的 IP 访问模式

3. **保持系统更新**
   - 定期运行 `mtproxy-whitelist update`
   - 关注项目更新和安全补丁

## 📞 技术支持

如果遇到问题：

1. 首先运行诊断：`mtproxy-whitelist diagnose-ip`
2. 查看详细日志：`mtproxy-whitelist logs`
3. 参考完整文档：`NAT-IP-ENHANCEMENT.md`
4. 提交 Issue：[GitHub Issues](https://github.com/zxzx412/mtproxy-whitelist/issues)

---

🌟 **NAT 模式让您在复杂网络环境下也能准确获取客户端 IP！**