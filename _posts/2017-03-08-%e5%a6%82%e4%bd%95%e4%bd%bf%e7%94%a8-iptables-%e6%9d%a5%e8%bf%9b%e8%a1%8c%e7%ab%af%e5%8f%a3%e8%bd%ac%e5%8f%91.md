---
id: 779
title: 如何使用 iptables 来进行端口转发
date: 2017-03-08T12:44:34+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=779
permalink: '/%e5%a6%82%e4%bd%95%e4%bd%bf%e7%94%a8-iptables-%e6%9d%a5%e8%bf%9b%e8%a1%8c%e7%ab%af%e5%8f%a3%e8%bd%ac%e5%8f%91/'
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - network
  - system
tags:
  - iptables
  - port forward
---
<h2>1. 介绍</h2>

传统的端口转发工具<a href="https://github.com/chenzhe07/portproxy">portproxy</a> 、<a href="https://boutell.com/rinetd/">rinetd</a> 等， 这些应用工具都通过接收并转发 tcp 数据报文实现转发端口的目的, 但是都存在或多或少的缺陷, 比如不能 tcp/udp 同时支持, 难以修改数据报文的一些路由规则等. 庆幸的是我们可以通过 linux 的 iptables 的数据包过滤规则在 kernel 层面实现端口的转发.

在 iptables 的层面, 端口转发也可以称为端口映射, 是通过NAT(地址转发)的方式来修改数据包目的地址或端口, 再将报文转发到最终的主机(通常在没有公网地址的私有网络中). 通过这种方式用户既可以访问到远端的私有网络的机器(比如运行着 http 服务的主机).

<h2>2. 访问结构</h2>

我们以如下结构来讲解如何在 public A 主机中进行端口转发, 使得用户可以访问到后端的 private B 主机的 memcached 端口:

<pre><code>note: 所有主机均为 Centos 系统, 1.1.1.1 为任意的公网地址.

   +------+           +----------+             +-----------+
   | user |  -------&gt; | public A | ----------&gt; | private B | 
   +------+           +----------+             +-----------+
   pub: 2.2.2.2     em1: 10.0.21.5             em1: 10.0.21.7
                    em2: 1.1.1.1
</code></pre>

图中 public A 主机的 em2 网卡为公网地址, 最终 user 可以通过访问 1.1.1.1:20011 来访问 private B 的 11211 端口. user 用户的主机可能存在于私有网络中, 也可能有独立的公网地址, 后续会介绍两者的不同.

<h2>3. iptables 中的数据报文流程</h2>

linux 用户可以通过 iptables 及其一系列的规则来高度控制数据报文的传输. 而 iptables 中的表则是其构件块, 描述了功能的大类, iptables 一共有4个表, 分别如下:

<pre><code>filter
nat
mangle
raw
</code></pre>

每个表都有自己的一组内置链, 用户基于这些链可以建立一组规则, 常用的有 filter 表中的 INPUT、OUTPUT、和 FORWARD 链等.

下图描述了数据包进入一台主机的 iptables 的工作流程:

<pre><code>                               XXXXXXXXXXXXXXXXXX
                             XXX     Network    XXX
                               XXXXXXXXXXXXXXXXXX
                                       +
                                       |
                                       v
 +-------------+              +------------------+
 |table: filter| &lt;---+        | table: nat       |
 |chain: INPUT |     |        | chain: PREROUTING|
 +-----+-------+     |        +--------+---------+
       |             |                 |
       v             |                 v
 [local process]     |           ****************          +--------------+
       |             +---------+ Routing decision +------&gt; |table: filter |
       v                         ****************          |chain: FORWARD|
****************                                           +------+-------+
Routing decision                                                  |
****************                                                  |
       |                                                          |
       v                        ****************                  |
+-------------+       +------&gt;  Routing decision  &lt;---------------+
|table: nat   |       |         ****************
|chain: OUTPUT|       |               +
+-----+-------+       |               |
      |               |               v
      v               |      +-------------------+
