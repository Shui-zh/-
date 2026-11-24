#!/bin/bash
set -e

echo "=========================================="
echo "VNC 黑屏修复脚本"
echo "=========================================="
echo ""

# 1. 强制停止所有 VNC 进程
echo "[1/6] 停止 VNC 服务..."
vncserver -kill :1 2>/dev/null || true
pkill -9 Xvnc 2>/dev/null || true
pkill -9 vnc 2>/dev/null || true
echo "✅ VNC 进程已停止"

# 2. 清理锁文件和日志
echo "[2/6] 清理锁文件和日志..."
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
rm -f ~/.vnc/*.log
echo "✅ 清理完成"

# 3. 安装简单桌面环境
echo "[3/6] 安装简单桌面环境（xterm + twm）..."
sudo apt install -y xterm twm
echo "✅ 安装完成"

# 4. 创建简单的启动脚本
echo "[4/6] 创建启动脚本..."
mkdir -p ~/.vnc

cat > ~/.vnc/xstartup << 'EOF'
#!/bin/sh
xterm &
exec twm
EOF

chmod +x ~/.vnc/xstartup
echo "✅ 启动脚本已创建"

# 5. 重新启动 VNC
echo "[5/6] 启动 VNC 服务器..."
vncserver :1 -geometry 1280x720 -depth 24 -localhost
echo "✅ VNC 已启动"

# 6. 验证状态
echo "[6/6] 验证状态..."
vncserver -list
echo ""

echo "=========================================="
echo "✅ 修复完成！"
echo "=========================================="
echo ""
echo "现在应该能看到一个黑色背景 + 一个终端窗口"
echo ""
echo "如果还是黑屏，检查笔记本端："
echo "  1. 确认 SSH 隧道在运行："
echo "     ps aux | grep 'ssh -L'"
echo ""
echo "  2. 如果没有，重新建立隧道："
echo "     ssh -L 5901:localhost:5901 -N car"
echo ""
echo "  3. 用 vncviewer 连接："
echo "     vncviewer localhost:5901"
echo ""
echo "如果简单桌面能显示，再切回 XFCE："
echo "  1. 安装 XFCE："
echo "     sudo apt install -y xfce4 xfce4-goodies"
echo ""
echo "  2. 修改启动脚本："
echo "     cat > ~/.vnc/xstartup << 'XEOF'"
echo "     #!/bin/sh"
echo "     unset SESSION_MANAGER"
echo "     unset DBUS_SESSION_BUS_ADDRESS"
echo "     if command -v dbus-launch >/dev/null 2>&1; then"
echo "         eval \$(dbus-launch --sh-syntax)"
echo "     fi"
echo "     exec startxfce4"
echo "     XEOF"
echo "     chmod +x ~/.vnc/xstartup"
echo ""
echo "  3. 重启 VNC："
echo "     vncserver -kill :1"
echo "     vncserver :1 -geometry 1280x720 -depth 24 -localhost"
echo ""
