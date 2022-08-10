#!/usr/bin/env bash

# 更新日期 2022-8-10

# 定义 v2ray 的端口
V2RAY_PORT='8080'
NAME='check_proxy'

# 最大后置测活次数
CHECK_TIME='3'

# 环境变量
arry=('|' '/' '-' '\')

# 传参
while getopts “:N:n:F:f:” OPTNAME; do
  case "$OPTNAME" in
    'N'|'n' ) NUM=$OPTARG;;
    'F'|'f' ) FILE_PATH=$OPTARG;;
  esac
done

# 自定义字体彩色,read 函数,安装依赖函数
red(){ echo -e "\033[31m\033[01m$@\033[0m"; }
green(){ echo -e "\033[32m\033[01m$@\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$@\033[0m"; }
reading(){ read -rp "$(green "$1")" "$2"; }

# 必须以root运行脚本
[[ $(id -u) != 0 ]] && red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1

# 判断 CPU 架构
ARCHITECTURE=$(uname -m)
case "$ARCHITECTURE" in
  aarch64 ) ARCH='arm64'; V2RAY='arm64-v8a';;
  x64|x86_64|amd64 ) ARCH='amd64'; V2RAY='64';;
  * ) red " ERROR: Unsupported architecture: $ARCHITECTURE\n" && exit 1;;
esac

# 判断操作系统
CMD=(	"$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)"
	"$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)"
	"$(lsb_release -sd 2>/dev/null)"
	"$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)"
	"$(grep . /etc/redhat-release 2>/dev/null)"
	"$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')"
	)

for i in "${CMD[@]}"; do SYS="$i" && [[ -n $SYS ]] && break; done

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "alpine" "arch linux")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine" "Arch")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f" "pacman -S --noconfirm")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f" "pacman -Rcnsu --noconfirm")

