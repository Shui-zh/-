# RoboMaster 双端配置实现（Ubuntu 22.04 + ROS2 Humble）

> 本文所有关键命令已于 2026-11-23 联网核对：ROS 2 官方 Humble 安装文档（Ubuntu Jammy deb 版）、ROS 2 官方 ROS_DOMAIN_ID 文档、Eclipse Cyclone DDS 官方 Discovery 配置文档。

两台机器：

| 角色  | 设备                       | 系统           | IP              |
| --- | ------------------------ | ------------ | --------------- |
| 被控端 | **哨兵**车载上位机（Jetson / 妙算 / NUC） | Ubuntu 22.04 | `192.168.8.250` |
| 主控端 | 调试笔记本                    | Ubuntu 22.04 | `192.168.8.99`  |

> 哨兵 IP 已按实际环境固定为 `192.168.8.250`（网段 192.168.8.x）。笔记本选了 `192.168.8.99`，若与车上其他设备冲突任选一个空闲地址即可。

Ubuntu 22.04（jammy）对应 ROS2 **Humble**。

> **两端均已装好 Ubuntu 系统 + ROS2 环境**，本文不再涉及安装，只做：网络配置 → SSH/VNC 服务 → 环境对齐（以车机为准）→ 联调验证。

---

## 通用约定

1. 用户名用 `<用户名>` 占位，替换成你实际的账号。
2. `ROS_DOMAIN_ID` 两端必须**完全一致**。官方建议取 **0–101** 之间（避开 Linux 内核临时端口 32768–60999）。
3. **`RMW_IMPLEMENTATION` 两端必须一致**。**车机已装好 ROS2 环境，原则是笔记本向车机对齐**：车机用什么 DDS 就用什么，`ROS_DOMAIN_ID` 也照抄车机的。只有跨机发现失败、且车机允许改动时，才两端一起切 Cyclone DDS（见第四部分）。
4. 网线直连不设网关/DNS。哨兵在 `192.168.8.x` 网段，与 Livox 雷达默认的 `192.168.1.x` 网段**天然不冲突**，这正好是选 8 网段的好处；但要注意同网段内其他设备（图传、裁判系统、队友调试机）不要撞地址。

---

# 第一部分：被控端（车载上位机）

## 步骤 1：设置静态 IP

```bash
ip -br link        # 查网卡名，如 enp3s0 / eth0 / eno1
```

新建独立配置文件（不覆盖系统原有配置，避免冲突）：

```bash
sudo nano /etc/netplan/99-direct-link.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:                  # 换成你的网卡名
      dhcp4: no
      dhcp6: no
      addresses: [192.168.8.250/24]
```

```bash
sudo netplan apply
ip -br addr show enp3s0      # 应看到 192.168.8.250/24
```

> 桌面版若由 NetworkManager 管理该网卡，用 nmcli 代替，二者不要同时管同一网卡：
>
> ```bash
> sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.8.250/24
> sudo nmcli con up "Wired connection 1"
> ```

## 步骤 2：核对已有 ROS2 环境（车机已装，跳过安装）

确认 DDS/RMW 实现和 ROS_DOMAIN_ID、确认工作空间位置。这些参数决定了笔记本端怎么配——**原则是笔记本向车机对齐，不动车机**。

### 2.1 探查车机现状（SSH 上去逐条执行）

ls ~/ | grep -i ws                   # 工作空间在哪，如 ros2_ws / catkin_ws(ROS1)
grep -E "ROS|source" ~/.bashrc       # 看它自己写了哪些环境变量
ros2 doctor --report | grep middleware   # 实际生效的 DDS 实现
```

### 2.2 判断结果

- **RMW_IMPLEMENTATION 为空**：默认 Fast DDS（`rmw_fastrtps_cpp`）。**优先让笔记本也保持默认 Fast DDS**，只在跨机发现失败时再考虑两端一起切 Cyclone DDS——切换要改车机配置，能不动就不动。
- **ROS_DOMAIN_ID 已设置**（比如车队自定义的 ID）：笔记本写**一模一样**的值。
- **已有 CYCLONEDDS_URI / cyclonedds.xml**：读一下内容，笔记本照抄并只改 Peer Address 为对方 IP。

### 2.3 笔记本按探查结果写环境变量（对齐示例）

```bash
echo "export ROS_DOMAIN_ID=<车机的值>" >> ~/.bashrc
# 若车机用了 Cyclone DDS：
echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" >> ~/.bashrc
echo "export CYCLONEDDS_URI=file://$HOME/.cyclonedds/cyclonedds.xml" >> ~/.bashrc
source ~/.bashrc
```

## 步骤 3：安装 SSH 服务端

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
systemctl is-active ssh           # active
```

## 步骤 4：安装 TigerVNC 服务端

