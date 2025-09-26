// MTProxy 白名单管理系统 JavaScript

class MTProxyManager {
    constructor() {
        this.apiBase = '/api';
        this.token = localStorage.getItem('authToken');
        this.whitelist = [];
        this.currentUser = localStorage.getItem('currentUser') || 'admin';
        this.deleteItemId = null;
        this.connections = [];
        this.blockedIPs = [];
        this.connectionStats = {};
        this.monitoringEnabled = true;
        this.monitorInterval = null;
        this.currentTab = 'recent';
        
        this.init();
    }
    
    async init() {
        this.setupEventListeners();
        await this.checkAuth();
        this.hideLoading();
    }
    
    setupEventListeners() {
        // 登录相关
        document.getElementById('login-form').addEventListener('submit', (e) => this.handleLogin(e));
        document.getElementById('logout-btn').addEventListener('click', () => this.handleLogout());
        
        // 白名单管理
        document.getElementById('add-ip-btn').addEventListener('click', () => this.showAddForm());
        document.getElementById('cancel-add-btn').addEventListener('click', () => this.hideAddForm());
        document.getElementById('save-ip-btn').addEventListener('click', () => this.handleAddIP());
        document.getElementById('refresh-btn').addEventListener('click', () => this.loadWhitelist());
        document.getElementById('export-btn').addEventListener('click', () => this.exportWhitelist());
        
        // 搜索和过滤
        document.getElementById('search-input').addEventListener('input', (e) => this.handleSearch(e.target.value));
        document.getElementById('filter-type').addEventListener('change', (e) => this.handleFilter(e.target.value));
        
        // 删除确认
        document.getElementById('confirm-delete-btn').addEventListener('click', () => this.confirmDelete());
        document.getElementById('cancel-delete-btn').addEventListener('click', () => this.hideDeleteModal());
        
        // 连接监控
        document.getElementById('toggle-monitor-btn').addEventListener('click', () => this.toggleMonitoring());
        document.getElementById('clear-logs-btn').addEventListener('click', () => this.clearConnectionLogs());
        
        // 监控标签切换
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => this.switchTab(e.target.dataset.tab));
        });
        
        // ESC 键关闭模态框
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.hideDeleteModal();
                this.hideAddForm();
            }
        });
    }
    
    async checkAuth() {
        if (!this.token) {
            this.showLogin();
            return;
        }
        
        try {
            const response = await this.apiCall('GET', '/auth/verify');
            if (response.success) {
                this.showMainInterface();
                await this.loadWhitelist();
                this.startStatusCheck();
                this.startConnectionMonitoring();
            } else {
                this.showLogin();
            }
        } catch (error) {
            console.error('Auth check failed:', error);
            this.showLogin();
        }
    }
    
    async handleLogin(e) {
        e.preventDefault();
        
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const errorDiv = document.getElementById('login-error');
        
        try {
            const response = await this.apiCall('POST', '/auth/login', {
                username,
                password
            });
            
            if (response.success) {
                this.token = response.token;
                this.currentUser = response.user || username;
                localStorage.setItem('authToken', this.token);
                localStorage.setItem('currentUser', this.currentUser);
                
                this.showMainInterface();
                await this.loadWhitelist();
                this.startStatusCheck();
                this.startConnectionMonitoring();
                this.showNotification('登录成功', 'success');
            } else {
                errorDiv.textContent = response.message || '登录失败';
                errorDiv.classList.remove('hidden');
            }
        } catch (error) {
            console.error('Login error:', error);
            errorDiv.textContent = '网络错误，请稍后重试';
            errorDiv.classList.remove('hidden');
        }
    }
    
    handleLogout() {
        this.token = null;
        this.currentUser = null;
        localStorage.removeItem('authToken');
        localStorage.removeItem('currentUser');
        this.showLogin();
        this.showNotification('已退出登录', 'success');
    }
    
    async loadWhitelist() {
        try {
            const response = await this.apiCall('GET', '/whitelist');
            if (response.success) {
                this.whitelist = response.data || [];
                this.renderWhitelist();
                this.updateStats();
            } else {
                this.showNotification('加载白名单失败', 'error');
            }
        } catch (error) {
            console.error('Load whitelist error:', error);
            this.showNotification('网络错误', 'error');
        }
    }
    
    async handleAddIP() {
        const ipInput = document.getElementById('ip-input');
        const descriptionInput = document.getElementById('description-input');
        
        const ip = ipInput.value.trim();
        const description = descriptionInput.value.trim();
        
        if (!ip) {
            this.showNotification('请输入IP地址', 'error');
            return;
        }
        
        if (!this.validateIP(ip)) {
            this.showNotification('IP地址格式无效', 'error');
            return;
        }
        
        try {
            const response = await this.apiCall('POST', '/whitelist', {
                ip,
                description
            });
            
            if (response.success) {
                this.hideAddForm();
                await this.loadWhitelist();
                this.showNotification('IP添加成功', 'success');
                
                // 清空表单
                ipInput.value = '';
                descriptionInput.value = '';
            } else {
                this.showNotification(response.message || 'IP添加失败', 'error');
            }
        } catch (error) {
            console.error('Add IP error:', error);
            this.showNotification('网络错误', 'error');
        }
    }
    
    async handleDeleteIP(id) {
        this.deleteItemId = id;
        this.showDeleteModal();
    }
    
    async confirmDelete() {
        if (!this.deleteItemId) return;
        
        try {
            const response = await this.apiCall('DELETE', `/whitelist/${this.deleteItemId}`);
            
            if (response.success) {
                this.hideDeleteModal();
                await this.loadWhitelist();
                this.showNotification('IP删除成功', 'success');
            } else {
                this.showNotification(response.message || 'IP删除失败', 'error');
            }
        } catch (error) {
            console.error('Delete IP error:', error);
            this.showNotification('网络错误', 'error');
        }
        
        this.deleteItemId = null;
    }
    
    validateIP(ip) {
        // IPv4 地址正则
        const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?$/;
        // IPv6 地址正则（简化版）
        const ipv6Regex = /^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}(\/\d{1,3})?$|^([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*(\/\d{1,3})?$/;
        
        if (ipv4Regex.test(ip)) {
            // 验证IPv4范围
            const parts = ip.split('/')[0].split('.');
            return parts.every(part => {
                const num = parseInt(part);
                return num >= 0 && num <= 255;
            });
        }
        
        if (ipv6Regex.test(ip)) {
            return true;
        }
        
        return false;
    }
    
    getIPType(ip) {
        if (ip.includes(':')) {
            return ip.includes('/') ? 'range' : 'ipv6';
        } else {
            return ip.includes('/') ? 'range' : 'ipv4';
        }
    }
    
    renderWhitelist() {
        const tbody = document.getElementById('whitelist-tbody');
        const emptyState = document.getElementById('empty-state');
        
        if (this.whitelist.length === 0) {
            tbody.innerHTML = '';
            emptyState.classList.remove('hidden');
            return;
        }
        
        emptyState.classList.add('hidden');
        
        tbody.innerHTML = this.whitelist.map(item => {
            const type = this.getIPType(item.ip);
            const typeClass = `type-${type}`;
            const typeLabel = {
                'ipv4': 'IPv4',
                'ipv6': 'IPv6',
                'range': '网段'
            }[type];
            
            return `
                <tr>
                    <td class="col-ip">${item.ip}</td>
                    <td class="col-type">
                        <span class="type-badge ${typeClass}">${typeLabel}</span>
                    </td>
                    <td class="col-description">${item.description || '-'}</td>
                    <td class="col-added">${this.formatDate(item.created_at)}</td>
                    <td class="col-actions">
                        <button class="delete-btn" onclick="app.handleDeleteIP('${item.id}')">
                            删除
                        </button>
                    </td>
                </tr>
            `;
        }).join('');
    }
    
    updateStats() {
        const total = this.whitelist.length;
        const ipv4Count = this.whitelist.filter(item => this.getIPType(item.ip) === 'ipv4').length;
        const ipv6Count = this.whitelist.filter(item => this.getIPType(item.ip) === 'ipv6').length;
        
        document.getElementById('total-entries').textContent = total;
        document.getElementById('ipv4-entries').textContent = ipv4Count;
        document.getElementById('ipv6-entries').textContent = ipv6Count;
    }
    
    async startStatusCheck() {
        await this.checkServiceStatus();
        // 每30秒检查一次状态
        setInterval(() => this.checkServiceStatus(), 30000);
    }
    
    async checkServiceStatus() {
        try {
            const response = await this.apiCall('GET', '/status');
            const statusElement = document.getElementById('service-status');
            const statusCard = document.getElementById('status-card');
            
            if (response.success && response.data.nginx_status === 'running') {
                statusElement.textContent = '正常运行';
                statusCard.className = 'stat-card status-online';
            } else {
                statusElement.textContent = '服务异常';
                statusCard.className = 'stat-card status-offline';
            }
        } catch (error) {
            console.error('Status check error:', error);
            document.getElementById('service-status').textContent = '检查失败';
            document.getElementById('status-card').className = 'stat-card status-offline';
        }
    }
    
    handleSearch(query) {
        const rows = document.querySelectorAll('#whitelist-tbody tr');
        const searchLower = query.toLowerCase();
        
        rows.forEach(row => {
            const ip = row.querySelector('.col-ip').textContent.toLowerCase();
            const description = row.querySelector('.col-description').textContent.toLowerCase();
            
            if (ip.includes(searchLower) || description.includes(searchLower)) {
                row.style.display = '';
            } else {
                row.style.display = 'none';
            }
        });
    }
    
    handleFilter(type) {
        const rows = document.querySelectorAll('#whitelist-tbody tr');
        
        rows.forEach(row => {
            const badge = row.querySelector('.type-badge');
            const itemType = badge.className.includes('type-ipv4') ? 'ipv4' :
                           badge.className.includes('type-ipv6') ? 'ipv6' : 'range';
            
            if (type === 'all' || type === itemType) {
                row.style.display = '';
            } else {
                row.style.display = 'none';
            }
        });
    }
    
    async exportWhitelist() {
        try {
            const response = await this.apiCall('GET', '/whitelist/export');
            if (response.success) {
                const blob = new Blob([response.data], { type: 'text/plain' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `whitelist_${new Date().toISOString().split('T')[0]}.conf`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                this.showNotification('导出成功', 'success');
            } else {
                this.showNotification('导出失败', 'error');
            }
        } catch (error) {
            console.error('Export error:', error);
            this.showNotification('网络错误', 'error');
        }
    }
    
    showLogin() {
        document.getElementById('main-container').classList.add('hidden');
        document.getElementById('login-container').classList.remove('hidden');
    }
    
    showMainInterface() {
        document.getElementById('login-container').classList.add('hidden');
        document.getElementById('main-container').classList.remove('hidden');
        document.getElementById('current-user').textContent = this.currentUser;
    }
    
    hideLoading() {
        document.getElementById('loading').classList.add('hidden');
    }
    
    showAddForm() {
        document.getElementById('add-ip-form').classList.remove('hidden');
        document.getElementById('ip-input').focus();
    }
    
    hideAddForm() {
        document.getElementById('add-ip-form').classList.add('hidden');
    }
    
    showDeleteModal() {
        document.getElementById('delete-modal').classList.remove('hidden');
    }
    
    hideDeleteModal() {
        document.getElementById('delete-modal').classList.add('hidden');
    }
    
    showNotification(message, type = 'info') {
        const notification = document.getElementById('notification');
        const content = notification.querySelector('.notification-content');
        const icon = notification.querySelector('.notification-icon');
        const messageSpan = notification.querySelector('.notification-message');
        
        // 设置图标
        const icons = {
            success: '✅',
            error: '❌',
            warning: '⚠️',
            info: 'ℹ️'
        };
        
        icon.textContent = icons[type] || icons.info;
        messageSpan.textContent = message;
        
        // 移除之前的类型类
        content.className = 'notification-content';
        if (type !== 'info') {
            content.classList.add(type);
        }
        
        notification.classList.remove('hidden');
        
        // 3秒后自动隐藏
        setTimeout(() => {
            notification.classList.add('hidden');
        }, 3000);
    }
    
    formatDate(dateString) {
        if (!dateString) return '-';
        const date = new Date(dateString);
        return date.toLocaleString('zh-CN', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        });
    }
    
    // 连接监控相关方法
    async startConnectionMonitoring() {
        await this.loadConnectionData();
        if (this.monitoringEnabled) {
            this.monitorInterval = setInterval(() => {
                if (this.monitoringEnabled) {
                    this.loadConnectionData();
                }
            }, 10000); // 每10秒更新一次
        }
    }
    
    toggleMonitoring() {
        this.monitoringEnabled = !this.monitoringEnabled;
        const btn = document.getElementById('toggle-monitor-btn');
        const icon = btn.querySelector('.btn-icon');
        
        if (this.monitoringEnabled) {
            icon.textContent = '⏸️';
            btn.childNodes[1].textContent = ' 暂停监控';
            this.startConnectionMonitoring();
        } else {
            icon.textContent = '▶️';
            btn.childNodes[1].textContent = ' 开始监控';
            if (this.monitorInterval) {
                clearInterval(this.monitorInterval);
                this.monitorInterval = null;
            }
        }
    }
    
    async clearConnectionLogs() {
        try {
            const response = await this.apiCall('DELETE', '/connections/logs');
            if (response.success) {
                this.connections = [];
                this.blockedIPs = [];
                this.renderConnections();
                this.renderBlockedIPs();
                this.updateConnectionStats();
                this.showNotification('日志已清空', 'success');
            } else {
                this.showNotification('清空日志失败', 'error');
            }
        } catch (error) {
            console.error('Clear logs error:', error);
            this.showNotification('网络错误', 'error');
        }
    }
    
    switchTab(tabName) {
        // 更新标签按钮状态
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.classList.remove('active');
        });
        document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');
        
        // 更新标签内容显示
        document.querySelectorAll('.tab-content').forEach(content => {
            content.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`).classList.add('active');
        
        this.currentTab = tabName;
        
        // 根据当前标签加载相应数据
        if (tabName === 'statistics') {
            this.renderConnectionChart();
        }
    }
    
    async loadConnectionData() {
        try {
            // 加载最近连接
            const connectionsResponse = await this.apiCall('GET', '/connections/recent');
            if (connectionsResponse.success) {
                this.connections = connectionsResponse.data || [];
                if (this.currentTab === 'recent') {
                    this.renderConnections();
                }
                
                // 显示调试信息
                if (connectionsResponse.debug) {
                    console.log('连接监控调试信息:', connectionsResponse.debug);
                    
                    // 如果没有连接记录且日志文件存在，可能是解析问题
                    if (this.connections.length === 0 && 
                        connectionsResponse.debug.log_file_exists && 
                        connectionsResponse.debug.log_file_size > 0) {
                        console.warn('日志文件存在但无连接记录，可能是解析问题');
                        // 测试日志解析
                        this.testLogParsing();
                    }
                }
            }
            
            // 加载被拒绝的IP
            const blockedResponse = await this.apiCall('GET', '/connections/blocked');
            if (blockedResponse.success) {
                this.blockedIPs = blockedResponse.data || [];
                if (this.currentTab === 'blocked') {
                    this.renderBlockedIPs();
                }
            }
            
            // 加载连接统计
            const statsResponse = await this.apiCall('GET', '/connections/stats');
            if (statsResponse.success) {
                this.connectionStats = statsResponse.data || {};
                this.updateConnectionStats();
                if (this.currentTab === 'statistics') {
                    this.renderConnectionChart();
                }
            }
        } catch (error) {
            console.error('Load connection data error:', error);
            if (error.message.includes('Unauthorized')) {
                this.showNotification('登录已过期，请重新登录', 'warning');
            } else {
                this.showNotification('加载连接数据失败', 'error');
            }
        }
    }
    
    async testLogParsing() {
        try {
            const response = await this.apiCall('GET', '/connections/test-parse');
            if (response.success) {
                console.log('日志解析测试结果:', response);
                if (response.parsed_successfully === 0 && response.total_lines_tested > 0) {
                    this.showNotification('检测到nginx日志解析问题，请检查日志格式', 'warning');
                }
            }
        } catch (error) {
            console.error('测试日志解析失败:', error);
        }
    }
    
    renderConnections() {
        const tbody = document.getElementById('connections-tbody');
        
        if (this.connections.length === 0) {
            tbody.innerHTML = `
                <div class="empty-connections">
                    <div class="empty-icon">👁️</div>
                    <p>暂无连接记录</p>
                </div>
            `;
            return;
        }
        
        tbody.innerHTML = this.connections.map(conn => {
            const statusClass = conn.status === 'allowed' ? 'status-allowed' : 'status-denied';
            const statusText = conn.status === 'allowed' ? '允许' : '拒绝';
            const timeStr = this.formatTime(conn.timestamp);
            
            return `
                <div class="connection-item">
                    <div class="connection-time">${timeStr}</div>
                    <div class="connection-ip">${conn.ip}</div>
                    <div class="connection-status ${statusClass}">${statusText}</div>
                    <div class="connection-location">${conn.location || '未知'}</div>
                    <div class="connection-action">
                        ${conn.status === 'denied' ? 
                            `<button class="action-btn add-whitelist" onclick="app.addToWhitelist('${conn.ip}')">添加白名单</button>` : 
                            ''
                        }
                    </div>
                </div>
            `;
        }).join('');
    }
    
    renderBlockedIPs() {
        const tbody = document.getElementById('blocked-ips-tbody');
        
        if (this.blockedIPs.length === 0) {
            tbody.innerHTML = `
                <div class="empty-blocked">
                    <div class="empty-icon">🛡️</div>
                    <p>暂无被拒绝的IP地址</p>
                </div>
            `;
            return;
        }
        
        tbody.innerHTML = this.blockedIPs.map(item => {
            const lastAttempt = this.formatTime(item.last_attempt);
            
            return `
                <div class="blocked-item">
                    <div class="connection-ip">${item.ip}</div>
                    <div class="connection-ip">${item.attempt_count}</div>
                    <div class="connection-time">${lastAttempt}</div>
                    <div class="connection-location">${item.location || '未知'}</div>
                    <div class="connection-action">
                        <button class="action-btn add-whitelist" onclick="app.addToWhitelist('${item.ip}')">添加白名单</button>
                    </div>
                </div>
            `;
        }).join('');
    }
    
    updateConnectionStats() {
        if (!this.connectionStats) return;
        
        // 更新主要统计卡片
        document.getElementById('allowed-count').textContent = this.connectionStats.allowed_today || 0;
        document.getElementById('denied-count').textContent = this.connectionStats.denied_today || 0;
        
        // 更新详细统计
        document.getElementById('total-connections').textContent = this.connectionStats.total_connections || 0;
        document.getElementById('unique-ips').textContent = this.connectionStats.unique_ips || 0;
        
        const total = (this.connectionStats.allowed_today || 0) + (this.connectionStats.denied_today || 0);
        const successRate = total > 0 ? Math.round((this.connectionStats.allowed_today || 0) * 100 / total) : 0;
        document.getElementById('success-rate').textContent = `${successRate}%`;
    }
    
    renderConnectionChart() {
        const canvas = document.getElementById('hourly-canvas');
        if (!canvas || !this.connectionStats.hourly_data) return;
        
        const ctx = canvas.getContext('2d');
        const data = this.connectionStats.hourly_data || [];
        
        // 清空画布
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        if (data.length === 0) {
            ctx.fillStyle = '#64748b';
            ctx.font = '14px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('暂无数据', canvas.width / 2, canvas.height / 2);
            return;
        }
        
        // 简单的柱状图渲染
        const barWidth = canvas.width / data.length;
        const maxValue = Math.max(...data.map(d => d.allowed + d.denied), 1);
        
        data.forEach((item, index) => {
            const x = index * barWidth;
            const allowedHeight = (item.allowed / maxValue) * canvas.height * 0.8;
            const deniedHeight = (item.denied / maxValue) * canvas.height * 0.8;
            
            // 绘制允许的连接（绿色）
            ctx.fillStyle = '#059669';
            ctx.fillRect(x, canvas.height - allowedHeight, barWidth * 0.4, allowedHeight);
            
            // 绘制拒绝的连接（红色）
            ctx.fillStyle = '#dc2626';
            ctx.fillRect(x + barWidth * 0.4, canvas.height - deniedHeight, barWidth * 0.4, deniedHeight);
            
            // 绘制时间标签
            ctx.fillStyle = '#64748b';
            ctx.font = '10px sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText(`${item.hour}:00`, x + barWidth / 2, canvas.height - 5);
        });
    }
    
    async addToWhitelist(ip) {
        try {
            const response = await this.apiCall('POST', '/whitelist', {
                ip: ip,
                description: `从监控日志添加 - ${new Date().toLocaleString()}`
            });
            
            if (response.success) {
                await this.loadWhitelist();
                this.showNotification(`IP ${ip} 已添加到白名单`, 'success');
            } else {
                this.showNotification(response.message || 'IP添加失败', 'error');
            }
        } catch (error) {
            console.error('Add to whitelist error:', error);
            this.showNotification('网络错误', 'error');
        }
    }
    
    formatTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleTimeString('zh-CN', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
    }
    
    async apiCall(method, endpoint, data = null) {
        const url = `${this.apiBase}${endpoint}`;
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json',
            }
        };
        
        if (this.token) {
            options.headers['Authorization'] = `Bearer ${this.token}`;
        }
        
        if (data) {
            options.body = JSON.stringify(data);
        }
        
        const response = await fetch(url, options);
        
        if (response.status === 401) {
            this.handleLogout();
            throw new Error('Unauthorized');
        }
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        return await response.json();
    }
}

// 初始化应用
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new MTProxyManager();
});

// 全局错误处理
window.addEventListener('error', (event) => {
    console.error('Global error:', event.error);
});

window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
});