+--------------+      |      | table: nat        |
|table: filter | +----+      | chain: POSTROUTING|
|chain: OUTPUT |             +--------+----------+
+--------------+                      |
                                      v
                               XXXXXXXXXXXXXXXXXX
                             XXX    Network     XXX
                               XXXXXXXXXXXXXXXXXX
</code></pre>

本文要介绍的端口转发就是基于 nat 表的 PREROUTING 和 POSTROUTING 链, 所有的数据报文都要先经过 nat 的 PREROUTING 链进行处理, 再根据路由规则选择是进入 filter 的 INPUT 链还是 filter 的 FORWARD 链, 不管进入哪个链, 之后都会进去 nat 表的 POSTROUTING 链, 最后数据报文再转发出去.

<h2>4. 设置端口转发</h2>

从上面的数据报文的流程来看, 要在 public A 主机中实现端口转发大致有两种方式, 第一种就是文中最开始介绍的 portproxy、rinetd 工具, 这些工具的数据报文在进入 nat 的 PREROUTING 后就进入了 filter 的 INPUT 链. 第二种则是本文要介绍的方法, 数据在进入 nat 的 PREROUTING 链后 直接进入 filter 的 FORWARD 链, 因此要进行以下操作:

<h4>1) 开启内核 ip_forward 转发</h4>

redhat/centos 系列系统默认为 0, 或者在 /etc/sysctl.conf 文件进行更改以永久生效;

<pre><code>sysctl -w net.ipv4.ip_forward=1
</code></pre>

<h4>2) 设置 PREROUTING 路由规则</h4>

用户访问 1.1.1.1:20011 的时候, 通过 DNAT 的方式将数据报文中的目的 ip 信息改为后端的 private B 地址 10.0.21.7:11211.

<pre><code>iptables -t nat -A PREROUTING -d 1.1.1.1/32 -p tcp -m tcp --dport 20011 -j DNAT --to-destination 10.0.21.7:11211
</code></pre>

如果 public A 主机的公网地址是固定的静态 ip, 则不用设置下面的参数:

<pre><code>iptables -t nat -A POSTROUTING -o em2 -j MASQUERADE 
</code></pre>

<h4>3) 增加 filter 表的 FORWARD 规则</h4>

该步骤不是必须的, 如果当前 FORWARD 链的默认规则为 REJECT 则需要添加, 如果是 ACCEPT 就不需要执行下面的操作.

<pre><code>iptables -I FORWARD 1 -d 10.0.21.7/32 -j ACCEPT
</code></pre>

<h4>4) 设置 POSTROUTING 路由规则</h4>

该步骤也不是必须的, 主要视 public A 主机的路由规则而定, 默认情况下是不需要增加的, 因为 FORWARD 规则会通过 10.0.21.5 内网地址进行转发. 这里的 SNAT 则是将数据报文的源地址改为 10.0.21.5(即 public A 的内网地址), 再发送出去.

<pre><code>iptables -t nat -I POSTROUTING 1 -d 10.0.21.7/32 -p tcp -m tcp --dport 11211 -j SNAT --to-source 10.0.21.5
</code></pre>

设置完成后, 用户既可以通过 telnet 1.1.1.1 20011 验证端口转发的有效性.

<h2>5. 访问出现的问题.</h2>

在上述步骤设置完成后, 笔者也碰到了一个有趣的问题, 如果 user 的主机有独立的公网则可以 telnet 通过, 如果 user 的主机也是存在于私网中, 即也是通过 NAT 的方式访问 public A 主机的话, 就会出现 telnet 超时的问题.

通过 tcpdump 抓包来看看数据报文的走向:

<h4>1) user 在本地的私网环境中 telnet public A 主机:</h4>

<pre><code>telnet 1.1.1.1 20011
Trying 1.1.1.1...
^C
</code></pre>

user 本地端抓包:

