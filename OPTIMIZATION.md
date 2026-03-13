# IPTV Speedtest 部署优化建议

## 📋 部署摘要

### 服务器信息
- **系统**: ImmortalWrt 24.10-SNAPSHOT (OpenWrt)
- **架构**: ARM64
- **内存**: 1.8GB
- **磁盘**: 58.4GB 可用 (Docker 数据目录)

### 服务状态
✅ **所有服务正常运行**
- `iptv_fetcher`: 直播源获取服务 (host网络模式)
- `iptv_speedtest`: 测速清洗服务 (host网络模式)
- `iptv_nginx`: HTTP文件服务 (bridge网络模式，端口5353)

### 测速结果
- **总频道数**: 47
- **有效频道**: 44
- **无效频道**: 3
- **成功率**: 93.6%

### 访问地址
- **HTTP服务**: http://10.10.10.130:5353/tv.m3u
- **本地访问**: http://localhost:5353/tv.m3u

---

## 🚀 已实施的优化

### 1. 网络优化
- **问题**: Docker容器默认bridge模式无法访问外网
- **解决**: 为 `iptv_fetcher` 和 `iptv_speedtest` 使用 `network_mode: host`
- **效果**: 成功访问GitHub和直播源进行测速

### 2. 配置修复
- **问题**: docker-compose.speedtest.yml中重复定义了iptv_fetcher服务
- **解决**: 删除了重复的服务定义

### 3. 镜像优化
- 使用Python 3.11-slim基础镜像
- 安装curl用于测速
- 最小化镜像体积

---

## 🔧 进一步优化建议

### 1. 资源优化

#### 限制容器资源使用
```yaml
# 在docker-compose.speedtest.yml中添加
services:
  iptv_speedtest:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

#### 优化测速间隔
当前配置：3分钟测速一次（180秒）
- 建议调整为 **5-10分钟**（300-600秒）
- 减少不必要的网络请求
- 延长设备寿命

```yaml
environment:
  TEST_INTERVAL: 600  # 10分钟
```

### 2. 性能优化

#### 并发测速
当前是串行测速，可以改为并发测速：
```python
# 在speedtest_cleaner.py中使用多线程
from concurrent.futures import ThreadPoolExecutor, as_completed

def test_channels_concurrent(channels, max_workers=5):
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_channel = {
            executor.submit(test_channel, ch['url']): ch 
            for ch in channels
        }
        for future in as_completed(future_to_channel):
            channel = future_to_channel[future]
            result = future.result()
            results.append((channel, result))
    return results
```

#### 缓存有效频道
如果上次测试有效的频道在短时间内再次测试，可以跳过：
```python
# 添加环境变量
environment:
  VALID_CHANNEL_TTL: 3600  # 有效频道1小时内不重新测试
```

### 3. 监控优化

#### 添加定时监控
使用cron定时执行监控脚本：
```bash
# 编辑crontab
crontab -e

# 每10分钟检查一次
*/10 * * * * /root/iptv-speedtest/monitor.sh >> /var/log/iptv-monitor.log 2>&1
```

#### 集成告警通知
在monitor.sh中配置webhook：
```bash
ALERT_WEBHOOK="https://your-webhook-url.com"
```

### 4. 数据管理

#### 定期清理历史数据
```python
# 清理30天前的测速历史
def clean_old_history(db_path, days=30):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''
        DELETE FROM speed_test_history 
        WHERE test_time < datetime('now', '-{} days')
    '''.format(days))
    conn.commit()
    conn.close()
```

#### 数据库优化
```sql
-- 添加索引
CREATE INDEX IF NOT EXISTS idx_channels_status ON channels(status);
CREATE INDEX IF NOT EXISTS idx_channels_url ON channels(url);
CREATE INDEX IF NOT EXISTS idx_history_time ON speed_test_history(test_time);
```

### 5. 安全优化

#### 配置防火墙规则
```bash
# 只允许特定IP访问5353端口
iptables -A INPUT -p tcp --dport 5353 -s 10.10.10.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 5353 -j DROP
```

#### 使用HTTPS
```nginx
# 添加Nginx SSL配置
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    # ...
}
```

### 6. 容器管理

#### 自动重启策略
已配置 `restart: unless-stopped`
- 容器崩溃后自动重启
- 主机重启后自动启动

#### 日志管理
当前配置：
- 日志大小限制: 50-100MB
- 日志文件数量: 3-10个
- 总日志大小限制: 约1GB

建议添加日志轮转：
```bash
# 使用logrotate
cat > /etc/logrotate.d/iptv-containers << EOF
/var/lib/docker/containers/*/*-json.log {
    rotate 7
    daily
    compress
    size 10M
    missingok
    notifempty
    copytruncate
}
EOF
```

### 7. 备份策略

#### 自动备份数据库
```bash
#!/bin/bash
# backup.sh
BACKUP_DIR="/root/backups/iptv"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d_%H%M%S)

# 备份数据库
docker exec iptv_speedtest cat /data/iptv_speedtest.db > \
    "$BACKUP_DIR/iptv_speedtest_$DATE.db"

# 备份M3U文件
cp /root/iptv-speedtest/data/tv.m3u "$BACKUP_DIR/tv_$DATE.m3u"

# 删除7天前的备份
find "$BACKUP_DIR" -name "*.db" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.m3u" -mtime +7 -delete
```

添加到cron：
```bash
# 每天凌晨3点备份
0 3 * * * /root/iptv-speedtest/backup.sh
```

---

## 📊 监控指标

建议监控以下指标：

1. **服务可用性**
   - 容器运行状态
   - HTTP服务响应时间

2. **测速指标**
   - 有效频道数量
   - 成功率
   - 平均响应时间

3. **系统资源**
   - CPU使用率
   - 内存使用率
   - 磁盘空间

4. **业务指标**
   - M3U文件更新时间
   - 测速完成时间

---

## 🎯 性能基线

### 当前性能
- 单频道测速: ~0.05秒
- 完整测速周期: ~2.5秒 (47个频道)
- 数据库大小: ~90KB
- tv.m3u大小: ~9KB

### 目标性能
- 测速间隔: 10分钟
- 并发测速: 5个线程
- 完整测速时间: <1分钟
- 内存使用: <500MB

---

## 📞 故障处理

### 常见问题

1. **容器无法访问外网**
   ```bash
   # 检查网络模式
   docker inspect iptv_fetcher | grep NetworkMode
   
   # 测试网络连接
   docker exec iptv_fetcher ping -c 1 8.8.8.8
   ```

2. **测速速度慢**
   - 检查网络带宽
   - 减少超时时间: `TEST_TIMEOUT: 3`
   - 增加并发数

3. **磁盘空间不足**
   ```bash
   # 清理Docker
   docker system prune -a
   
   # 清理日志
   journalctl --vacuum-time=3d
   ```

---

## 📚 参考文档

- [Docker Compose 文档](https://docs.docker.com/compose/)
- [SQLite 文档](https://www.sqlite.org/docs.html)
- [Nginx 配置](https://nginx.org/en/docs/)

---

## 🔄 更新记录

- 2026-03-04: 初始部署，优化网络配置
- 2026-03-04: 添加监控和备份脚本
- 2026-03-04: 性能优化建议

---

**部署完成时间**: 2026-03-04 17:19  
**版本**: v1.0  
**状态**: ✅ 运行正常
