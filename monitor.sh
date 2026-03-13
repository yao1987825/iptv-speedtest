#!/bin/bash

# IPTV Speedtest 监控脚本
# 定期检查服务状态并发送通知

set -e

PROJECT_DIR="/root/iptv-speedtest"
COMPOSE_FILE="docker-compose.speedtest.yml"
ALERT_WEBHOOK=""  # 设置你的通知webhook（可选）

cd "$PROJECT_DIR"

# 检查容器状态
check_containers() {
    local status=0
    
    echo "📊 检查容器状态..."
    
    # 检查容器是否运行
    if ! docker ps --format "{{.Names}}" | grep -q "^iptv_fetcher$"; then
        echo "❌ iptv_fetcher 容器未运行"
        status=1
    else
        echo "✅ iptv_fetcher 运行中"
    fi
    
    if ! docker ps --format "{{.Names}}" | grep -q "^iptv_speedtest$"; then
        echo "❌ iptv_speedtest 容器未运行"
        status=1
    else
        echo "✅ iptv_speedtest 运行中"
    fi
    
    if ! docker ps --format "{{.Names}}" | grep -q "^iptv_nginx$"; then
        echo "❌ iptv_nginx 容器未运行"
        status=1
    else
        echo "✅ iptv_nginx 运行中"
    fi
    
    return $status
}

# 检查HTTP服务
check_http_service() {
    local status=0
    
    echo ""
    echo "🌐 检查HTTP服务..."
    
    if curl -s http://localhost:5353/tv.m3u | head -1 | grep -q EXTM3U; then
        echo "✅ HTTP服务正常"
    else
        echo "❌ HTTP服务异常"
        status=1
    fi
    
    return $status
}

# 检查数据文件
check_data_files() {
    local status=0
    
    echo ""
    echo "📁 检查数据文件..."
    
    if [ ! -f "./data/iptv.m3u" ]; then
        echo "❌ iptv.m3u 文件不存在"
        status=1
    else
        local channels=$(grep -c "^http" ./data/iptv.m3u || echo 0)
        echo "✅ iptv.m3u 存在 ($channels 个频道)"
    fi
    
    if [ ! -f "./data/tv.m3u" ]; then
        echo "❌ tv.m3u 文件不存在"
        status=1
    else
        local valid_channels=$(grep -c "^http" ./data/tv.m3u || echo 0)
        echo "✅ tv.m3u 存在 ($valid_channels 个有效频道)"
    fi
    
    return $status
}

# 检查数据库统计
check_database() {
    echo ""
    echo "📊 数据库统计..."
    
    if [ -f "./data/iptv_speedtest.db" ]; then
        docker exec iptv_speedtest python3 -c "
import sqlite3
conn = sqlite3.connect('/data/iptv_speedtest.db')
c = conn.cursor()
c.execute('SELECT COUNT(*), (SELECT COUNT(*) FROM channels WHERE status=\"valid\") FROM channels')
total, valid = c.fetchone()
success_rate = (valid / total * 100) if total > 0 else 0
print(f'总频道: {total}, 有效: {valid}, 成功率: {success_rate:.1f}%')
conn.close()
"
    else
        echo "❌ 数据库文件不存在"
    fi
}

# 检查网络连接
check_network() {
    local status=0
    
    echo ""
    echo "🌐 检查网络连接..."
    
    if docker exec iptv_fetcher curl -s --connect-timeout 5 https://www.baidu.com > /dev/null 2>&1; then
        echo "✅ 网络连接正常"
    else
        echo "❌ 网络连接异常"
        status=1
    fi
    
    return $status
}

# 发送通知
send_alert() {
    local message="$1"
    
    if [ -n "$ALERT_WEBHOOK" ]; then
        curl -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"🚨 IPTV Speedtest 警告: $message\"}"
    fi
}

# 主函数
main() {
    echo "=========================================="
    echo "  IPTV Speedtest 监控检查"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    local overall_status=0
    
    check_containers || overall_status=1
    check_http_service || overall_status=1
    check_data_files || overall_status=1
    check_network || overall_status=1
    check_database
    
    echo ""
    echo "=========================================="
    
    if [ $overall_status -eq 0 ]; then
        echo "✅ 所有检查通过"
    else
        echo "❌ 检查发现问题，请查看详情"
        send_alert "IPTV Speedtest 监控检查失败"
    fi
    
    echo "=========================================="
    
    return $overall_status
}

# 执行主函数
main