```bash
sudo apt install -y tigervnc-standalone-server tigervnc-common xfce4
vncpasswd                          # 设置 VNC 密码（存到 ~/.vnc/passwd）
```

写启动脚本：

```bash
cat > ~/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup
```

先手动验证能起来：

```bash
vncserver :1 -geometry 1280x720 -depth 24 -localhost
```

- `:1` 对应端口 **5901**（端口 = 5900 + display 号）
- `-localhost` 只监听 127.0.0.1，必须走 SSH 隧道访问，安全性高

确认可用后配开机自启 `/etc/systemd/system/vncserver@.service`：

```ini
[Unit]
Description=TigerVNC server (%i)
After=syslog.target network.target

[Service]
Type=forking
User=<用户名>
PAMName=login
PIDFile=/home/<用户名>/.vnc/%H:%i.pid
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :%i > /dev/null 2>&1 || true'
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1280x720 -localhost :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vncserver@1.service
systemctl status vncserver@1.service --no-pager
```

> Jetson 资源紧张，不用时 `vncserver -kill :1` 或 `sudo systemctl stop vncserver@1` 释放资源。

## 步骤 5：串口权限与防火墙

串口（上位机 ↔ STM32）：

```bash
sudo usermod -aG dialout <用户名>    # 需重新登录生效
ls /dev/ttyUSB* /dev/ttyACM*          # 确认设备节点
dmesg | grep -i ttyUSB                # 看识别日志
```

防火墙（直连场景只信任本网段）：

```bash
sudo ufw allow from 192.168.8.0/24
sudo ufw enable
```

> 若要走 ROS 2 跨机通信，ufw 对 DDS 的 UDP 端口处理较麻烦，直连调试期间也可先 `sudo ufw disable`，调通后再按需收紧。

## 步骤 6：被控端自检

```bash
ip -br addr                    # 192.168.8.250
systemctl is-active ssh vncserver@1.service
ros2 run demo_nodes_cpp talker # 能正常输出 Publishing 即 ROS2 环境 OK
nvidia-smi                     # Jetson：GPU / 显存
df -h                          # eMMC 剩余空间
```

---

# 第二部分：主控端（调试笔记本）

## 步骤 1：设置静态 IP

同样新建 `/etc/netplan/99-direct-link.yaml`：

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: no
      dhcp6: no
      addresses: [192.168.8.99/24]
```

```bash
sudo netplan apply
ping -c 3 192.168.8.250
```

## 步骤 2：核对已有 ROS2 环境并对齐车机（两端都已装，跳过安装）

笔记本和车机都已有 ROS2 环境，本步骤不装任何东西，只做**对齐**。先探查笔记本自己的现状：

```bash
printenv | grep -E "ROS_DISTRO|ROS_DOMAIN_ID|RMW_IMPLEMENTATION|CYCLONEDDS_URI"
ros2 doctor --report | grep middleware
```

然后按第一部分 2.2 的规则与车机对齐（**车机为准**）：

| 检查项 | 要求 | 笔记本写法 |
| --- | --- | --- |
| `ROS_DOMAIN_ID` | 两端完全一致 | `echo "export ROS_DOMAIN_ID=<车机的值>" >> ~/.bashrc` |
| RMW / DDS | 两端一致 | 车机用 Cyclone 才加 `RMW_IMPLEMENTATION` 和 `CYCLONEDDS_URI`（文件照抄车机的，只改 Peer Address 为 192.168.8.250） |

改完 `source ~/.bashrc`。


## 步骤 3：SSH 免密 + 别名

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_car          # 一路回车
ssh-copy-id -i ~/.ssh/id_ed25519_car.pub <用户名>@192.168.8.250
```

编辑 `~/.ssh/config`：

```
Host car
    HostName 192.168.8.250
    User <用户名>
    IdentityFile ~/.ssh/id_ed25519_car
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

```bash
chmod 600 ~/.ssh/config
ssh car 'echo ok'
```

## 步骤 4：VNC 查看器 + SSH 隧道

```bash
sudo apt install -y tigervnc-viewer
```

被控端用了 `-localhost`，必须先建隧道（保持该终端不关）：

```bash
ssh -L 5901:localhost:5901 -N car
```

另开终端：

```bash
vncviewer localhost:5901
```

## 步骤 5：主控端自检

```bash
ping -c 3 192.168.8.250
ssh car 'echo ok'
ros2 node list          # 应能看到车载机上的节点
```

---

# 第三部分：联调验证（按顺序）

```bash
# 1. 网络
ping -c 3 192.168.8.250

# 2. SSH
ssh car 'hostname'

# 3. ROS2 跨机发现（两端都执行，应互相看到）
ros2 node list

# 4. 话题通信：车载机发布，笔记本订阅
# 车载机：
ssh car 'ros2 topic pub /test std_msgs/msg/String "{data: hello}" --once'
# 笔记本（另开终端）：
ros2 topic echo /test --once