for ((int=0; int<${#REGEX[@]}; int++)); do
	[[ $(tr '[:upper:]' '[:lower:]' <<< $SYS) =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && break
done

# 输入检测文件路径和分割数量,并作初步检测
[[ -z $FILE_PATH ]] && reading "\n Enter proxy file PATH. For example: /root/proxy.conf : " FILE_PATH
[[ ! -e $FILE_PATH ]] && red " ERROR: Proxy file is not exist.\n" && exit 1
[[ -z $(cat $FILE_PATH) ]] && red " ERROR: There is not any proxy.\n" && exit 1
[[ -z $NUM ]] && reading "\n Enter quantity in splits.(Default is 999999): " NUM
echo $NUM | grep -q "[^0-9]" && red " ERROR: $NUM is not an integer.\n" && exit 1
[[ $NUM = 0 || -z $NUM ]] && NUM=999999

# 脚本开始时间
START=$(date +%s)

# 安装 python3 以支持 json 格式, dos2unix 依赖，把 windows 文件格式化成 unix 使用的, wget 和 unzip 依赖
DEPENDENCIES=(wget python3 unzip dos2unix)
for i in ${DEPENDENCIES[@]}; do
  ! type -p $i >/dev/null 2>&1 && NEED_REMOVE=($i ${NEED_REMOVE[@]})
done
[ ${#NEED_REMOVE[@]} != 0 ] && yellow "\n Install ${NEED_REMOVE[@]}\n" && ${PACKAGE_INSTALL[int]} ${NEED_REMOVE[@]}

# 把 windows 文件格式化成 unix 使用的
dos2unix $FILE_PATH

# 宿主机安装 v2ray
if ! systemctl is-enabled v2ray >/etc/null 2>&1; then
  yellow " \n Install v2ray \n "
  ${PACKAGE_UNINSTALL[int]} netfilter-persistent
  wget --no-check-certificate -O ./v2ray-linux-$V2RAY.zip https://github.com/v2fly/v2ray-core/releases/download/v4.45.0/v2ray-linux-$V2RAY.zip
  mkdir -p /etc/v2ray
  unzip -d /etc/v2ray v2ray-linux-*.zip
  cp /etc/v2ray/vpoint_vmess_freedom.json /etc/v2ray/config.json
  sed -i "s/ExecStart.*/ExecStart=\/etc\/v2ray\/v2ray -config \/etc\/v2ray\/config.json/g" /etc/v2ray/systemd/system/v2ray.service
  cp /etc/v2ray/systemd/system/v2ray.service /lib/systemd/system/
  systemctl enable --now v2ray
  ! systemctl is-enabled v2ray >/etc/null 2>&1 && red "\n ERROR: v2ray doesn't work.\n" && exit 1
  rm -f v2ray-linux-*.zip
fi

# 创建 iptables 规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
iptables -t nat -D PREROUTING -s 172.20.0.1 -p tcp -j RETURN >/dev/null 2>&1
iptables -t nat -D PREROUTING -s 172.20.0.0/16 -p tcp -j DNAT --to-destination 172.20.0.1:$V2RAY_PORT >/dev/null 2>&1
iptables -t nat -A PREROUTING -s 172.20.0.1 -p tcp -j RETURN
iptables -t nat -A PREROUTING -s 172.20.0.0/16 -p tcp -j DNAT --to-destination 172.20.0.1:$V2RAY_PORT

# 宿主机安装 docker 和 wireguard 内核
! systemctl is-active docker >/dev/null 2>&1 && green " \n Install docker \n " && curl -sSL get.docker.com | sh
systemctl is-enabled docker | grep -qv enabled && systemctl enable --now docker

# 代理的话创建 172.20.0.0/16 网段，用与区分 warp 的 172.17.0.0/16
[[ ! $(docker network list) =~ $NAME ]] && docker network create --subnet=172.20.0.0/16 $NAME

# 创建一个测活容器
docker pull fscarmen/alive:latest
docker ps -a | awk '{print $NF}' | tail -n +2 | grep -q $NAME ||
docker run -dit --restart=always --name $NAME --net $NAME --ip 172.20.0.2 --sysctl net.ipv6.conf.all.disable_ipv6=0 --device /dev/net/tun --privileged --cap-add net_admin --cap-add sys_module --log-opt max-size=1m -v /lib/modules:/lib/modules fscarmen/alive:latest

# 删除旧文件
rm -f $FILE_PATH-*

# 代理去重
REMOVE_PROXIES=($(sort -u $FILE_PATH))
for ((u=0; u<$CHECK_TIME; u++)); do
  v=0
  PROXIES_NUM=${#REMOVE_PROXIES[@]}
  green "\n Check proxies alive $((u+1)) / $CHECK_TIME "
  [ "$u" = 0 ] && yellow " Check all the ${#REMOVE_PROXIES[@]} proxies. " || yellow " Recheck ${#REMOVE_PROXIES[@]} proxies.  "
  for h in ${REMOVE_PROXIES[@]}; do
    PROXY_NOW="$h"
    ((v++))
    index=$(( v % 4 ))
    VAL=$(( v * 100 / PROXIES_NUM ))
    printf " %c %3d%% %c\r" "${arry[$index]}" "$VAL" "${arry[$index]}"

    # socks 协议
    if echo "$h" | grep -q "^socks"; then
      if echo "$PROXY_NOW" | grep -q "@"; then
        TEST_USER=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:@] '{print $1}')
        TEST_PASSWORD=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:@] '{print $2}')
        TEST_IP=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:@] '{print $3}')
        TEST_PORT=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:@] '{print $4}')
      else
        TEST_IP=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:] '{print $1}')
        TEST_PORT=$(echo $PROXY_NOW | sed 's#socks.://##g' | awk -F [:] '{print $2}')
      fi
      JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"socks\", \"settings\": { \"servers\": [ { \"address\": \"$TEST_IP\", \"port\": $TEST_PORT, \"users\": [ { \"user\": \"$TEST_USER\", \"pass\": \"$TEST_PASSWORD\" } ] } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"

    elif
      # http(s) 协议
      echo "$PROXY_NOW" | grep -q "^http"; then
      if echo "$PROXY_NOW" | grep -q "@"; then
        TEST_USER=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:@] '{print $1}')
        TEST_PASSWORD=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:@] '{print $2}')
        TEST_IP=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:@] '{print $3}')
        TEST_PORT=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:@] '{print $4}')
      else
        TEST_IP=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:] '{print $1}')
        TEST_PORT=$(echo $PROXY_NOW | sed 's#http://##g' | awk -F [:] '{print $2}')
      fi
      JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"http\", \"settings\": { \"servers\": [ { \"address\": \"$TEST_IP\", \"port\": $TEST_PORT, \"users\": [ { \"user\": \"$TEST_USER\", \"pass\": \"$TEST_PASSWORD\" } ] } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"

    elif
      # vmess 协议
      echo "$PROXY_NOW" | grep -q "^vmess"; then

      # 传输协议为 ws
      if echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | grep -q '"net":[[:space:]]*"ws"'; then
        WS_ID=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"id":' | cut -d\" -f4)
        WS_ADD=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"add":' | cut -d\" -f4)
        WS_HOST=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"host":' | cut -d\" -f4)
        WS_PATH=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"path":' | cut -d\" -f4 | sed 's#%2[Ff]#/#g')
        WS_PORT=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"port":' | grep -oP "\d+")

        if echo "$PROXY_NOW" | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep -q '"tls":[[:space:]]*"tls"'; then
          # 安全类型为 tls,即为 vmess + ws + tls
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vmess\", \"streamSettings\": { \"network\": \"ws\", \"security\": \"tls\", \"wsSettings\": { \"path\": \"$WS_PATH\", \"headers\": { \"host\": \"$WS_HOST\" } }, \"tlsSettings\": { \"serverName\": \"$WS_HOST\", \"allowInsecure\": false } },  \"settings\": { \"vnext\": [ { \"address\": \"$WS_ADD\", \"users\": [ { \"id\": \"$WS_ID\", \"alterId\": 0, \"level\": 0, \"security\": \"aes-128-gcm\" } ], \"port\": $WS_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        else
          # 安全类型为 tls,即为 vmess + ws + none
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vmess\", \"streamSettings\": { \"network\": \"ws\", \"security\": \"none\", \"wsSettings\": { \"path\": \"$WS_PATH\", \"headers\": { \"host\": \"$WS_HOST\" } } },  \"settings\": { \"vnext\": [ { \"address\": \"$WS_ADD\", \"users\": [ { \"id\": \"$WS_ID\", \"alterId\": 0, \"level\": 0, \"security\": \"aes-128-gcm\" } ], \"port\": $WS_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        fi
      else
        # 传输协议为 tcp
        TCP_ID=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"id":' | cut -d\" -f4)
        TCP_ADD=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"add":' | cut -d\" -f4)
        TCP_PORT=$(echo $PROXY_NOW | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep '"port":' | grep -oP "\d+")

        if echo "$PROXY_NOW" | sed "s#vmess://##g" | base64 -d | python3 -m json.tool | grep -q '"tls":[[:space:]]*"tls"'; then
          # 安全类型为 tls,即为 vmess + tcp + tls
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vmess\", \"streamSettings\": { \"network\": \"tcp\", \"tcpSettings\": { \"header\": { \"type\": \"none\" } }, \"security\": \"tls\" , \"tlsSettings\": { \"allowInsecure\": false } }, \"settings\": { \"vnext\": [ { \"address\": \"$TCP_ADD\", \"users\": [ { \"id\": \"$TCP_ID\", \"alterId\": 0, \"level\": 0, \"security\": \"aes-128-gcm\" } ], \"port\": $TCP_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        else
          # 类型为 tls,即为 vmess + tcp + none
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vmess\", \"streamSettings\": { \"network\": \"tcp\", \"tcpSettings\": { \"header\": { \"type\": \"none\" } }, \"security\": \"none\" }, \"settings\": { \"vnext\": [ { \"address\": \"$TCP_ADD\", \"users\": [ { \"id\": \"$TCP_ID\", \"alterId\": 0, \"level\": 0, \"security\": \"aes-128-gcm\" } ], \"port\": $TCP_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        fi
      fi
    elif
      # vless 协议
      echo "$PROXY_NOW" | grep -q "^vless"; then

      # 传输协议为 ws
      if echo $PROXY_NOW | grep -q 'type=ws'; then
        WS_ID=$(echo $PROXY_NOW | sed 's#vless://\([^@]\+\).*#\1#g')
        WS_ADD=$(echo $PROXY_NOW | sed 's#.*@\([^:]\+\).*#\1#g')
        WS_HOST=$(echo $PROXY_NOW | sed 's#.*host=\([^&#]\+\).*#\1#g')
        WS_PATH=$(echo $PROXY_NOW | sed 's#.*path=\([^&#]\+\).*#\1#g' | sed 's#%2[Ff]#/#g')
        WS_PORT=$(echo $PROXY_NOW | sed "s#.*:\([0-9]\+\)?.*#\1#g")
        
        if echo $PROXY_NOW | grep -q 'security=tls'; then
          # 安全类型为 tls,即为 vless + ws + tls
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vless\", \"streamSettings\": { \"network\": \"ws\", \"security\": \"tls\", \"wsSettings\": { \"path\": \"$WS_PATH\", \"headers\": { \"host\": \"$WS_HOST\" } }, \"tlsSettings\": { \"serverName\": \"$WS_HOST\", \"allowInsecure\": false } }, \"settings\": { \"vnext\": [ { \"address\": \"$WS_ADD\", \"users\": [ { \"encryption\": \"none\", \"id\": \"$WS_ID\", \"level\": 0, \"flow\": \"\" } ], \"port\": $WS_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        else
          # 安全类型为 tls,即为 vless + ws + none
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vless\", \"streamSettings\": { \"network\": \"ws\", \"security\": \"none\", \"wsSettings\": { \"path\": \"$WS_PATH\", \"headers\": { \"host\": \"$WS_HOST\" } } }, \"settings\": { \"vnext\": [ { \"address\": \"$WS_ADD\", \"users\": [ { \"encryption\": \"none\", \"id\": \"$WS_ID\", \"level\": 0, \"flow\": \"\" } ], \"port\": $WS_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        fi
      else
        # 传输协议为 tcp
        TCP_ID=$(echo $PROXY_NOW | sed 's#vless://\([^@]\+\).*#\1#g')
        TCP_ADD=$(echo $PROXY_NOW | sed 's#.*@\([^:]\+\).*#\1#g')
        TCP_PORT=$(echo $PROXY_NOW | sed "s#.*:\([0-9]\+\)?.*#\1#g")

        if echo $PROXY_NOW | grep -q 'security=tls'; then
          # 安全类型为 tcp, 即为 vless + tcp + tls
          TCP_SNI=$(echo $PROXY_NOW | sed 's#.*sni=\([^#]\+\).*#\1#g')
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vless\", \"streamSettings\": { \"network\": \"tcp\", \"security\": \"tls\", \"tcpSettings\": { \"header\": { \"type\": \"none\" } }, \"tlsSettings\": { \"serverName\": \"$TCP_SNI\", \"allowInsecure\": false } }, \"tag\": \"proxy\", \"settings\": { \"vnext\": [ { \"address\": \"$TCP_ADD\", \"users\": [ { \"encryption\": \"none\", \"id\": \"$TCP_ID\", \"level\": 0, \"flow\": \"\" } ], \"port\": $TCP_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"
        else
          # 类型为 tcp, 即为 vless + tcp + none
          JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"mux\": { \"enabled\": false, \"concurrency\": 8 }, \"protocol\": \"vless\", \"streamSettings\": { \"network\": \"tcp\", \"security\": \"none\", \"tcpSettings\": { \"header\": { \"type\": \"none\" } } }, \"settings\": { \"vnext\": [ { \"address\": \"$TCP_ADD\", \"users\": [ { \"encryption\": \"none\", \"id\": \"$TCP_ID\", \"level\": 0, \"flow\": \"\" } ], \"port\": $TCP_PORT } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"          
        fi
      fi
    elif
      # ss 协议
      echo "$PROXY_NOW" | grep -q "^ss://"; then
        # 新版格式带 @ 后面的地址和端口是明文的
      if echo "$PROXY_NOW" | grep -q "@"; then
        SS_METHOD=$(echo $PROXY_NOW | sed 's#ss://##g' | cut -d '@' -f1 | base64 -d 2>/dev/null | cut -d : -f1)
        SS_PASSWORD=$(echo $PROXY_NOW | sed 's#ss://##g' | cut -d '@' -f1 | base64 -d  2>/dev/null  | cut -d : -f2)
        SS_ADD=$(echo $PROXY_NOW | sed "s/.*@\([^:]\+\).*/\1/g")
        SS_PORT=$(echo $PROXY_NOW | sed "s/.*:\([0-9]\+\).*/\1/g")
      else
        # 旧版本格式，全部经过 base64 encode 的
        SS_METHOD=$(echo $PROXY_NOW | sed 's#ss://\([^#]\+\).*#\1#g' | base64 -d 2>/dev/null | cut -d@ -f1 | cut -d: -f1)
        SS_PASSWORD=$(echo $PROXY_NOW | sed 's#ss://\([^#]\+\).*#\1#g' | base64 -d 2>/dev/null | cut -d@ -f1 | cut -d: -f2)
        SS_ADD=$(echo $PROXY_NOW | sed 's#ss://\([^#]\+\).*#\1#g' | base64 -d 2>/dev/null | cut -d@ -f2 | cut -d: -f1)
        SS_PORT=$(echo $PROXY_NOW | sed 's#ss://\([^#]\+\).*#\1#g' | base64 -d 2>/dev/null | cut -d@ -f2 | cut -d: -f2)
      fi
      JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"protocol\": \"shadowsocks\", \"streamSettings\": { \"network\": \"tcp\", \"tcpSettings\": { \"header\": { \"type\": \"none\" } }, \"security\": \"none\" }, \"settings\": { \"servers\": [ { \"port\": $SS_PORT, \"method\": \"$SS_METHOD\", \"password\": \"$SS_PASSWORD\", \"address\": \"$SS_ADD\", \"level\": 0, \"email\": \"\", \"ota\": false } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"

    elif
      # trojan 协议
      echo "$PROXY_NOW" | grep -q "^trojan://"; then
        TROJAN_PASSWORD=$(echo $PROXY_NOW | sed 's#trojan://\([^#]\+\).*#\1#g' | cut -d@ -f1)
        TROJAN_ADD=$(echo $PROXY_NOW | sed "s#.*@\([^:]\+\).*#\1#g")
        TROJAN_PORT=$(echo $PROXY_NOW | sed "s#.*:\([0-9]\+\)?.*#\1#g")
        echo $PROXY_NOW | grep -q 'sni=' && TROJAN_SNI=$(echo $PROXY_NOW | sed "s#.*sni=\([^&#]\+\).*#\1#g") || TROJAN_SNI=$TROJAN_ADD
      JSON="{ \"inbounds\": [ { \"listen\": \"172.20.0.1\", \"port\": $V2RAY_PORT, \"protocol\": \"dokodemo-door\", \"settings\": { \"network\": \"tcp,udp\", \"followRedirect\": true }, \"sniffing\": { \"enabled\": true, \"destOverride\": [ \"http\", \"tls\" ] } } ], \"policy\": { \"levels\": { \"0\": { \"statsUserDownlink\": true, \"statsUserUplink\": true } }, \"system\": { \"statsInboundUplink\": true, \"statsInboundDownlink\": true } }, \"outbounds\": [ { \"tag\": \"proxy\", \"protocol\": \"trojan\", \"streamSettings\": { \"tcpSettings\": { \"header\": { \"type\": \"none\" } }, \"tlsSettings\": { \"serverName\": \"$TROJAN_SNI\", \"allowInsecure\": true }, \"security\": \"tls\", \"network\": \"tcp\" }, \"settings\": { \"servers\": [ { \"password\": \"$TROJAN_PASSWORD\", \"port\": $TROJAN_PORT, \"email\": \"\", \"level\": 0, \"address\": \"$TROJAN_ADD\" } ] } } ], \"routing\": { \"rules\": [ { \"type\": \"field\", \"outboundTag\": \"proxy\", \"source\": [ \"172.20.0.2\" ] }, { \"type\": \"field\", \"network\": \"tcp,udp\", \"outboundTag\": \"direct\" } ] } }"

    fi
        
    systemctl stop v2ray
    echo $JSON | python3 -m json.tool > /etc/v2ray/config.json
    sleep 1 
    systemctl start v2ray
    sleep 1
    [[ $(docker exec -i $NAME curl -s4m$[u * 2 + 4] http://ip.sb | wc -l) = 1 ]] &&
 OK_PROXIES=($(echo ${OK_PROXIES[@]}) $PROXY_NOW) && REMOVE_PROXIES=(${REMOVE_PROXIES[@]//$PROXY_NOW/})
  done
  echo ''
done

# 删除 v2ray
yellow " Remove temp files "
systemctl disable --now v2ray
rm -rf /etc/v2ray/ /lib/systemd/system/v2ray.service

# 删除测试 docker 和网段名
docker rm -f $NAME
docker network rm $NAME
docker rmi -f fscarmen/alive:latest

# 删除防火墙相关规则
iptables -t nat -D PREROUTING -s 172.20.0.1 -p tcp -j RETURN
iptables -t nat -D PREROUTING -s 172.20.0.0/16 -p tcp -j DNAT --to-destination 172.20.0.1:$V2RAY_PORT

# 删除本脚本安装的系统依赖
[ ${#NEED_REMOVE[@]} != 0 ] && yellow "\n Uninstall ${NEED_REMOVE[@]}\n" && ${PACKAGE_UNINSTALL[int]} ${NEED_REMOVE[@]}

# 结束时间，计算运行时长
END=$(date +%s)
RUNTIME=$[ END - START ]
DAY=$[ RUNTIME / 86400 ]
HOUR=$[ (RUNTIME % 86400 ) / 3600 ]
MIN=$[ (RUNTIME % 86400 % 3600) / 60 ]
SEC=$[ RUNTIME % 86400 % 3600 % 60 ]

# 输入结果并分发文件
[ "${#REMOVE_PROXIES[@]}" != 0 ] && echo "${REMOVE_PROXIES[@]}" | grep -oP "\K\S+" > $FILE_PATH-unavailable

if [ "${#OK_PROXIES[@]}" = 0 ]; then
  red "\n No proxy now !\n Runing time: $DAY days $HOUR hours $MIN minutes $SEC seconds\n " && exit
else
  echo "${OK_PROXIES[@]}" | grep -oP "\K\S+" > $FILE_PATH.available
  split -l $NUM $FILE_PATH.available -d $FILE_PATH-
  rm -f $FILE_PATH.available
  green " Result:\n ${#OK_PROXIES[@]} proxies are available in $(cat $FILE_PATH | sed "/^[[:space:]]*$/d" | wc -l). "
  ls | egrep -q "^$FILE_PATH-[0-9]+$" && green " Split into $(ls | egrep "^$FILE_PATH-[0-9]+$" | wc -l) files: $(ls | egrep "^$FILE_PATH-[0-9]+$" | paste -sd " "). "
  [ -e $FILE_PATH-unavailable ] && red " Unavailable proxies are in file: $FILE_PATH-unavailable. "
  green " Runing time: $DAY days $HOUR hours $MIN minutes $SEC seconds.\n "
fi
