#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
MTProxy 白名单管理系统 Flask API
提供白名单管理、用户认证、系统状态检查等功能
"""

import os
import sys
import json
import sqlite3
import hashlib
import secrets
import ipaddress
import subprocess
import re
from collections import defaultdict
from datetime import datetime, timedelta
from functools import wraps
from pathlib import Path

from flask import Flask, request, jsonify, g
from flask_cors import CORS
import jwt

# 应用配置
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['JWT_EXPIRATION_HOURS'] = int(os.environ.get('JWT_EXPIRATION_HOURS', '24'))

# 启用 CORS
CORS(app, origins=['*'])

# 路径配置
BASE_DIR = Path(__file__).parent
DATA_DIR = Path('/data')
NGINX_WHITELIST_PATH = DATA_DIR / 'nginx' / 'whitelist.txt'  # 新的白名单文件路径
NGINX_MAP_PATH = DATA_DIR / 'nginx' / 'whitelist_map.conf'  # nginx映射文件
NGINX_LOG_PATH = Path('/var/log/nginx/stream_access.log')   # 更新日志路径
DB_PATH = DATA_DIR / 'webapp' / 'users.db'
CONFIG_PATH = DATA_DIR / 'webapp' / 'config.json'
LOG_DIR = DATA_DIR / 'webapp' / 'logs'

# 确保目录存在
for path in [DATA_DIR / 'nginx', DATA_DIR / 'webapp', LOG_DIR]:
    path.mkdir(parents=True, exist_ok=True)

# 日志配置
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_DIR / 'api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DatabaseManager:
    """数据库管理类"""
    
    def __init__(self, db_path):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        """初始化数据库"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 创建用户表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP,
                is_active BOOLEAN DEFAULT 1
            )
        ''')
        
        # 创建白名单表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS whitelist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip TEXT UNIQUE NOT NULL,
                description TEXT,
                ip_type TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_by TEXT,
                is_active BOOLEAN DEFAULT 1
            )
        ''')
        
        # 创建操作日志表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS operation_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user TEXT NOT NULL,
                action TEXT NOT NULL,
                target TEXT,
                details TEXT,
                ip_address TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # 创建连接日志表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS connection_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT NOT NULL,
                status TEXT NOT NULL,  -- 'allowed' or 'denied'
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                user_agent TEXT,
                location TEXT
            )
        ''')
        
        # 创建被拒绝IP统计表
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS blocked_ip_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT UNIQUE NOT NULL,
                attempt_count INTEGER DEFAULT 1,
                first_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                location TEXT
            )
        ''')
        
        # 创建索引
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_connection_logs_ip ON connection_logs(ip_address)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_connection_logs_timestamp ON connection_logs(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_connection_logs_status ON connection_logs(status)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_blocked_ip_stats_ip ON blocked_ip_stats(ip_address)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_blocked_ip_stats_last_attempt ON blocked_ip_stats(last_attempt)')
        
        # 创建默认管理员用户
        self.create_default_admin(cursor)
        
        conn.commit()
        conn.close()
        logger.info("Database initialized successfully")
    
    def create_default_admin(self, cursor):
        """创建默认管理员用户"""
        try:
            # 检查是否已存在管理员用户
            cursor.execute("SELECT COUNT(*) FROM users WHERE username = ?", ('admin',))
            if cursor.fetchone()[0] == 0:
                # 从环境变量获取管理员密码
                admin_password = os.environ.get('ADMIN_PASSWORD', 'admin123')
                password_hash = hashlib.sha256(admin_password.encode()).hexdigest()
                
                cursor.execute(
                    "INSERT INTO users (username, password_hash) VALUES (?, ?)",
                    ('admin', password_hash)
                )
                logger.info(f"Default admin user created with password from environment variable")
        except Exception as e:
            logger.error(f"Error creating default admin: {e}")
    
    def get_connection(self):
        """获取数据库连接"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

class WhitelistManager:
    """白名单管理类"""
    
    def __init__(self, nginx_path, db_manager):
        self.nginx_path = nginx_path
        self.db_manager = db_manager
    
    def validate_ip(self, ip_str):
        """验证IP地址格式"""
        try:
            # 如果包含斜杠，是IP段/网络地址
            if '/' in ip_str:
                ip_obj = ipaddress.ip_network(ip_str, strict=False)
                return 'range', str(ip_obj)
            else:
                # 单个IP地址，使用ip_address而不是ip_network
                ip_obj = ipaddress.ip_address(ip_str)
                if ip_obj.version == 4:
                    return 'ipv4', str(ip_obj)  # 保持原始格式
                else:
                    return 'ipv6', str(ip_obj)  # 保持原始格式
        except ValueError as e:
            raise ValueError(f"Invalid IP address format: {e}")
    
    def add_ip(self, ip_str, description='', user=''):
        """添加IP到白名单"""
        ip_type, normalized_ip = self.validate_ip(ip_str)
        
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        try:
            # 检查IP是否已存在
            cursor.execute("SELECT id FROM whitelist WHERE ip = ? AND is_active = 1", (normalized_ip,))
            if cursor.fetchone():
                raise ValueError("IP address already exists in whitelist")
            
            # 添加到数据库
            cursor.execute('''
                INSERT INTO whitelist (ip, description, ip_type, created_by)
                VALUES (?, ?, ?, ?)
            ''', (normalized_ip, description, ip_type, user))
            
            item_id = cursor.lastrowid
            
            # 记录操作日志
            cursor.execute('''
                INSERT INTO operation_logs (user, action, target, details)
                VALUES (?, ?, ?, ?)
            ''', (user, 'ADD_IP', normalized_ip, description))
            
            conn.commit()
            
            # 更新nginx配置文件
            self.update_nginx_config()
            
            logger.info(f"IP {normalized_ip} added to whitelist by {user}")
            return item_id
            
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()
    
    def remove_ip(self, item_id, user=''):
        """从白名单移除IP"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        try:
            # 获取IP信息
            cursor.execute("SELECT ip FROM whitelist WHERE id = ? AND is_active = 1", (item_id,))
            row = cursor.fetchone()
            if not row:
                raise ValueError("IP not found in whitelist")
            
            ip_addr = row['ip']
            
            # 标记为删除（软删除）
            cursor.execute(
                "UPDATE whitelist SET is_active = 0 WHERE id = ?",
                (item_id,)
            )
            
            # 记录操作日志
            cursor.execute('''
                INSERT INTO operation_logs (user, action, target)
                VALUES (?, ?, ?)
            ''', (user, 'REMOVE_IP', ip_addr))
            
            conn.commit()
            
            # 更新nginx配置文件
            self.update_nginx_config()
            
            logger.info(f"IP {ip_addr} removed from whitelist by {user}")
            
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()
    
    def get_whitelist(self):
        """获取白名单列表"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT id, ip, description, ip_type, created_at, created_by
            FROM whitelist
            WHERE is_active = 1
            ORDER BY created_at DESC
        ''')
        
        items = []
        for row in cursor.fetchall():
            items.append({
                'id': row['id'],
                'ip': row['ip'],
                'description': row['description'] or '',
                'ip_type': row['ip_type'],
                'created_at': row['created_at'],
                'created_by': row['created_by'] or ''
            })
        
        conn.close()
        return items
    
    def generate_whitelist_map(self):
        """生成nginx白名单映射配置文件"""
        try:
            map_lines = [
                f"# 白名单映射文件 - 自动生成 {datetime.now().strftime('%a %b %d %H:%M:%S UTC %Y')}",
                "# 格式: IP地址 1;"
            ]
            
            # 添加默认条目 (localhost)
            map_lines.extend([
                "127.0.0.1 1;",
                "::1 1;"
            ])
            
            # 从数据库获取活跃的白名单条目
            whitelist = self.get_whitelist()
            
            for item in whitelist:
                ip = item['ip'].strip()
                if ip and not ip.startswith('#'):
                    # 确保IP格式正确并添加映射条目
                    map_lines.append(f"{ip} 1;")
            
            # 确保目录存在
            map_path = NGINX_MAP_PATH
            map_path.parent.mkdir(parents=True, exist_ok=True)
            
            # 写入映射文件
            try:
                map_path.write_text('\n'.join(map_lines), encoding='utf-8')
                logger.info(f"Generated whitelist map with {len(map_lines)-2} entries at {map_path}")
            except PermissionError as pe:
                logger.error(f"Permission denied writing to {map_path}: {pe}")
                # 尝试备用方案：直接写入临时位置
                import tempfile
                with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as tmp:
                    tmp.write('\n'.join(map_lines))
                    tmp.flush()
                    # 尝试移动到目标位置
                    import shutil
                    try:
                        shutil.move(tmp.name, str(map_path))
                        logger.info(f"Successfully moved temp file to {map_path}")
                    except Exception as move_err:
                        logger.error(f"Failed to move temp file: {move_err}")
                        raise move_err
            
            return len(map_lines) - 2  # 减去注释行数
            
        except Exception as e:
            logger.error(f"Error generating whitelist map: {e}")
            logger.error(f"Map path: {NGINX_MAP_PATH}")
            logger.error(f"Map path exists: {NGINX_MAP_PATH.parent.exists()}")
            logger.error(f"Map path writable: {os.access(NGINX_MAP_PATH.parent, os.W_OK) if NGINX_MAP_PATH.parent.exists() else 'Unknown'}")
            raise e

    def update_nginx_config(self):
        """更新nginx白名单配置文件"""
        try:
            logger.info("Starting nginx config update...")
            whitelist = self.get_whitelist()
            logger.info(f"Retrieved {len(whitelist)} whitelist entries")
            
            # 生成白名单IP列表 (新格式: 每行一个IP)
            ip_lines = [
                "# MTProxy 白名单配置文件",
                "# This file is automatically generated and managed by the web interface",
                f"# Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                f"# Total entries: {len(whitelist)}",
                "",
                "# Default entries (localhost for testing)",
                "127.0.0.1",
                "::1",
                "",
                "# User added entries",
            ]
            
            for item in whitelist:
                # 添加注释说明 (如果有描述)
                if item['description']:
                    ip_lines.append(f"# {item['description']}")
                ip_lines.append(item['ip'])
            
            # 写入白名单文件
            logger.info(f"Writing whitelist to {self.nginx_path}")
            self.nginx_path.write_text('\n'.join(ip_lines), encoding='utf-8')
            logger.info("Whitelist file written successfully")
            
            # 生成nginx映射文件 - 新增关键步骤
            logger.info("Generating whitelist map...")
            map_entries = self.generate_whitelist_map()
            logger.info(f"Map generation completed with {map_entries} entries")
            
            # 调用白名单重载脚本
            logger.info("Calling reload whitelist...")
            self.reload_whitelist()
            logger.info("Reload completed successfully")
            
            logger.info(f"Nginx whitelist config updated with {len(whitelist)} entries")
            logger.info(f"Nginx map config updated with {map_entries} map entries")
            
        except Exception as e:
            logger.error(f"Error updating nginx config: {e}")
            import traceback
            logger.error(f"Full traceback: {traceback.format_exc()}")
            raise e
    
    def reload_whitelist(self):
        """重载白名单配置"""
        try:
            # 调用白名单重载脚本
            result = subprocess.run(['/usr/local/bin/reload-whitelist.sh', 'reload'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                raise RuntimeError(f"Whitelist reload failed: {result.stderr}")
            
            logger.info("Whitelist configuration reloaded successfully")
            logger.debug(f"Reload output: {result.stdout}")
            
        except FileNotFoundError:
            logger.warning("Whitelist reload script not found, attempting direct nginx reload")
            # 备用方案：直接重载nginx
            try:
                subprocess.run(['nginx', '-s', 'reload'], check=True, capture_output=True)
                logger.info("Nginx reloaded directly")
            except Exception as e:
                logger.error(f"Direct nginx reload also failed: {e}")
                raise e
        except subprocess.TimeoutExpired:
            logger.error("Whitelist reload script timed out")
            raise RuntimeError("Whitelist reload timed out")
        except Exception as e:
            logger.error(f"Error reloading whitelist: {e}")
            raise e

class ConnectionMonitor:
    """连接监控管理类"""
    
    def __init__(self, db_manager, log_path=NGINX_LOG_PATH):
        self.db_manager = db_manager
        self.log_path = log_path
        self.last_position = 0
        self.load_last_position()
    
    def load_last_position(self):
        """加载上次读取的日志位置"""
        try:
            pos_file = DATA_DIR / 'webapp' / 'log_position.txt'
            if pos_file.exists():
                self.last_position = int(pos_file.read_text().strip())
        except:
            self.last_position = 0
    
    def save_last_position(self):
        """保存当前读取的日志位置"""
        try:
            pos_file = DATA_DIR / 'webapp' / 'log_position.txt'
            pos_file.write_text(str(self.last_position))
        except Exception as e:
            logger.error(f"Error saving log position: {e}")
    
    def parse_nginx_logs(self):
        """解析nginx日志获取连接信息"""
        if not self.log_path.exists():
            return []
        
        connections = []
        try:
            with open(self.log_path, 'r', encoding='utf-8', errors='ignore') as f:
                f.seek(self.last_position)
                
                for line in f:
                    try:
                        # 解析nginx stream log格式
                        # IP [时间] 协议 状态 发送字节 接收字节 会话时间 whitelist:0/1
                        match = re.match(
                            r'(\d+\.\d+\.\d+\.\d+|\[?[0-9a-fA-F:]+\]?) \[([^\]]+)\] (\w+) (\d+) (\d+) (\d+) ([\d.]+) whitelist:([01])',
                            line.strip()
                        )
                        
                        if match:
                            ip = match.group(1)
                            timestamp_str = match.group(2)
                            protocol = match.group(3)
                            status_code = match.group(4)
                            whitelist_status = match.group(8)
                            
                            # 解析时间
                            try:
                                timestamp = datetime.strptime(timestamp_str, '%d/%b/%Y:%H:%M:%S %z')
                            except:
                                timestamp = datetime.now()
                            
                            # 确定连接状态
                            status = 'allowed' if whitelist_status == '1' else 'denied'
                            
                            connections.append({
                                'ip': ip,
                                'status': status,
                                'timestamp': timestamp,
                                'protocol': protocol
                            })
                    
                    except Exception as e:
                        logger.debug(f"Error parsing log line: {e}")
                        continue
                
                self.last_position = f.tell()
                self.save_last_position()
        
        except Exception as e:
            logger.error(f"Error reading nginx logs: {e}")
        
        return connections
    
    def record_connections(self, connections):
        """记录连接到数据库"""
        if not connections:
            return
        
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        try:
            for connection in connections:
                # 记录连接日志
                cursor.execute('''
                    INSERT INTO connection_logs (ip_address, status, timestamp, location)
                    VALUES (?, ?, ?, ?)
                ''', (
                    connection['ip'],
                    connection['status'],
                    connection['timestamp'],
                    self.get_ip_location(connection['ip'])
                ))
                
                # 如果是被拒绝的连接，更新统计
                if connection['status'] == 'denied':
                    cursor.execute('''
                        INSERT OR IGNORE INTO blocked_ip_stats 
                        (ip_address, location, first_attempt, last_attempt)
                        VALUES (?, ?, ?, ?)
                    ''', (
                        connection['ip'],
                        self.get_ip_location(connection['ip']),
                        connection['timestamp'],
                        connection['timestamp']
                    ))
                    
                    cursor.execute('''
                        UPDATE blocked_ip_stats 
                        SET attempt_count = attempt_count + 1,
                            last_attempt = ?
                        WHERE ip_address = ?
                    ''', (connection['timestamp'], connection['ip']))
            
            conn.commit()
            
        except Exception as e:
            conn.rollback()
            logger.error(f"Error recording connections: {e}")
        finally:
            conn.close()
    
    def get_recent_connections(self, limit=100):
        """获取最近的连接记录"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT ip_address, status, timestamp, location
            FROM connection_logs
            ORDER BY timestamp DESC
            LIMIT ?
        ''', (limit,))
        
        connections = []
        for row in cursor.fetchall():
            connections.append({
                'ip': row['ip_address'],
                'status': row['status'],
                'timestamp': row['timestamp'],
                'location': row['location'] or '未知'
            })
        
        conn.close()
        return connections
    
    def get_blocked_ips(self, limit=50):
        """获取被拒绝的IP统计"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT ip_address, attempt_count, first_attempt, last_attempt, location
            FROM blocked_ip_stats
            ORDER BY last_attempt DESC
            LIMIT ?
        ''', (limit,))
        
        blocked_ips = []
        for row in cursor.fetchall():
            blocked_ips.append({
                'ip': row['ip_address'],
                'attempt_count': row['attempt_count'],
                'first_attempt': row['first_attempt'],
                'last_attempt': row['last_attempt'],
                'location': row['location'] or '未知'
            })
        
        conn.close()
        return blocked_ips
    
    def get_connection_stats(self):
        """获取连接统计信息"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        # 今天的统计
        today = datetime.now().strftime('%Y-%m-%d')
        cursor.execute('''
            SELECT status, COUNT(*) as count
            FROM connection_logs
            WHERE DATE(timestamp) = ?
            GROUP BY status
        ''', (today,))
        
        today_stats = {'allowed': 0, 'denied': 0}
        for row in cursor.fetchall():
            today_stats[row['status']] = row['count']
        
        # 总体统计
        cursor.execute('SELECT COUNT(*) as total FROM connection_logs')
        total_connections = cursor.fetchone()['total']
        
        cursor.execute('SELECT COUNT(DISTINCT ip_address) as unique_count FROM connection_logs')
        unique_ips = cursor.fetchone()['unique_count']
        
        # 24小时连接趋势
        cursor.execute('''
            SELECT 
                strftime('%H', timestamp) as hour,
                status,
                COUNT(*) as count
            FROM connection_logs
            WHERE timestamp >= datetime('now', '-24 hours')
            GROUP BY hour, status
            ORDER BY hour
        ''')
        
        hourly_data = defaultdict(lambda: {'allowed': 0, 'denied': 0})
        for row in cursor.fetchall():
            hour = int(row['hour'])
            hourly_data[hour][row['status']] = row['count']
        
        # 转换为列表格式
        hourly_list = []
        for hour in range(24):
            hourly_list.append({
                'hour': hour,
                'allowed': hourly_data[hour]['allowed'],
                'denied': hourly_data[hour]['denied']
            })
        
        conn.close()
        
        return {
            'allowed_today': today_stats['allowed'],
            'denied_today': today_stats['denied'],
            'total_connections': total_connections,
            'unique_ips': unique_ips,
            'hourly_data': hourly_list
        }
    
    def clear_logs(self):
        """清空连接日志"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        try:
            cursor.execute('DELETE FROM connection_logs')
            cursor.execute('DELETE FROM blocked_ip_stats')
            conn.commit()
            
            # 重置日志位置
            self.last_position = 0
            self.save_last_position()
            
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()
    
    def get_ip_location(self, ip):
        """获取IP地理位置（简化版）"""
        try:
            # 这里可以集成IP地理位置查询服务
            # 目前返回简单的分类
            if ip.startswith('127.') or ip == '::1':
                return '本地'
            elif ip.startswith('192.168.') or ip.startswith('10.') or ip.startswith('172.'):
                return '内网'
            else:
                return '外网'
        except:
            return '未知'
    
    def update_connections(self):
        """更新连接数据（定期调用）"""
        try:
            connections = self.parse_nginx_logs()
            if connections:
                self.record_connections(connections)
                logger.debug(f"Recorded {len(connections)} new connections")
        except Exception as e:
            logger.error(f"Error updating connections: {e}")