# 5. VNC
ssh -L 5901:localhost:5901 -N car    # 终端 A
vncviewer localhost:5901             # 终端 B
```

### 发现失败先做多播自检

```bash
# 车载机
ros2 multicast receive
# 笔记本
ros2 multicast send
```

收不到就说明该链路的多播被拦（直连、虚拟网卡、某些驱动都会），走下面的单播 Peer 方案。

---

# 第四部分：直连发现不了的解决办法（Cyclone DDS 单播 Peer）

Cyclone DDS 官方文档说明：除多播外，可在 `Discovery/Peers` 里写死对方的单播地址，每次 SPDP 报文都会发给这些地址。

## 配置文件写法（注意属性名是 `Address`，首字母大写）

车载端 `~/.cyclonedds/cyclonedds.xml`：

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CycloneDDS xmlns="https://cdds.io/config"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain id="any">
    <General>
      <Interfaces>
        <NetworkInterface name="enp3s0" priority="default" multicast="default"/>
      </Interfaces>
      <AllowMulticast>spdp</AllowMulticast>
    </General>
    <Discovery>
      <ParticipantIndex>auto</ParticipantIndex>
      <Peers>
        <Peer Address="192.168.8.99"/>
      </Peers>
      <MaxAutoParticipantIndex>50</MaxAutoParticipantIndex>
    </Discovery>
  </Domain>
</CycloneDDS>
```

笔记本端只改两处：`NetworkInterface name` 换成笔记本网卡名、`Peer Address` 换成 `192.168.8.250`。

要点：

- `<Peer Address="..."/>`：**`Address` 必须首字母大写**，写成小写 `address` 会被忽略。
- `<AllowMulticast>spdp</AllowMulticast>`：多播仅用于发现；也可写 `false` 完全关闭多播，纯靠 Peer。
- `<NetworkInterface name="...">`：**多网卡机器必须显式指定**（笔记本常有 Wi-Fi + 有线），否则 DDS 可能绑定到错误网卡导致发现失败。

## 启用配置

```bash
echo "export CYCLONEDDS_URI=file://$HOME/.cyclonedds/cyclonedds.xml" >> ~/.bashrc
source ~/.bashrc
```

路径必须是**绝对路径**且加 `file://` 前缀。两端都要配，然后重启 daemon 并重测：

```bash
ros2 daemon stop && ros2 daemon start
ros2 node list
```

想看 Cyclone 实际加载的配置：

```bash
CYCLONEDDS_URI='file:///home/<用户名>/.cyclonedds/cyclonedds.xml,//CycloneDDS/Domain/General/Tracing/Verbosity=config' ros2 topic list
```

---

## 附：命令速查

| 目的            | 命令                                                               |
| ------------- | ---------------------------------------------------------------- |
| 登录车载机         | `ssh car`                                                        |
| 跟日志           | `ssh car 'journalctl -f -u <服务>'`                                |
| 推代码           | `rsync -av ~/ws/src/ car:~/ros2_ws/src/`                         |
| 拉日志           | `scp car:/var/log/<日志> ./`                                       |
| 看话题频率         | `ssh car 'ros2 topic hz /cmd_vel'`                               |
| 看话题内容         | `ssh car 'ros2 topic echo /detection'`                           |
| Jetson 资源     | `ssh car 'nvidia-smi && free -h && df -h'`                       |
| 重启 ROS daemon | `ros2 daemon stop && ros2 daemon start`                          |
| 看视觉画面         | `ssh -L 5901:localhost:5901 -N car` + `vncviewer localhost:5901` |
| 串口调试          | `ssh car 'screen /dev/ttyUSB0 115200'`                           |
| 查 DDS 实际实现    | `ros2 doctor --report \| grep middleware`                        |

## 常见坑对照

| 现象                     | 原因 / 处理                                                                  |
| ---------------------- | ------------------------------------------------------------------------ |
| `ros2 node list` 只看到本机 | ROS_DOMAIN_ID 不一致 / RMW_IMPLEMENTATION 不一致 / 多播被拦 → 走 Peer 单播            |
| 多网卡机器发现不了              | Cyclone 只绑一张网卡，需 `<NetworkInterface name="...">` 显式指定                    |
| Peer 配了仍不通             | `Address` 写成小写 / 未重启 ros2 daemon / `CYCLONEDDS_URI` 路径不是绝对路径或无 `file://` |
| `ros2` 命令找不到           | 未 source `/opt/ros/humble/setup.bash`                                    |
| 装 ROS 时提示要删关键包         | 漏了 `sudo apt upgrade`（官方明确要求先升级 systemd/udev）                            |
| VNC 连不上                | 被控端用了 `-localhost`，必须先建 SSH 隧道                                           |
| VNC 黑屏                 | `xstartup` 内容不对或缺 Xfce；确认 `exec startxfce4`                              |
