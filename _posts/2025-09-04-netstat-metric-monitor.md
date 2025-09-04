---
layout: post
title: "netstat 指标监控汇总"
tags: [netstat]
comments: true
---

linux 中的 `netstat` 提供了很详细的 `IP/TCP/UDP` 统计信息. 本文则对常见的错误做了汇总以及指标含义的说明, 可以按需对重要的指标进行监控.

## 参数汇总

> 备注: `netstat -s` 即可获取详细的指标信息. 不过有的指标在高版本内核已经废弃, 更全的参数信息见: [kernel-snmp_counter](https://docs.kernel.org/networking/snmp_counter.html)

| netstat 指标 | 统计类型 | 对应 telegraf 插件 nstat 指标 | 说明 |
| :- | :- | :- | :- |
| TcpExtTCPRetransFail | counter | nstat.TcpExtTCPRetransFail | a counter that indicates the number of times a TCP connection has been closed because of repeated, failed retransmission attempts.  |
| TcpExtListenDrops | counter | nstat. TcpExtListenDrops |indicate the number of packets dropped because the server's listen queue was full. In newer kernels (4.7 and later), this statistic is no longer incremented, and other metrics like TcpExtListenOverflows are used to track similar issues related to the listen queue. |
| TcpExtListenOverflows | gauge | nstat.TcpExtListenOverflows | indicates when a TCP connection's accept queue was full after the connection's 3-way handshake completed, causing a connection to be dropped, or when a new SYN packet arrived while the accept queue was already full. |
| TcpExtTCPBacklogDrop | counter | nstat.TcpExtTCPBacklogDrop | refers to the dropping of incoming TCP connection requests due to the server's listen queue being full. This occurs when the rate of new connection attempts exceeds the rate at which the application can accept and process them. |
| TcpExtTCPDeferAcceptDrop | counter | nstat.TcpExtTCPDeferAcceptDrop  | counts the number of times a TCP connection was dropped because an application was too slow to call accept() on a deferred-accept socket. |
| TcpExtTCPPrequeueDropped | counter | nstat.TcpExtTCPPrequeueDropped  | a counter in the Linux networking stack that measures the number of TCP packets that were dropped from a CPU's "prequeue". A prequeue is a queue where incoming packets are temporarily stored before being processed by the TCP stack. These drops are an indicator of high server load and can lead to connection issues |
| TcpExtTCPRcvQDrop | counter | nstat.TcpExtTCPRcvQDrop  | a Linux network statistics counter that tracks the number of TCP packets dropped by the kernel because a socket's receive queue was full. It is a critical metric for diagnosing network performance bottlenecks, particularly when a high-throughput network is paired with an application that cannot process data quickly enough. |
| TcpExtTCPReqQFullDrop | counter | nstat.TcpExtTCPReqQFullDrop  | a Linux network stack statistic that tracks the number of times a TCP SYN (synchronize) packet was dropped because the SYN queue was full. A server maintains a SYN queue, also known as the request queue, for incoming connection requests. If the queue is full, the server may drop new connection requests, and this counter increments.  |
| TcpExtTCPTimeWaitOverflow | counter | nstat.TcpExtTCPTimeWaitOverflow  | indicates that the number of TCP sockets in the TIME_WAIT state has exceeded the maximum limit defined by the net.ipv4.tcp_max_tw_buckets kernel parameter. |
| IpInAddrErrors | counter | nstat.IpInAddrErrors  | The number of input datagrams discarded because the IP address in their IP header’s destination field was not a valid address to be received at this entity. This count includes invalid addresses (e.g., 0.0.0.0) and addresses of unsupported Classes (e.g., Class E). For entities which are not IP routers and therefore do not forward datagrams, this counter includes datagrams discarded because the destination address was not a local address. |
| IpInHdrErrors | counter | nstat.IpInHdrErrors  | The number of input datagrams discarded due to errors in their IP headers, including bad checksums, version number mismatch, other format errors, time-to-live exceeded, errors discovered in processing their IP options, etc. |
| TcpInErrs | counter | nstat.TcpInErrs  | The total number of segments received in error (e.g., bad TCP checksums). |
| UdpInErrors | counter | nstat. UdpInErrors  | The number of received UDP datagrams that could not be delivered for reasons other than the lack of an application at the destination port. |
| UdpRcvbufErrors | counter | nstat. UdpRcvbufErrors  | a counter in the network statistics that increments when a UDP packet is dropped due to insufficient receive buffer space on the socket. This indicates that the application or the system's default receive buffer size is too small to handle the incoming UDP traffic volume. The most common reason is that the kernel's network receive buffer (controlled by net.core.rmem_default and net.core.rmem_max sysctl parameters, or specifically for a socket using SO_RCVBUF) is too small to handle the incoming UDP traffic rate, leading to buffer overflows and dropped packets. |
| UdpSndbufErrors |  counter | UdpSndbufErrors  | refer to instances where UDP send buffers become full and the kernel drops packets, often due to high send rates or insufficient buffer sizes. To resolve this, you can increase the net.core.wmem_max and net.core.wmem_default kernel parameters to allow for larger UDP send buffers, or set larger send buffer sizes for specific applications using the SO_SNDBUF socket option.  |


## 指标类型

上述指标在 kernel 源码中都通过以下宏定义处理上述的统计值:
> 以下为 `Centos 7 3.10.0-1160` 版本内核代码, 不同方式都通过 SNMP 的方法实现, 都是累加的操作, 对应 counter 类型的监控.

| 方法 | 定义 |
| :- | :- |
| NET_INC_STATS_BH | #define NET_INC_STATS_BH(net, field)   SNMP_INC_STATS_BH((net)->mib.net_statistics, field) | 
| IP_INC_STATS_BH | #define IP_INC_STATS_BH(net, field)    SNMP_INC_STATS64_BH((net)->mib.ip_statistics, field) |
| UDP_INC_STATS_BH | #define UDP_INC_STATS_BH(net, field, is_udplite)            do { \ <br>      if (is_udplite) SNMP_INC_STATS_BH((net)->mib.udplite_statistics, field);   |
| SNMP_MIB_ITEM | #define SNMP_INC_STATS_BH(mib, field)        \ <br>                     __this_cpu_inc(mib[0]->mibs[field]) |
| __this_cpu_inc | # define __this_cpu_inc(pcp)             __this_cpu_add((pcp), 1) |


## 报警规则

由于都是 counter 类型的数据, 可以统一使用以下 promql 表达式进行报警监控:

```
increase(metric[1m]) > value
```

参考阈值:

> 备注: 4.7 内核开始已废弃 TcpExtListenDrops, 可以用 TcpExtListenOverflows 替代. 监控报警可以两个规则一起设置

| 指标 | 时间范围 | 阈值 | 含义 |
| :- | :- | :- | :- |
| nstat.TcpExtTCPRetransFail | 1m | 50 |  tcp 重传失败过多, 请检查主机负载或网络状况. |
| nstat.TcpExtListenDrops | 1m | 20 | tcp listen 队列已满, 请检查 net.ipv4.tcp_max_syn_backlog 和 net.core.somaxconn 相关参数. |
| nstat.TcpExtListenOverflows | 1m | 20 | tcp listen 队列已满, 请检查 net.ipv4.tcp_max_syn_backlog 和 net.core.somaxconn 相关参数. |
| nstat.TcpExtTCPBacklogDrop | 1m | 20 | tcp 连接队列已满, 请检查系统负载或 tcp 连接是否过快或检查 backlog 等参数. | 
| nstat.TcpExtTCPDeferAcceptDrop | 1m | 10 | tcp accept 新请求处理过慢, 请检查系统负载. |
| nstat. TcpExtTCPPrequeueDropped | 1m | 10 | tcp 堆栈 prequeue 处理过慢, 系统过于繁忙. |
| nstat.TcpExtTCPTimeWaitOverflow | 1m | 10 | tcp time_wait 状态过多, 请检查 net.ipv4.tcp_max_tw_buckets 参数.

## 系统参数

重要的 sysctl 参数主要包括以下:
```
net.core.netdev_max_backlog
net.ipv4.tcp_max_syn_backlog
net.core.somaxconn
net.ipv4.tcp_rmem
net.ipv4.tcp_wmem
```

不过对于整个网络请求来讲, 有不少流程都会存在排队的情况, 可以参考以下图来适当调优:

> 参考: [linux-network-performance-parameter](https://github.com/leandromoreira/linux-network-performance-parameters)  

**网络流程**:

![linux_network_flow]({{ site.baseurl }}/images/articles/202509/linux_network_flow.png)  

**tcp 状态流程**:

![tcp_connection_flow]({{ site.baseurl }}/images/articles/202509/tcp_connection-flow.png)  