class AuthManager:
    """认证管理类"""
    
    def __init__(self, db_manager, secret_key):
        self.db_manager = db_manager
        self.secret_key = secret_key
    
    def authenticate_user(self, username, password):
        """用户认证"""
        conn = self.db_manager.get_connection()
        cursor = conn.cursor()
        
        try:
            password_hash = hashlib.sha256(password.encode()).hexdigest()
            
            cursor.execute('''
                SELECT id, username, is_active FROM users
                WHERE username = ? AND password_hash = ?
            ''', (username, password_hash))
            
            user = cursor.fetchone()
            if not user or not user['is_active']:
                return None
            
            # 更新最后登录时间
            cursor.execute(
                "UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?",
                (user['id'],)
            )
            conn.commit()
            
            return {
                'id': user['id'],
                'username': user['username']
            }
            
        finally:
            conn.close()
    
    def generate_token(self, user):
        """生成JWT token"""
        payload = {
            'user_id': user['id'],
            'username': user['username'],
            'exp': datetime.utcnow() + timedelta(hours=app.config['JWT_EXPIRATION_HOURS'])
        }
        return jwt.encode(payload, self.secret_key, algorithm='HS256')
    
    def verify_token(self, token):
        """验证JWT token"""
        try:
            payload = jwt.decode(token, self.secret_key, algorithms=['HS256'])
            return payload
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

