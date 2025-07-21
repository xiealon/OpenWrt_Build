# 默认ip 192.168.100.1  本项目为x86_64平台
# 可以修改为其他平台 不过对应的config记得修改
# 324/8334 allpass 对应kexec-tools
#
# 修改LAN口 IP 两个地方都要更改为你想要的IP地址
#
# 定义源部分可以自己添加了！安装从前到后强制顺序进行
# 请不要调整alon源的(第一个安装源)位置 请确保源已经添加，并将源名称(例如alon)已经添加到定义源部分
#
# 如果改成旁路由可以进入diy.sh 把忽略lan口的DHCP
# 所有接口设置为LAN口 删除WAN口的 #号去掉 
# 旁路由记得设置网关 uci set network.lan.gateway=""
# 旁路由网关设置成主路由 主路由不需要动.
#
# 本项目从Ing （wjz304）  修改而来 
# 查看插件
https://github.com/xiealon/openwrt-packages
#
https://github.com/xiealon/openwrt-package
#
https://github.com/xiealon/small
# 脚本互指 精简build.sh 三个源地址可以修改  
# 按照alon alon1 alon2 顺序进行安装软件 
# FORK后只需要更换alon.sh里面三个源地址即可 
# 注意alon源不要更换，防止默认插件没有安装
#
# 特别注意 .config的名称 不要更改格式
# .config名称按照格式 lede;Alon;x86_64_Xxxx
# 最好不要修改.config名称 #

# 怎么使用该项目：
  #1，登录/注册github账号 建议使用使用邮箱📮-
  
  #2，fork该项目的nain分支到你的仓库(其他均为备用无需fork)-
  
  #3，进入你fork的项目 安装上述操作diy完成后或者直接点击-
  
    上方action，enable action功能  进入build OpenWrt
    
    点击右上角的 new workflow 点击运行 等待action完成即可。
