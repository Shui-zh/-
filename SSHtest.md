1.约定ip：
控制端ip：192.168.8.100
掩码：255.255.255.0
车机端ip：192.168.8.250

2.ping ip，测试是否连通

3.车机端开启SSH服务：
执行：
sudo apt update
sudo apt install openssh-server
sudo systemctl enable --now ssh
systemctl status ssh

4.控制端登录：
ssh 车机端用户名@192.168.8.250
输入车机端密码

5.创建和连接VNC隧道:
确保服务端（车机）已开启SSH服务和VNC
VNC服务打开：
打开“设置”->“共享”->"远程桌面"
开启远程桌面，旧式VNC协议，远程控制，设置用户名和密码

客户端:
打开remmina
在基本中填写相应信息，服务器这栏填192.168.8.250：5900