# 初始化管理器
db_manager = DatabaseManager(DB_PATH)
whitelist_manager = WhitelistManager(NGINX_WHITELIST_PATH, db_manager)
auth_manager = AuthManager(db_manager, app.config['SECRET_KEY'])
connection_monitor = ConnectionMonitor(db_manager)

def require_auth(f):
    """认证装饰器"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = None
        auth_header = request.headers.get('Authorization')
        
        if auth_header:
            try:
                token = auth_header.split(' ')[1]  # Bearer <token>
            except IndexError:
                pass
        
        if not token:
            return jsonify({'success': False, 'message': 'Token is missing'}), 401
        
        payload = auth_manager.verify_token(token)
        if not payload:
            return jsonify({'success': False, 'message': 'Token is invalid or expired'}), 401
        
        g.current_user = payload
        return f(*args, **kwargs)
    
    return decorated_function

def log_operation(action, target='', details=''):
    """记录操作日志"""
    try:
        user = g.current_user.get('username', 'unknown') if hasattr(g, 'current_user') else 'system'
        ip_address = request.remote_addr if request else ''
        
        conn = db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO operation_logs (user, action, target, details, ip_address)
            VALUES (?, ?, ?, ?, ?)
        ''', (user, action, target, details, ip_address))
        
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Error logging operation: {e}")

# API 路由

@app.route('/api/auth/login', methods=['POST'])
def login():
    """用户登录"""
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        
        if not username or not password:
            return jsonify({
                'success': False,
                'message': 'Username and password are required'
            }), 400
        
        user = auth_manager.authenticate_user(username, password)
        if not user:
            return jsonify({
                'success': False,
                'message': 'Invalid username or password'
            }), 401
        
        token = auth_manager.generate_token(user)
        
        logger.info(f"User {username} logged in successfully")
        
        return jsonify({
            'success': True,
            'token': token,
            'user': user['username']
        })
        
    except Exception as e:
        logger.error(f"Login error: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@app.route('/api/auth/verify', methods=['GET'])
@require_auth
def verify_token():
    """验证token有效性"""
    return jsonify({
        'success': True,
        'user': g.current_user
    })

@app.route('/api/whitelist', methods=['GET'])
@require_auth
def get_whitelist():
    """获取白名单列表"""
    try:
        whitelist = whitelist_manager.get_whitelist()
        return jsonify({
            'success': True,
            'data': whitelist
        })
    except Exception as e:
        logger.error(f"Error getting whitelist: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to retrieve whitelist'
        }), 500

@app.route('/api/whitelist', methods=['POST'])
@require_auth
def add_whitelist_ip():
    """添加IP到白名单"""
    try:
        data = request.get_json()
        ip = data.get('ip', '').strip()
        description = data.get('description', '').strip()
        
        if not ip:
            return jsonify({
                'success': False,
                'message': 'IP address is required'
            }), 400
        
        user = g.current_user.get('username', '')
        item_id = whitelist_manager.add_ip(ip, description, user)
        
        log_operation('ADD_IP', ip, description)
        
        return jsonify({
            'success': True,
            'message': 'IP added successfully',
            'id': item_id
        })
        
    except ValueError as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 400
    except Exception as e:
        logger.error(f"Error adding IP: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to add IP'
        }), 500

@app.route('/api/whitelist/<int:item_id>', methods=['DELETE'])
@require_auth
def remove_whitelist_ip(item_id):
    """从白名单移除IP"""
    try:
        user = g.current_user.get('username', '')
        whitelist_manager.remove_ip(item_id, user)
        
        log_operation('REMOVE_IP', str(item_id))
        
        return jsonify({
            'success': True,
            'message': 'IP removed successfully'
        })
        
    except ValueError as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 404
    except Exception as e:
        logger.error(f"Error removing IP: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to remove IP'
        }), 500

@app.route('/api/whitelist/export', methods=['GET'])
@require_auth
def export_whitelist():
    """导出白名单配置"""
    try:
        whitelist = whitelist_manager.get_whitelist()
        
        lines = [
            "# MTProxy Whitelist Export",
            f"# Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"# Total entries: {len(whitelist)}",
            ""
        ]
        
        for item in whitelist:
            if item['description']:
                lines.append(f"# {item['description']}")
            lines.append(f"{item['ip']} 1;")
            lines.append("")
        
        config_text = '\n'.join(lines)
        
        log_operation('EXPORT_WHITELIST')
        
        return jsonify({
            'success': True,
            'data': config_text
        })
        
    except Exception as e:
        logger.error(f"Error exporting whitelist: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to export whitelist'
        }), 500

@app.route('/api/status', methods=['GET'])
@require_auth
def get_status():
    """获取系统状态"""
    try:
        # 检查nginx状态
        nginx_status = 'unknown'
        try:
            result = subprocess.run(['pgrep', 'nginx'], capture_output=True, text=True)
            nginx_status = 'running' if result.returncode == 0 else 'stopped'
        except:
            nginx_status = 'unknown'
        
        # 检查白名单条目数
        whitelist_count = len(whitelist_manager.get_whitelist())
        
        return jsonify({
            'success': True,
            'data': {
                'nginx_status': nginx_status,
                'whitelist_count': whitelist_count,
                'timestamp': datetime.now().isoformat()
            }
        })
        
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get status'
        }), 500

@app.route('/api/logs', methods=['GET'])
@require_auth
def get_logs():
    """获取操作日志"""
    try:
        limit = min(int(request.args.get('limit', 100)), 1000)
        offset = int(request.args.get('offset', 0))
        
        conn = db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT user, action, target, details, ip_address, timestamp
            FROM operation_logs
            ORDER BY timestamp DESC
            LIMIT ? OFFSET ?
        ''', (limit, offset))
        
        logs = []
        for row in cursor.fetchall():
            logs.append({
                'user': row['user'],
                'action': row['action'],
                'target': row['target'],
                'details': row['details'],
                'ip_address': row['ip_address'],
                'timestamp': row['timestamp']
            })
        
        conn.close()
        
        return jsonify({
            'success': True,
            'data': logs
        })
        
    except Exception as e:
        logger.error(f"Error getting logs: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get logs'
        }), 500

# 连接监控API端点

@app.route('/api/connections/recent', methods=['GET'])
@require_auth
def get_recent_connections():
    """获取最近的连接记录"""
    try:
        # 更新连接数据
        connection_monitor.update_connections()
        
        limit = min(int(request.args.get('limit', 100)), 500)
        connections = connection_monitor.get_recent_connections(limit)
        
        return jsonify({
            'success': True,
            'data': connections
        })
        
    except Exception as e:
        logger.error(f"Error getting recent connections: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get recent connections'
        }), 500

@app.route('/api/connections/blocked', methods=['GET'])
@require_auth
def get_blocked_ips():
    """获取被拒绝的IP统计"""
    try:
        limit = min(int(request.args.get('limit', 50)), 200)
        blocked_ips = connection_monitor.get_blocked_ips(limit)
        
        return jsonify({
            'success': True,
            'data': blocked_ips
        })
        
    except Exception as e:
        logger.error(f"Error getting blocked IPs: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get blocked IPs'
        }), 500

@app.route('/api/connections/stats', methods=['GET'])
@require_auth
def get_connection_stats():
    """获取连接统计信息"""
    try:
        # 更新连接数据
        connection_monitor.update_connections()
        
        stats = connection_monitor.get_connection_stats()
        
        return jsonify({
            'success': True,
            'data': stats
        })
        
    except Exception as e:
        logger.error(f"Error getting connection stats: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to get connection stats'
        }), 500

@app.route('/api/connections/logs', methods=['DELETE'])
@require_auth
def clear_connection_logs():
    """清空连接日志"""
    try:
        user = g.current_user.get('username', '')
        connection_monitor.clear_logs()
        
        log_operation('CLEAR_CONNECTION_LOGS', '', f'Cleared by {user}')
        
        return jsonify({
            'success': True,
            'message': 'Connection logs cleared successfully'
        })
        
    except Exception as e:
        logger.error(f"Error clearing connection logs: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to clear connection logs'
        }), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'message': 'API endpoint not found'
    }), 404

@app.route('/health', methods=['GET'])
def health_check():
    """健康检查端点"""
    return jsonify({
        'success': True,
        'message': 'API is healthy',
        'timestamp': datetime.now().isoformat()
    }), 200

@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        'success': False,
        'message': 'Internal server error'
    }), 500

if __name__ == '__main__':
    logger.info("Starting MTProxy Whitelist API server")
    port = int(os.environ.get('API_PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)