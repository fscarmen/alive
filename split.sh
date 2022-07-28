#!/usr/bin/env bash

# 更新日期 2022-7-18

# 传参
while getopts “:N:n:F:f:” OPTNAME; do
  case "$OPTNAME" in
    'N'|'n' ) NUM=$OPTARG;;
    'F'|'f' ) FILE_PATH=$OPTARG;;
  esac
done

# 自定义字体彩色,read 函数，安装依赖函数
red(){ echo -e "\033[31m\033[01m$@\033[0m"; }
green(){ echo -e "\033[32m\033[01m$@\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$@\033[0m"; }
reading(){ read -rp "$(green "$1")" "$2"; }

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

# 输入检测文件路径和分割数量，并作初步检测
[[ -z $FILE_PATH ]] && reading "\n Enter proxy file PATH. For example: /root/proxy.conf : " FILE_PATH
[[ ! -e $FILE_PATH ]] && red " ERROR: Proxy file is not exist.\n" && exit 1
[[ -z $(cat $FILE_PATH) ]] && red " ERROR: There is not any proxy.\n" && exit 1
[[ -z $NUM ]] && reading "\n Enter quantity in splits.(Default is 999999): " NUM
echo $NUM | grep -q "[^0-9]" && red " ERROR: $NUM is not an integer.\n" && exit 1
[[ $NUM = 0 || -z $NUM ]] && NUM=999999

# 安装 python3 以支持 json 格式, dos2unix 依赖，把 windows 文件格式化成 unix 使用的, wget 和 unzip 依赖
DEPENDENCIES=(curl dos2unix)
for i in ${DEPENDENCIES[@]}; do
  ! type -p $i >/dev/null 2>&1 && NEED_REMOVE=($i ${NEED_REMOVE[@]})
done
[ ${#NEED_REMOVE[@]} != 0 ] && yellow "\n Install ${NEED_REMOVE[@]}\n" && ${PACKAGE_INSTALL[int]} ${NEED_REMOVE[@]}

# 把 windows 文件格式化成 unix 使用的
dos2unix $FILE_PATH

FILE=("$FILE_PATH" "$FILE_PATH-check1" "$FILE_PATH-check2")
TEMP=("$FILE_PATH-check1" "$FILE_PATH-check2" "$FILE_PATH-unavailable")
ECHO=("(1/3) 1st check the validity of proxies" "(2/3) 2nd recheck for unavailaxble proxies" "(3/3) 3rd recheck for unavailaxble proxies")
TIME_OUT=("3" "7" "10")

# 三次测代理可用性
rm -f $FILE_PATH-*
for ((b=0;b<${#FILE[@]};b++)); do
  unset CHECK_PROXY
  if [[ -n $(cat ${FILE[b]}) ]]; then
    yellow "\n ${ECHO[b]}\n"
    CHECK_PROXY=($(cat ${FILE[b]} | sed 's#^socks5://#socks5h://#g'))
    for a in "${CHECK_PROXY[@]}"; do
      { [ "$(curl -s4m${TIME_OUT[b]} -x $a ip.gs | wc -l)" = 1 ] && echo $a | sed 's#^socks5h://#socks5://#g' | tee -a $FILE_PATH.available >/dev/null 2>&1 || echo $a | sed 's#^socks5h://#socks5://#g' | tee -a ${TEMP[b]} >/dev/null 2>&1; }&
    done
    wait
  fi
done

# 删除本脚本安装的系统依赖
[ ${#NEED_REMOVE[@]} != 0 ] && yellow "\n Uninstall ${NEED_REMOVE[@]}\n" && ${PACKAGE_UNINSTALL[int]} ${NEED_REMOVE[@]}

# 输入结果并分发文件
[[ ! -e $FILE_PATH.available ]] && red "\n No proxy now !\n" && rm -f ${TEMP[0]} ${TEMP[1]} && exit
AVAILABLE=$(cat $FILE_PATH.available | wc -l)
split -l $NUM $FILE_PATH.available -d $FILE_PATH-
rm -f $FILE_PATH.available ${TEMP[0]} ${TEMP[1]}
ls | egrep -q "^$FILE_PATH-[0-9]+$" && green " Result:\n Split $AVAILABLE proxies into $(ls | egrep "^$FILE_PATH-[0-9]+" | wc -l) files: $(ls | egrep "^$FILE_PATH-[0-9]+$" | paste -sd " "). "
[ -e $FILE_PATH-unavailable ] && red " Unavailable proxies are in file: $FILE_PATH-unavailable. "
