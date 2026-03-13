# IPTV 直播源测速与实时更新系统

自动从 GitHub 获取 IPTV 直播源，实时测速清洗，并通过 HTTP 提供有效频道列表。

## 功能特性

- ✅ **自动获取直播源**：每小时从 GitHub 拉取最新的 M3U 文件
- ✅ **实时测速更新**：每3分钟对所有频道进行测速
- ✅ **智能清洗**：自动过滤无效频道，只保留可用的直播源
- ✅ **数据库存储**：保存测速历史和统计数据
- ✅ **HTTP 文件服务**：通过 `http://localhost:5353` 访问有效频道列表
- ✅ **M3U 导出**：自动生成 `tv.m3u` 文件，包含所有有效频道

## 快速开始

### 1. 启动所有服务

```bash
# 创建数据目录
mkdir -p ./data

# 启动完整服务（获取 + 测速 + HTTP服务）
docker compose -f docker-compose.speedtest.yml up -d
```

### 2. 查看服务状态

```bash
# 查看所有容器状态
docker ps -a --filter "name=iptv"

# 查看各服务日志
docker logs -f iptv_fetcher    # 直播源获取服务
docker logs -f iptv_speedtest  # 测速服务
docker logs -f iptv_nginx     # HTTP 服务
```

### 3. 访问有效频道列表

```bash
# 浏览器访问
http://localhost:5353/tv.m3u

# 或使用 curl
curl http://localhost:5353/tv.m3u
```

### 4. 停止服务

```bash
docker compose -f docker-compose.speedtest.yml down
```

## 服务架构

```
┌─────────────────┐     每小时      ┌─────────────────┐
│   GitHub 源     │ ────────────────> │  iptv_fetcher   │
│                 │                 │  (curl 容器)    │
└─────────────────┘                 └────────┬────────┘
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │  iptv.m3u   │
                                     │  (原始源)    │
                                     └──────┬───────┘
                                            │ 每3分钟
                                            ▼
┌─────────────────┐                 ┌──────────────┐
│  HTTP 客户端    │ <───────────────│iptv_speedtest│
│ localhost:5353  │                 │ (测速服务)    │
└─────────────────┘                 └──────┬───────┘
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │  tv.m3u     │
                                     │ (有效频道)   │
                                     └──────────────┘
```

## 服务说明

### iptv_fetcher - 直播源获取服务

- **功能**：从 GitHub 定期拉取最新的 IPTV 直播源
- **拉取频率**：每小时一次（3600秒）
- **输出文件**：`./data/iptv.m3u`

### iptv_speedtest - 测速清洗服务

- **功能**：对直播源进行实时测速，清洗无效频道
- **测速频率**：每3分钟一次（180秒）
- **超时设置**：单个频道5秒超时
- **输出文件**：
  - `./data/tv.m3u` - 有效频道列表
  - `./data/iptv_speedtest.db` - 测速数据库

### iptv_nginx - HTTP 文件服务

- **功能**：提供 HTTP 文件访问服务
- **端口**：5353
- **访问地址**：`http://localhost:5353/tv.m3u`
- **功能**：支持目录浏览、跨域访问

## 数据库结构

### channels 表 - 频道信息

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 频道 ID（主键） |
| name | TEXT | 频道名称 |
| url | TEXT | 频道地址（唯一） |
| group_name | TEXT | 频道分组 |
| status | TEXT | 状态（valid/invalid/timeout/error） |
| response_time_ms | INTEGER | 响应时间（毫秒） |
| last_test_time | TIMESTAMP | 最后测试时间 |

### speed_test_history 表 - 测速历史

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 记录 ID（主键） |
| channel_id | INTEGER | 频道 ID |
| response_time_ms | INTEGER | 响应时间 |
| status | TEXT | 测速状态 |
| error_msg | TEXT | 错误信息 |
| test_time | TIMESTAMP | 测试时间 |

### statistics 表 - 统计数据

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 记录 ID（主键） |
| total_channels | INTEGER | 总频道数 |
| valid_channels | INTEGER | 有效频道数 |
| invalid_channels | INTEGER | 无效频道数 |
| avg_response_time_ms | REAL | 平均响应时间 |
| success_rate | REAL | 成功率 |
| stat_time | TIMESTAMP | 统计时间 |

## 配置说明

### 修改拉取频率

编辑 [`docker-compose.speedtest.yml`](docker-compose.speedtest.yml:18) 中的 `iptv_fetcher` 服务：

```yaml
command: sh -c 'while true; do curl -fsSL "..." -o /data/iptv.m3u.tmp && mv /data/iptv.m3u.tmp /data/iptv.m3u && echo "$(date -Iseconds) updated"; sleep 3600; done'
#                                                                                                                                  ^^^^^^
#                                                                                                                               修改这里（秒）
```

