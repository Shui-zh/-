#!/bin/bash
set -e

echo "=========================================="
echo "VNC 服务器一键安装脚本"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本"
    echo "用法：sudo bash install_vnc.sh"
    exit 1
fi

# 获取实际用户（不是 root）
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

echo "安装用户：$REAL_USER"
echo "用户目录：$REAL_HOME"
echo ""

# 1. 换源（可选，加速下载）
#echo "[1/6] 更换软件源（阿里云镜像）..."
#cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true
#sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
#sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

# 2. 更新软件包
echo "[2/6] 更新软件包列表..."
apt update -y

# 3. 安装软件
echo "[3/6] 安装 TigerVNC 和 XFCE4..."
apt install -y tigervnc-standalone-server tigervnc-common xfce4 xfce4-goodies

# 4. 配置 VNC
echo "[4/6] 配置 VNC 服务器..."
su - $REAL_USER -c "
    # 创建配置目录
    mkdir -p ~/.vnc
    
    # 创建配置文件
    cat > ~/.vnc/config << 'VNC_CONFIG'
session=xfce
geometry=1920x1080
depth=24
localhost=no
VNC_CONFIG
    
    # 创建启动脚本
    cat > ~/.vnc/xstartup << 'XSTARTUP'
#!/bin/sh
unset WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR
export DISPLAY=:2 XDG_SESSION_TYPE=x11
[ -x /usr/bin/dbus-launch ] && eval \$(dbus-launch --sh-syntax)
xset -dpms s noblank s off 2>/dev/null
exec startxfce4
XSTARTUP
    
    chmod +x ~/.vnc/xstartup
    echo 'VNC 配置文件已创建'
"

# 5. 设置密码
echo "[5/6] 设置 VNC 密码..."
echo "请为用户 $REAL_USER 设置 VNC 连接密码（需要输入两次）："
su - $REAL_USER -c "vncpasswd"

# 6. 启动 VNC
echo "[6/6] 启动 VNC 服务器..."
su - $REAL_USER -c "
    # 清理残留
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2
    
    # 停止可能存在的旧实例
    vncserver -kill :2 2>/dev/null || true
    
    # 启动新的 VNC 服务器
    vncserver :2 -geometry 1920x1080 -depth 24
    
    # 显示运行状态
    echo ''
    echo 'VNC 服务器状态：'
    vncserver -list
"

# 7. 配置防火墙（如果存在）
if command -v ufw &> /dev/null; then
    echo ""
    echo "配置防火墙..."
    ufw allow 5902/tcp
    echo "防火墙规则已添加：允许 5902 端口"
fi

echo ""
echo "=========================================="
echo "✅ 安装完成！"
echo "=========================================="
echo ""
echo "连接信息："
echo "  - 地址：localhost:5902 或 127.0.0.1:5902"
echo "  - 显示号：:2"
echo "  - 端口：5902"
echo ""
echo "使用 Remmina 连接："
echo "  1. 安装 Remmina（如果未安装）："
echo "     sudo apt install -y flatpak"
echo "     flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
echo "     flatpak install flathub org.remmina.Remmina"
echo "  2. 启动 Remmina：flatpak run org.remmina.Remmina"
echo "  3. 创建新连接"
echo "  4. 协议选择：VNC"
echo "  5. 服务器：localhost:5902"
echo "  6. 输入刚才设置的密码"
echo ""
echo "常用管理命令："
echo "  - 查看状态：vncserver -list"
echo "  - 停止服务：vncserver -kill :2"
echo "  - 重启服务：vncserver -kill :2 && vncserver :2 -geometry 1920x1080 -depth 24"
echo "  - 查看日志：tail -f ~/.vnc/*.log"
echo ""
echo "远程访问（通过 SSH 隧道）："
echo "  ssh -L 5902:localhost:5902 user@remote_host"
echo "  然后连接 localhost:5902"
echo ""
