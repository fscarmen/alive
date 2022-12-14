# 【各协议代理测活】

* * *

# 目录

- [更新信息](README.md#更新信息)
- [脚本特点](README.md#脚本特点)
- [VPS 运行脚本](README.md#VPS-运行脚本)
- [鸣谢](README.md#鸣谢下列作者的文章和项目)

* * *

## 更新信息
2022.7.27 只测 socks 和 http 代理的 split.sh，并发处理，极快;    
测综合的 docker_split.sh，由于vmess和vless涉及的组合太多，故需要慢慢完善

## 脚本特点
* 代码开源透明，不会收集上报信息。原理：1、vps 本地安装官方 v2ray 和官方 alpine docker (升级 curl 指令)，2、docker 通过 v2ray 连外网，3、逐一测试代理是否正确从 ip.sb 获取 IP ，4、最终把成功和失败的代理输出到 vps 本地文件
* 支持多种主流协议: vmess, vless (XTLS除外), ss, socks5, https, trojan
* 把经测试可用的代理，按用户指定个数分割为 N 个文件，不可用的代理输出为一个文件, 结果输出有提示
* 脚本运行完会删除使用到的系统依赖、v2ray 和 alpine docker
* 使用 docker_split 将会安装最新版 v2ray，请使用没有安装 xray 和 v2ray 的并且有 IPv4 网络的 VPS 上运行，以免冲突
* 把所有的代理放入一个检测文件中，一行一个代理

<img width="40%" alt="image" src="https://user-images.githubusercontent.com/62703343/181262082-8888fb0c-23d8-4da4-87a5-f6598381582f.png">

<img width="70%" alt="image" src="https://user-images.githubusercontent.com/62703343/181262243-e3359dac-c26d-4ba8-9420-2084939bf177.png">


## VPS 运行脚本

### 1. 只测 socks5 和 https
```
bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/alive/main/split.sh)
```

### 2. 综合测 vmess, vless, ss, socks5, https, trojan
```
bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/alive/main/docker_split.sh)
```

### 3.带参数 (pass parameter)
  | paremeter 参数 | value 值 | describe 具体动作说明 |
  | --------------|--------- | ------------------- |
  | -f | 代理文件路径 | 可以是绝对路径或者相对路径 |
  | -n | 指定个数可用代理为一个文件| 如填0即为不分割 |

举例: 检测文件为 test 里的 socks5 和 https 代理，并把可用的以 10 个为一个文件输出
```
bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/alive/main/split.sh) -f test -n 10
```

## 鸣谢下列作者的文章和项目

互联网永远不会忘记，但人们会。

技术文章和相关项目（排名不分先后）:
* StarOnTheSky: https://github.com/staronthesky
* v2ray 项目团队: https://github.com/v2fly/v2ray-core
* xray 项目团队: https://github.com/XTLS/Xray-core

服务提供（排名不分先后）:
* 获取公网 IP 及归属地查询: https://ip.sb/