### 修改测速频率

编辑 [`docker-compose.speedtest.yml`](docker-compose.speedtest.yml:56) 中的环境变量：

```yaml
environment:
  TEST_INTERVAL: 180  # 测速间隔（秒），默认 3 分钟
```

### 修改测速超时

编辑 [`docker-compose.speedtest.yml`](docker-compose.speedtest.yml:57) 中的环境变量：

```yaml
environment:
  TEST_TIMEOUT: 5  # 单个频道超时（秒），默认 5 秒
```

### 修改 HTTP 端口

编辑 [`docker-compose.speedtest.yml`](docker-compose.speedtest.yml:29) 中的端口映射：

```yaml
ports:
  - "8080:80"  # 将 5353 改为 8080
```

## 查询数据库

```bash
# 进入容器查询
docker exec -it iptv_speedtest sqlite3 /data/iptv_speedtest.db

# 或直接从本地查询（需要安装 sqlite3）
sqlite3 ./data/iptv_speedtest.db
```

### 常用查询示例

```sql
-- 获取所有有效频道
SELECT name, url, response_time_ms FROM channels 
WHERE status='valid' ORDER BY response_time_ms;

-- 获取最新统计数据
SELECT * FROM statistics ORDER BY stat_time DESC LIMIT 1;

-- 获取单个频道的测速历史
SELECT response_time_ms, status, test_time FROM speed_test_history 
WHERE channel_id = 1 ORDER BY test_time DESC LIMIT 10;

-- 按分组统计有效频道数
SELECT group_name, COUNT(*) as count FROM channels 
WHERE status='valid' GROUP BY group_name ORDER BY count DESC;
```

## 日志示例

### iptv_fetcher 日志

```
2026-03-04T08:00:00+00:00 updated
2026-03-04T09:00:00+00:00 updated
2026-03-04T10:00:00+00:00 updated
```

### iptv_speedtest 日志

```
2026-03-04 08:00:00,123 - INFO - ==================================================
2026-03-04 08:00:00,125 - INFO - Starting IPTV speedtest and cleansing
2026-03-04 08:00:00,127 - INFO - ==================================================
2026-03-04 08:00:00,456 - INFO - Parsed 47 channels from /data/iptv.m3u
2026-03-04 08:00:01,789 - INFO - [1/47] Testing: CCTV-1 - http://...
...
2026-03-04 08:01:30,567 - INFO - Statistics: total=47, valid=45, invalid=2, avg_time=58ms, success_rate=95.74%
2026-03-04 08:01:30,968 - INFO - Generated tv.m3u with 45 valid channels: /data/tv.m3u
2026-03-04 08:01:30,969 - INFO - Speedtest completed: 47 tested, 45 valid, 2 invalid
2026-03-04 08:01:30,970 - INFO - Next test in 180s...
```

## tv.m3u 文件格式

```
#EXTM3U

# ===== 📺央视频道 =====
#EXTINF:-1 group-title="📺央视频道" tvg-name="CCTV-1",CCTV-1
http://39.134.246.145:80/wh7f454c46tw3359402476_-14003855/000000001000/1000000001000021973/1.m3u8

# ===== 📡卫视频道 =====
#EXTINF:-1 group-title="📡卫视频道" tvg-name="浙江卫视",浙江卫视
http://39.134.246.132:80/wh7f454c46tw611840634_-1847862552/0/1.m3u8
```

## 故障排除

### 1. M3U 文件不存在

```bash
# 确保先启动了 iptv_fetcher
docker logs -f iptv_fetcher
```

### 2. 测速过程缓慢

- 检查网络连接
- 适当增加 `TEST_TIMEOUT`
- 检查本地 curl 能否访问频道 URL

### 3. 数据库锁定

```bash
# 重启容器即可恢复
docker restart iptv_speedtest
```

### 4. HTTP 无法访问

```bash
# 检查 nginx 容器状态
docker ps | grep iptv_nginx

# 检查端口是否被占用
netstat -tlnp | grep 5353

# 查看 nginx 日志
docker logs iptv_nginx
```

## 文件结构

```
.
├── docker-compose.speedtest.yml  # 完整服务配置
├── docker-compose.yml            # 仅直播源获取
├── Dockerfile.speedtest         # 测速服务镜像
├── nginx/
│   └── default.conf            # Nginx 配置
├── scripts/
│   └── speedtest_cleaner.py    # 测速脚本
├── data/
│   ├── iptv.m3u               # 原始直播源
│   ├── tv.m3u                 # 有效频道列表
│   └── iptv_speedtest.db      # 测速数据库
└── README.md                  # 本文档
```

## 许可证

MIT License
