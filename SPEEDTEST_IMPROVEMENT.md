# 测速优化说明

## 问题分析

用户反馈：湖南爱晚频道虽然被标记为有效，但实际无法播放。

### 原因分析

1. **测速方法局限**：原始逻辑只检查 HTTP 状态码（200 OK）
2. **内容验证不足**：没有深入验证流媒体内容
3. **频道不稳定**：某些频道时好时坏

### 测试结果

```
频道组：湖南频道
- 湖南爱晚      ✓ valid (174ms)
- 湖南经视      ✓ valid (157ms)
- 金鹰卡通      ✓ valid (195ms)
- 长沙新闻频道  ✓ valid (245ms)
- 湖南电视剧    ✗ invalid (HTTP 403)
- 湖南国际频道  ✗ invalid (HTTP 410)
- 湖南娱乐频道  ✗ invalid (HTTP 403)
```

---

## 优化方案

### 1. 已实施的优化

**增强版测速逻辑** (speedtest_cleaner.py:125-169)

```python
def test_channel(url, timeout=5):
    """测速单个频道（增强版：验证内容）"""
    # 1. 获取完整内容和HTTP状态码
    # 2. 检查状态码是否为 2xx
    # 3. 对于 m3u8 文件，验证内容格式
    #    - 检查是否包含 #EXTM3U 标记
    #    - 检查是否包含分片信息 (#EXTINF 或 .ts)
```

**改进点：**
- ✅ 获取完整内容而不只是状态码
- ✅ 验证 m3u8 文件格式
- ✅ 检查是否包含媒体分片

### 2. 建议的进一步优化

#### 方案A：多次测试验证

连续测试 2-3 次，只有都成功才标记为 valid

```python
def test_channel_with_retry(url, timeout=5, retries=2):
    """多次测试验证"""
    for i in range(retries + 1):
        result = test_channel(url, timeout)
        if result['status'] != 'valid':
            return result
        time.sleep(1)  # 间隔1秒
    return result
```

#### 方案B：ts 分片验证

对于 m3u8 文件，尝试下载第一个 ts 分片

```python
def test_ts_segment(m3u8_content):
    """测试 ts 分片是否可下载"""
    # 1. 解析 m3u8 获取 ts 分片 URL
    # 2. 尝试下载第一个 ts 分片
    # 3. 验证文件大小是否合理（>1KB）
```

#### 方案C：FFmpeg 验证

使用 FFmpeg 尝试播放流媒体

```python
def test_with_ffmpeg(url, timeout=10):
    """使用 FFmpeg 验证流媒体"""
    result = subprocess.run([
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', url
    ], timeout=timeout, capture_output=True)
    # 如果能获取时长，说明可播放
```

---

## 当前状态

### 湖南爱晚分析

**测速历史（最近10次）**：
- 9次 valid
- 1次 invalid (HTTP 000)
- 成功率：90%

**内容验证**：
- ✓ HTTP 200 OK
- ✓ 包含 #EXTM3U 标记
- ✓ 包含 #EXTINF 分片信息
- ✓ ts 分片可下载（返回 200）

**可能失效原因**：
1. 频道有时效性（token 可能过期）
2. 频道不稳定（时好时坏）
3. 需要特定的客户端参数
4. 可能是测试时段恰好可用

---

## 建议

### 短期方案（已实施）

1. ✅ 增强测速逻辑（验证内容格式）
2. ✅ 部署更新后的测速服务

### 中期方案（建议实施）

1. **增加测速频率**：从 3 分钟改为 1 分钟
2. **多次验证**：连续测试 2-3 次
3. **稳定性评分**：根据历史成功率评分

### 长期方案（可选）

1. **集成 FFmpeg**：实际尝试播放流媒体
2. **用户反馈**：允许用户标记失效频道
3. **智能调度**：优先测试不稳定频道

---

## 验证命令

```bash
# 查看湖南频道状态
docker exec iptv_speedtest python3 <<'EOF'
import sqlite3
conn = sqlite3.connect('/data/iptv_speedtest.db')
c = conn.cursor()
c.execute("SELECT name, status FROM channels WHERE group_name LIKE '%湖南%'")
for row in c.fetchall():
    print(f"{row[0]:20} {row[1]:10}")
EOF

# 手动测试湖南爱晚
curl -s -m 10 '湖南爱晚URL' | head -10

# 查看最近测速日志
docker logs --tail 50 iptv_speedtest | grep '湖南'
```

---

## 配置调整

如果需要调整测速频率，修改 `docker-compose.speedtest.yml`：

```yaml
environment:
  TEST_INTERVAL: 60  # 改为 1 分钟
  TEST_TIMEOUT: 10   # 增加超时到 10 秒
```

---

**更新时间**: 2026-03-04 18:05
**状态**: 已部署增强版测速逻辑
