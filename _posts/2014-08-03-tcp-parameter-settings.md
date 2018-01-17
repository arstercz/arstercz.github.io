---
id: 277
title: TCP parameter Settings
date: 2014-08-03T09:46:50+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=277
permalink: /tcp-parameter-settings/
dsq_thread_id:
  - "3838167851"
dsq_needs_sync:
  - "1"
categories:
  - system
tags:
  - TCP
---
<pre>sysctl -w net.core.rmem_max=8388608</pre>
# maximum receive size of buffers used by sockets
<pre>sysctl -w net.core.wmem_max=8388608</pre>
# maximum socket send buffer size
<pre>sysctl -w net.core.rmem_default=65536</pre>
# default setting in bytes of the socket receive buffer
<pre>sysctl -w net.core.wmem_default=65536</pre>
# default setting in bytes of the socket send buffer
<!--more-->

<pre>sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608'</pre>
# The first value tells the kernel the minimum receive buffer for each TCP connection, and this buffer is always allocated to a TCP socket, even under high pressure on the system. ... The second value specified tells the kernel the default receive buffer allocated for each TCP socket. This value overrides the /proc/sys/net/core/rmem_default value used by other protocols. ... The third and last value specified in this variable specifies the maximum receive buffer that can be allocated for a TCP socket.

<pre>sysctl -w net.ipv4.tcp_wmem='4096 65536 8388608'</pre>
# This variable takes 3 different values which holds information on how much TCP sendbuffer memory space each TCP socket has to use. Every TCP socket has this much buffer space to use before the buffer is filled up. Each of the three values are used under different conditions. ... The first value in this variable tells the minimum TCP send buffer space available for a single TCP socket. ... The second value in the variable tells us the default buffer space allowed for a single TCP socket to use. ... The third value tells the kernel the maximum TCP send buffer space.

<pre>sysctl -w net.ipv4.tcp_mem='8388608 8388608 8388608'</pre>
# The tcp_mem variable defines how the TCP stack should behave when it comes to memory usage. ... The first value specified in the tcp_mem variable tells the kernel the low threshold. Below this point, the TCP stack do not bother at all about putting any pressure on the memory usage by different TCP sockets. ... The second value tells the kernel at which point to start pressuring memory usage down. ... The final value tells the kernel how many memory pages it may use maximally. If this value is reached, TCP streams and packets start getting dropped until we reach a lower memory usage again. This value includes all TCP sockets currently in use.
 
<pre>sysctl -w net.ipv4.tcp_syncookies=1</pre>
# TCP SYN cookie protection (default), helps protect against SYN flood attacks, only kicks in when net.ipv4.tcp_max_syn_backlog is reached
<pre>sysctl -w net.ipv4.tcp_max_syn_backlog=4096</pre>
# This parameter enables SYN flood protection, mysql back_log option should be less than this value.
<pre>sysctl -w net.ipv4.ip_local_port_range="1024 65000"</pre>
# default range of IP port numbers that are allowed for TCP and UDP traffic on the server.
<pre>sysctl -w net.ipv4.tcp_fin_timeout=15</pre>
# determines the time that must elapse before TCP/IP can release a closed connection and reuse its resources. This is known as TIME_WAIT state.

# the following 3 entries can be used in high perfomance web site.
<pre>sysctl -w net.ipv4.tcp_max_tw_buckets=20000</pre>
# Maximal number of timewait sockets held by the system simultaneously.
<pre>sysctl -w net.ipv4.tcp_tw_reuse=1</pre>
# allows reusing sockets in TIME_WAIT state for new connections when it is safe from protocol viewpoint.
<pre>sysctl -w net.ipv4.tcp_tw_recycle=1</pre>
# enables fast recycling of TIME_WAIT sockets
<pre>sysctl -w net.netfilter.nf_conntrack_max=262144</pre>
# increase simultaneous/concurrent TCP connections。