<pre><code># tcpdump -S -s0 -nn -i any port 20011
10:09:20.018174 IP 192.168.1.101.51782 &gt; 1.1.1.1.20011: Flags [S], seq 3245571896, win 14600, options [mss 1460,sackOK,TS val 57645414 ecr 0,nop,wscale 7], length 0
10:09:21.017320 IP 192.168.1.101.51782 &gt; 1.1.1.1.20011: Flags [S], seq 3245571896, win 14600, options [mss 1460,sackOK,TS val 57646414 ecr 0,nop,wscale 7], length 0
</code></pre>

public A 主机抓包:

<pre><code># tcpdump -S -nn -i any port 11211 or port 20011
10:09:22.777271 IP 2.2.2.2.57158 &gt; 1.1.1.1.20011: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57645414 ecr 0,nop,wscale 7], length 0
10:09:22.777335 IP 10.0.21.5.57158 &gt; 10.0.21.7.11211: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57645414 ecr 0,nop,wscale 7], length 0
10:09:23.776389 IP 2.2.2.2.57158 &gt; 1.1.1.1.20011: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57646414 ecr 0,nop,wscale 7], length 0
10:09:23.776420 IP 10.0.21.5.57158 &gt; 10.0.21.7.11211: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57646414 ecr 0,nop,wscale 7], length 0
</code></pre>

private B 主机抓包:

<pre><code># tcpdump -S -nn -i any port 11211
10:09:23.773626 IP 10.0.21.5.57158 &gt; 10.0.21.7.11211: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57646414 ecr 0,nop,wscale 7], length 0
10:09:25.773608 IP 10.0.21.5.57158 &gt; 10.0.21.7.11211: Flags [S], seq 3937785824, win 14600, options [mss 1380,sackOK,TS val 57648414 ecr 0,nop,wscale 7], length 0
</code></pre>

从两个 tcpdump 结果可以看出, 数据报文已经正常到了 private B 主机, 也就说已经通过了 public A 主机的 POSTROUTING 处理, 将包转发到了后端的 B 主机, 但是 B 主机没有响应, 正常的三次握手也没有建立完成, 也就是 B 主机直接丢弃了 A 发送过来的报文.

但是如果 user 主机有独立的公网, 则正常验证通过. 这点很让人迷惑, tcpdump 的结果中唯一不同的就是数据报文开头的时间戳信息, 但是 tcp 选项里的 TS val 值是以 user 本地端为准的. 这让笔者想到了 TCP 时间戳的一个问题, 参见 <a href="http://stackoverflow.com/questions/8893888/dropping-of-connections-with-tcp-tw-recycle">dropping-of-connections-with-tcp-tw-recycle</a>, 而 B 主机上的 tcp_tw_recycle 的参数是开启的. tcp_tw_recycle 内核参数到底有什么用? 下面是内核文档的解释:

<pre><code>kernel-doc-2.6.32/Documentation/networking/ip-sysctl.txt

tcp_tw_recycle - BOOLEAN
        Enable fast recycling TIME-WAIT sockets. Default value is 0.
        It should not be changed without advice/request of technical
        experts.
</code></pre>

linux 系统的 TIME_WAIT 状态用来保障连接的正常关系, 实际上并不会消耗过多的资源, 但是在高并发的环境中很多技术人员会将 tcp_tw_recycle 和 tcp_tw_reuse 参数打开用来快速回收和重用 TIME_WAIT 的 socket 连接, 这在一定程度上可以提升机器的性能, 不过也会带来一些难以预料的问题.

当 tcp_tw_recycle 和 tcp_timestamps 参数同时开启的时候, 同一源 ip 的连接, 在 TIME_WAIT 状态下, 系统内核会追踪其最近的时间戳信息, 如果时间戳正常增长就允许重用(re-use)该连接的 socket, 如果时间戳异常变更, 该主机就会丢弃接收到 SYN 报文, 这就会引起上面令人迷惑的问题. 同样再来看看我们的环境, user 如果存在于 NAT 环境, 在连接 public server 的时候, 用户侧的 NAT 只会更改 IP 的源地址信息, 而不会改变时间戳(tcp 报文的时间戳基于系统启动的时间, tcp 报文的 timestamps 选项), <a href="https://www.ietf.org/rfc/rfc1323.txt">rfc</a>文档规定时间戳值必须为单调递增，否则接受到的包可能会被丢掉, 如下所示:

<pre><code>
           An additional mechanism could be added to the TCP, a per-host
           cache of the last timestamp received from any connection.
           This value could then be used in the PAWS mechanism to reject
           old duplicate segments from earlier incarnations of the
           connection, if the timestamp clock can be guaranteed to have
           ticked at least once since the old connection was open.  This
           would require that the TIME-WAIT delay plus the RTT together
           must be at least one tick of the sender's timestamp clock.
           Such an extension is not part of the proposal of this RFC.
</code></pre>
在 linux 内核源文件中 <code>linux/v2.6.39.4/source/net/ipv4/tcp_ipv4.c</code> 中的 <code>tcp_v4_conn_request</code> 函数中
<pre><code>
		/* VJ's idea. We save last timestamp seen
		 * from the destination in peer table, when entering
		 * state TIME-WAIT, and check against it before
		 * accepting new connection request.
		 *
		 * If "isn" is not zero, this request hit alive
		 * timewait bucket, so that all the necessary checks
		 * are made in the function processing timewait state.
		 */
		if (tmp_opt.saw_tstamp &&
		    tcp_death_row.sysctl_tw_recycle &&
		    (dst = inet_csk_route_req(sk, req)) != NULL &&
		    (peer = rt_get_peer((struct rtable *)dst)) != NULL &&
		    peer->daddr.addr.a4 == saddr) {
			inet_peer_refcheck(peer);
			if ((u32)get_seconds() - peer->tcp_ts_stamp < TCP_PAWS_MSL &&
			    (s32)(peer->tcp_ts - req->ts_recent) >
							TCP_PAWS_WINDOW) {
				NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_PAWSPASSIVEREJECTED);
				goto drop_and_release;
			}
		}
</code></pre>
<code>tmp_opt.saw_tstamp</code> 即表示该socket支持<code>tcp_timestamp</code>, <code>sysctl_tw_recycle</code> 则是 <code>tcp_tw_recycle</code> 对应的选项; <code>TCP_PAWS_MSL</code> 的值为 60, <code>TCP_PAWS_WINDOW</code> 的值则为 1, <code>linux/v2.6.39.4/source/include/net/tcp.h</code> 包含以下代码
<pre><code>
#define TCP_PAWS_MSL	60		/* Per-host timestamps are invalidated
					 * after this time. It should be equal
					 * (or greater than) TCP_TIMEWAIT_LEN
					 * to provide reliability equal to one
					 * provided by timewait state.
					 */
#define TCP_PAWS_WINDOW	1		/* Replay window for per-host
					 * timestamps. It must be less than
					 * minimal timewait lifetime.
					 */
</code></pre>

所以对于后端的 private B 主机而言, 其保存着 public A 主机转发时候的连接信息, 这个连接的时间戳也是最新的值, 而 user 本地端的时间戳信息则远远小于该值, 这就会引起 B 主机直接丢弃 user 发送过来的请求, 相反如果 user 本地端的时间戳大于 public A 保存的时间戳则可以正常访问 B 主机. 这种问题实际上在 LVS 环境中也是比较普遍的, 很多人都建议线上的机器只开启 tcp_tw_reuse 选项, 让 tcp_tw_recycle 保持默认, 不要开启.

另外 tcp_timestamps 参数控制时间戳信息, 而在内核代码中 <code>#define tcp_time_stamp ((__u32)(jiffies))</code> 内核每秒中将 jiffies 变量增加 HZ 次, 对于 HZ 值为 100 的系统, 1 个 jiffy 就等于 1000/100 = 10ms, 对于 1000 的系统, 1 个 jiffy 就是 1ms, 本文中测试的机器的系统的 HZ 为 1000, 如下:

