---
id: 588
title: lvs DR模式均衡读请求
date: 2015-05-20T10:58:04+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=588
permalink: '/lvs-dr%e6%a8%a1%e5%bc%8f%e5%9d%87%e8%a1%a1%e8%af%bb%e8%af%b7%e6%b1%82/'
ultimate_sidebarlayout:
  - default
dsq_thread_id:
  - "4241201730"
dsq_needs_sync:
  - "1"
categories:
  - network
  - performance
tags:
  - lvs
---
env环境:
Director IP:  10.0.21.100
vitrual IP:   10.0.21.222
Real server1: 10.0.21.7
Real server2: 10.0.21.17


Director配置:

<pre>
net.ipv4.ip_forward = 1  # 开启ip转发

ip addr add 10.0.21.222/32 dev eth0; arping -c 3 -U 10.0.21.222 -I eth0 #配置vip并通告网络

ipvsadm -A  -t 10.0.21.222:3301 -s rr                #选择轮询调度模式
ipvsadm -a  -t 10.0.21.222:3301 -r 10.0.21.7:3301 -g
ipvsadm -a  -t 10.0.21.222:3301 -r 10.0.21.17:3301 -g

ipvsadm-save   #保存配置


# ipvsadm -ln  #查看当前配置信息
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.0.21.222:3301 rr
  -> 10.0.21.7:3301               Route   1      0          0         
  -> 10.0.21.17:3301              Route   1      0          0
</pre>

real server配置:
<pre>
#将 vip 配置到 lo网卡, 并配置路由
ip addr add 10.0.21.222/32 broadcast 10.0.21.222 dev lo 
ip route add 10.0.21.222/32 via 10.0.21.222

#关闭 arp 
echo "1" >/proc/sys/net/ipv4/conf/lo/arp_ignore
echo "2" >/proc/sys/net/ipv4/conf/lo/arp_announce
echo "1" >/proc/sys/net/ipv4/conf/all/arp_ignore
echo "2" >/proc/sys/net/ipv4/conf/all/arp_announce
</pre>

连接测试, 不要在 vip 主机中测试, 可以在 client 主机中测试请求的信息:
<pre>
[root@cz ~]# mysql -h 10.0.21.222 -P 3301 -upercona percona -Bse "show global variables like 'hostname'"
hostname	cz-test2
[root@cz ~]# mysql -h 10.0.21.222 -P 3301 -upercona percona -Bse "show global variables like 'hostname'"
hostname	cz-test3
[root@cz ~]# mysql -h 10.0.21.222 -P 3301 -upercona percona -Bse "show global variables like 'hostname'"
hostname	cz-test2
</pre>