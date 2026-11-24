#!/bin/bash
set -e

echo "=========================================="
echo "VNC 开机自启配置（修正版）"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本"
    echo "用法：sudo bash setup_vnc_autostart_v2.sh"
    exit 1
fi

# 获取实际用户
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

echo "配置用户：$REAL_USER"
echo "用户目录：$REAL_HOME"
echo ""

# 1. 停止现有 VNC 服务
echo "[1/5] 停止现有 VNC 服务..."
su - $REAL_USER -c "vncserver -kill :2 2>/dev/null || true"
pkill -9 Xvnc 2>/dev/null || true
pkill -9 vnc 2>/dev/null || true
echo "✅ 已停止"

# 2. 清理残留文件
echo "[2/5] 清理残留文件..."
rm -f /tmp/.X2-lock /tmp/.X11-unix/X2
echo "✅ 已清理"

# 3. 创建 systemd 服务文件
echo "[3/5] 创建 systemd 服务文件..."

cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=TigerVNC server display %i
After=syslog.target network.target

[Service]
Type=forking
User=$REAL_USER
WorkingDirectory=$REAL_HOME

ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :%i > /dev/null 2>&1 || true'
ExecStart=/usr/bin/vncserver :%i -geometry 1920x1080 -depth 24
ExecStop=/bin/sh -c '/usr/bin/vncserver -kill :%i > /dev/null 2>&1 || true'

TimeoutStartSec=60
TimeoutStopSec=30
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "✅ 服务文件已创建：/etc/systemd/system/vncserver@.service"

# 4. 重载 systemd 配置
echo "[4/5] 重载 systemd 配置..."
systemctl daemon-reload
echo "✅ 配置已重载"

# 5. 启用并启动服务
echo "[5/5] 启用并启动 VNC 服务..."
systemctl enable vncserver@2.service
systemctl start vncserver@2.service

# 等待几秒让服务完全启动
sleep 3

echo "✅ 服务已启用并启动"
echo ""

# 验证状态
echo "=========================================="
echo "服务状态"
echo "=========================================="
systemctl status vncserver@2.service --no-pager
echo ""

# 验证 VNC 是否运行
echo "=========================================="
echo "VNC 进程检查"
echo "=========================================="
su - $REAL_USER -c "vncserver -list"
echo ""

echo "=========================================="
echo "✅ 配置完成！"
echo "=========================================="
echo ""
echo "服务信息："
echo "  - 服务名：vncserver@2.service"
echo "  - 显示号：:2"
echo "  - 端口：5902"
echo "  - 分辨率：1920x1080"
echo "  - 绑定：0.0.0.0（可直接连接）"
echo ""
echo "常用管理命令："
echo "  - 查看状态：sudo systemctl status vncserver@2.service"
echo "  - 启动服务：sudo systemctl start vncserver@2.service"
echo "  - 停止服务：sudo systemctl stop vncserver@2.service"
echo "  - 重启服务：sudo systemctl restart vncserver@2.service"
echo "  - 禁用自启：sudo systemctl disable vncserver@2.service"
echo "  - 启用自启：sudo systemctl enable vncserver@2.service"
echo ""
echo "从笔记本连接（使用 Remmina）："
echo "  1. 启动 Remmina："
echo "     flatpak run org.remmina.Remmina"
echo ""
echo "  2. 在 Remmina 中创建新连接："
echo "     - 协议：VNC"
echo "     - 服务器：192.168.8.250:5902"
echo "     - 密码：你的 VNC 密码"
echo ""
echo "查看日志："
echo "  - 服务日志：journalctl -u vncserver@2.service -f"
echo "  - VNC 日志：tail -f $REAL_HOME/.vnc/*.log"
echo ""