<pre><code>cat /boot/config-2.6.32-573.18.1.el6.x86_64| grep HZ
CONFIG_NO_HZ=y
CONFIG_HZ_1000=y
CONFIG_HZ=1000
CONFIG_MACHZ_WDT=m
</code></pre>

我们来看看正常的 telnet 请求的情况:

<pre><code>12:26:41.599122 IP 2.2.2.2.26597 &gt; 1.1.1.1.20011: Flags [S], seq 1403291286, win 14600, options [mss 1380,sackOK,TS val 65884228 ecr 0,nop,wscale 7], length 0
12:26:41.599155 IP 10.0.21.5.26597 &gt; 10.0.21.7.11211: Flags [S], seq 1403291286, win 14600, options [mss 1380,sackOK,TS val 65884228 ecr 0,nop,wscale 7], length 0
12:26:41.599219 IP 10.0.21.7.11211 &gt; 10.0.21.5.26597: Flags [S.], seq 159148930, ack 1403291287, win 14480, options [mss 1460,sackOK,TS val 1681744061 ecr 65884228,nop,wscale 7], length 0
12:26:41.599226 IP 1.1.1.1.20011 &gt; 2.2.2.2.26597: Flags [S.], seq 159148930, ack 1403291287, win 14480, options [mss 1460,sackOK,TS val 1681744061 ecr 65884228,nop,wscale 7], length 0
12:26:41.602296 IP 2.2.2.2.26597 &gt; 1.1.1.1.20011: Flags [.], ack 159148931, win 115, options [nop,nop,TS val 65884232 ecr 1681744061], length 0
12:26:41.602321 IP 10.0.21.5.26597 &gt; 10.0.21.7.11211: Flags [.], ack 159148931, win 115, options [nop,nop,TS val 65884232 ecr 1681744061], length 0
...
...
12:26:44.119060 IP 10.0.21.7.11211 &gt; 10.0.21.5.26597: Flags [.], ack 1403291294, win 114, options [nop,nop,TS val 1681746581 ecr 65886749], length 0
12:26:44.119068 IP 1.1.1.1.20011 &gt; 2.2.2.2.26597: Flags [.], ack 1403291294, win 114, options [nop,nop,TS val 1681746581 ecr 65886749], length 0
</code></pre>

这是正常的三次握手的过程, 第三个包为 private B 主机的响应, 倒数第三个包的 TS val 为 65884232, 倒数第二个报的 ecr 为 65886749, 相减为 2.517个 HZ, 即经过了 2517 ms, 刚好对应每行的时间信息. 而最后一个包的 TS val 值 1681746581 会被 private B 主机保存为连接的最新时间戳(如果 tcp_tw_recycle 和 tcp_timestamps 同时开启的话).

<h2>6. 总结</h2>

总体上 iptables 的端口转发功能是在内核层面实现的, 用户通过 iptables 及一系列规则可以高度控制数据报文的流向, 比起传统的转发工具, 在灵活性方面有了很大的提升, 不过 iptables 方式在安全层面也会有一些隐患, 比如来源地址一定要限制好, 否则用户只要能路由到 public A 主机, 就可以访问转发的端口, 这点不像我们以往了解的只在 filter 表里限制就可以. 最后也需要特别注意 tcp 相关的内核参数设置, selinux 的限制也可能会影响端口转发的可用性.

<h2>7. 参考</h2>

<a href="http://stackoverflow.com/questions/8893888/dropping-of-connections-with-tcp-tw-recycle">dropping-of-connections-with-tcp-tw-recycle</a>

<a href="https://www.systutorials.com/816/port-forwarding-using-iptables/">port-forwarding-using-iptables</a>

<a href="https://wiki.archlinux.org/index.php/iptables">archwiki iptables</a>

<a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/4/html/Security_Guide/s1-firewall-ipt-fwd.html">s1-firewall-ipt-fwd.html</a>