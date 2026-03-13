#!/bin/bash

# IPTV Speedtest 部署脚本
# 适用于 OpenWrt ARM64 服务器

set -e

echo "=========================================="
echo "  IPTV Speedtest 部署脚本"
echo "=========================================="

# 配置
PROJECT_DIR="/root/iptv-speedtest"
COMPOSE_FILE="docker-compose.speedtest.yml"

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker"
    exit 1
fi

echo "✅ Docker 已安装: $(docker --version)"

# 检查Docker Compose
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose 未安装，请先安装 Docker Compose"
    exit 1
fi

echo "✅ Docker Compose 已安装: $(docker compose version)"

# 停止现有服务
echo ""
echo "🛑 停止现有服务..."
cd "$PROJECT_DIR"
docker compose -f "$COMPOSE_FILE" down || true

# 拉取最新镜像
echo ""
echo "📦 拉取最新镜像..."
docker compose -f "$COMPOSE_FILE" pull

# 构建测速服务镜像
echo ""
echo "🔨 构建测速服务镜像..."
docker compose -f "$COMPOSE_FILE" build

# 启动所有服务
echo ""
echo "🚀 启动所有服务..."
docker compose -f "$COMPOSE_FILE" up -d

# 等待服务启动
echo ""
echo "⏳ 等待服务启动..."
sleep 5

# 检查服务状态
echo ""
echo "📊 服务状态:"
docker ps --filter "name=iptv" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 检查网络连接
echo ""
echo "🌐 检查网络连接..."
if docker exec iptv_fetcher curl -s --connect-timeout 5 https://www.baidu.com > /dev/null 2>&1; then
    echo "✅ 网络连接正常"
else
    echo "⚠️  网络连接异常，请检查配置"
fi

# 检查HTTP服务
echo ""
echo "🌍 检查HTTP服务..."
if curl -s http://localhost:5353/tv.m3u | head -1 | grep -q EXTM3U; then
    echo "✅ HTTP服务正常: http://localhost:5353/tv.m3u"
else
    echo "⚠️  HTTP服务异常，请检查日志"
fi

# 显示访问地址
echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "📍 访问地址:"
echo "   - HTTP服务: http://$(hostname -I | awk '{print $1}'):5353/tv.m3u"
echo "   - 本地访问: http://localhost:5353/tv.m3u"
echo ""
echo "📝 查看日志:"
echo "   - 直播源获取: docker logs -f iptv_fetcher"
echo "   - 测速服务: docker logs -f iptv_speedtest"
echo "   - HTTP服务: docker logs -f iptv_nginx"
echo ""
echo "🔧 管理命令:"
echo "   - 停止服务: cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE down"
echo "   - 重启服务: cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE restart"
echo "   - 查看状态: cd $PROJECT_DIR && docker compose -f $COMPOSE_FILE ps"
echo ""
echo "=========================================="
