---
id: 595
title: 重启 iptables 影响 nf_conntrack 参数说明
date: 2015-11-03T15:14:28+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=595
permalink: '/%e9%87%8d%e5%90%af-iptables-%e5%bd%b1%e5%93%8d-nf_conntrack-%e5%8f%82%e6%95%b0%e8%af%b4%e6%98%8e/'
ultimate_sidebarlayout:
  - default
dsq_thread_id:
  - "4288570113"
dsq_needs_sync:
  - "1"
categories:
  - performance
  - system
tags:
  - iptables
---
重启 iptables 影响 nf_conntrack 参数说明

今天在新机房的机器上重启 iptables 后发现 net.nf_conntrack_max(最大跟踪的连接数) 会恢复成默认的 65536(RAM > 4G时, 该值默认为 65536), 在stop iptables 后, 通过命令 sysctl -a |grep nf_conntrack 查看已经不存在nf_conntrack 模块相关的参数信息. 从这点来看参数恢复成默认值本质上是因为在重启 iptables 的过程中重新加载了 nf_conntrack 模块;
<!--more-->


在其它机房并未重现该问题, 查看 /etc/init.d/iptables 脚本, 跟踪到 stop 函数中的代码
```
IPTABLES=iptables
IPV=${IPTABLES%tables}  # ip
...
NF_MODULES=($(lsmod | awk "/^${IPV}table_/ {print \$1}") ${IPV}_tables)  # iptable_filter
NF_MODULES_COMMON=(x_tables nf_nat nf_conntrack) # Used by netfilter v4 and v6
...

stop() {
    ...
    if [ "x$IPTABLES_MODULES_UNLOAD" = "xyes" ]; then
        echo -n $"${IPTABLES}: Unloading modules: "
        ret=0
        for mod in ${NF_MODULES[*]}; do
            rmmod_r $mod
            let ret+=$?;
        done
        # try to unload remaining netfilter modules used by ipv4 and ipv6 
        # netfilter
        for mod in ${NF_MODULES_COMMON[*]}; do
            rmmod_r $mod >/dev/null
        done
        [ $ret -eq 0 ] && success || failure
        echo
    fi
    ...
}
```

脚本从 /etc/sysconfig/iptables-config 文件中读取配置 IPTABLES_MODULES_UNLOAD, 判断是否为 yes, 默认都是yes, 则 stop 函数执行卸载模块操作, rmmod_r 函数如下:
```
rmmod_r() {
    ...
    # Get referring modules.
    # New modutils have another output format.
    [ $NEW_MODUTILS = 1 ] \
        && ref=$(lsmod | awk "/^${mod}/ { print \$4; }" | tr ',' ' ') \
        || ref=$(lsmod | grep ^${mod} | cut -d "[" -s -f 2 | cut -d "]" -s -f 1)

    # recursive call for all referring modules
    for i in $ref; do
        rmmod_r $i
        let ret+=$?;
    done

    # Unload module.
    # The extra test is for 2.6: The module might have autocleaned,
    # after all referring modules are unloaded.
    if grep -q "^${mod}" /proc/modules ; then
        modprobe -r $mod > /dev/null 2>&1
        res=$?
        [ $res -eq 0 ] || echo -n " $mod"
        let ret+=$res;
    fi
    ...
}
```
rmmod_r 函数通过递归方式卸载从 stop 函数传过来的模块名(注意 NF_MODULES_COMMON 信息); modprobe -r $mod 即为卸载模块操作, 改函数会下载 stop 函数传过来的 nf_conntrack 模块; 在新机房中手工操作 modprobe -r nf_conntrack 可以正常卸载, 在其它机房手工操作，提示错误:
```
FATAL: Module nf_conntrack is in use.
```

跟踪模块信息:
```
[root@cz ~]# lsmod | grep '^nf_conntrack'
nf_conntrack_ipv6       7985  2 
nf_conntrack           79206  3 nf_conntrack_ipv4,nf_conntrack_ipv6,xt_state
```
可以看到 nf_conntrack 被三个模块使用, 对比新机房的信息:
```
[root@database6 ~]# lsmod | grep '^nf_conntrack'
nf_conntrack_ipv4       9154  1 
nf_conntrack           79206  2 nf_conntrack_ipv4,xt_state
```
可以看到 nf_conntrack_ipv6 模块的使用才是该文问题的原因, 由此可以关联到 ip6tables 正在使用 nf_conntrack 模块, 所以没有卸载 nf_conntrack 模块, 我们关掉 ip6tables 后, 看看其它机房的机器能否重现该文的问题:
```
[root@db02 ~]# /etc/init.d/ip6tables stop
ip6tables: Setting chains to policy ACCEPT: filter         [  OK  ]
ip6tables: Flushing firewall rules:                        [  OK  ]
ip6tables: Unloading modules:                              [  OK  ]
[root@db02 ~]# 
[root@db02 ~]# 
[root@db02 ~]# sysctl -a |grep nf_conntrack
[root@db02 ~]#
[root@db02 ~]# /etc/init.d/ip6tables start
ip6tables: Applying firewall rules:                        [  OK  ]
[root@cz ~]# sysctl -a |grep nf_conntrack_max
net.netfilter.nf_conntrack_max = 65536
net.nf_conntrack_max = 65536
```
以上重现了新机房的问题, conntrack 参数恢复成了默认值.

再来看看 ip6table 的设置:
```
[root@db02 ~]# ip6tables -vnL
Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 ACCEPT     all      *      *       ::/0                 ::/0                state RELATED,ESTABLISHED 
    0     0 ACCEPT     icmpv6    *      *       ::/0                 ::/0                
    0     0 ACCEPT     all      lo     *       ::/0                 ::/0                
    0     0 ACCEPT     tcp      *      *       ::/0                 ::/0                state NEW tcp dpt:22 
    0     0 REJECT     all      *      *       ::/0                 ::/0                reject-with icmp6-adm-prohibited 

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 REJECT     all      *      *       ::/0                 ::/0                reject-with icmp6-adm-prohibited 

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
```

允许所有的 ipv6 地址可以连接 22 端口:
```
# ping6 -I em1 fe80::eef4:bbff:fecd:d224
PING fe80::eef4:bbff:fecd:d224(fe80::eef4:bbff:fecd:d224) from fe80::be30:5bff:feed:fde0 em1: 56 data bytes
64 bytes from fe80::eef4:bbff:fecd:d224: icmp_seq=1 ttl=64 time=2.10 ms
64 bytes from fe80::eef4:bbff:fecd:d224: icmp_seq=2 ttl=64 time=0.183 ms

# ssh -6 fe80::eef4:bbff:fecd:d224%em1
Last login: Tue Nov  3 14:04:05 2015 from 172.30.0.30
[root@cz ~]#  
```

从这点来看, ipv6 还是存在安全隐患, 不过运行商都没有配置 ipv6 相关的路由, 机器上的 ipv6 也不是运营商分配的, 所以通信仅限于内网的机器, 不过到底是多了一个安全隐患;

综上, 严格来看重启 iptables/ip6tables 会重新加载 nf_conntrack 相关的模块, 引起参数恢复成默认值, 在有应用的主机中需要引起重视. 当然为了机房之间机器的统一, 可以在新机房启用 ip6tables, 以免重启 iptables 引起参数失效. 也可以在 /etc/sysconfig/iptables-config 文件中开启选项 IPTABLES_SYSCTL_LOAD_LIST=".nf_conntrack", iptables 重启后会进行 sysctl 操作.