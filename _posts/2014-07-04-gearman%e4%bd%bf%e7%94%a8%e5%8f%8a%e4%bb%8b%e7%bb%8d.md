---
id: 176
title: Gearman使用及介绍
date: 2014-07-04T17:25:49+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=176
permalink: '/gearman%e4%bd%bf%e7%94%a8%e5%8f%8a%e4%bb%8b%e7%bb%8d/'
views:
  - "5"
dsq_thread_id:
  - "3493782375"
dsq_needs_sync:
  - "1"
categories:
  - performance
  - system
tags:
  - gearmand
  - performance
---
<strong>Gearman介绍</strong>
   Gearman 为通用的应用程序框架提供了一种和其它机器或进程协同工作的机制， 允许并行的执行任务， 均衡负载处理， 也可以在多个编程语言中实现相互的函数调用。Gearman适用于很多应用， 从高可用站点到数据库replication事件的传输都可以适用到。在分布式处理交互中， Gearman是一个不错的选择。

   官网： <a href="http://gearman.org/">http://gearman.org/</a>
   工程： <a href="https://launchpad.net/gearmand/+download">https://launchpad.net/gearmand/+download</a>
   协议： <a href="http://gearman.org/protocol/">http://gearman.org/protocol/</a>
<!--more-->
<strong>Gearman工作机制</strong>
见下图:
<img src="http://img.zhechen.me/articles/201407/stack.png" alt="stack" />

   Gearman通过三部分组件来实现与应用程序之间的交互，分别为Client, Worker和Job Server.
以Gearman::XS(c代码实现的一种perl封装)模块为例,包含以下列表:
<pre>
Gearman
├── XS
│   ├── Client.pm     # client组件
│   ├── Job.pm        # Job Server组件
│   ├── Task.pm       # 并行执行
│   └── Worker.pm     # Worker组件
└── XS.pm
</pre>

   Client：用来生成可以发送给Job 端并且可以运行的请求, 即为生产者；
   Job Server：用来将生产者的请求发送到合适的Worker端，即为协调者(下面的Gearmand说明)；
   Worker：执行实际需要的工作，并通过Job端返回给Client需要的信息，即为消费者；

   三者之间通过TCP socket互通, 数据以二进制封装进行传输，见 <a href="http://gearman.org/protocol/">http://gearman.org/protocol/</a>
Worker组件可以注册、删除函数，添加选项连接Job等, Client可以调用注册到Job中的函数。
目前的支持的编程语言有: C, Java, Perl, Python, Php， Ruby, C#等,详见: <a href="http://gearman.org/download/">http://gearman.org/download/</a>

<strong>部署说明</strong>
   Gearman的部署分为两部分： 应用程序的Gearman驱动和Gearmand软件(Job Server)。

1. Gearmand安装

   可从<a href="https://launchpad.net/gearmand/+download">https://launchpad.net/gearmand/+download</a> 下载源码包, 也可使用epel源进行YUM安装：
<pre>
libgearman-1.1.8-2.el6.x86_64
gearmand-1.1.8-2.el6.x86_64
libgearman-devel-1.1.8-2.el6.x86_64      #视驱动类型, 封装c源码的驱动需要
</pre>

2. Gearman驱动下载

   详见: <a href="http://gearman.org/download/">http://gearman.org/download/</a> ，安装可参考：<a href="http://gearman.org/getting-started/">http://gearman.org/getting-started/</a>， 相应编程语言的扩展可参考安装

<strong>配置说明</strong>
1. 参数

   Gearmand(Job Server)默认监控0.0.0.0:4730端口,分别对应host和port端口, 可以额外增加thread数目(默认4)和backlog队列数目(默认32)如下:
<pre>
# cat /etc/sysconfig/gearmand 
### Settings for gearmand
OPTIONS="-t 50 -b 500"
</pre>

2. Gearmand(Job Server)冗余
   可以在Client,Worker端操作, 仅在第一台gearmand不可用时, 则访问后面gearmand。可以配置成冗余状态(至少两台), 后续驱动程序的函数会注册到多台服务中。
<pre>
Now you’re probably asking what if the job server dies? You are able to run multiple job servers and have the clients and workers connect to the first available job server they are configured with. This way if one job server dies, clients and workers automatically fail over to another job server. 
</pre>
   以perl说明,添加Server可以通过add_server($host, $port)连接单个的gearmand服务, 也可以通过add_servers("$host1:$port1,$host2:$port2")实现冗余, 冗余后函数的注册和清除分别在$host1, $host2中操作.

<strong>示例说明</strong>

1. Perl
   (1). <a href="http://www.pqpq.de/2010/01/gearmandriver.html">http://www.pqpq.de/2010/01/gearmandriver.html</a>  #链接示例中仅列出了worker部分
   (2). <font color="red">PATH/Gearman-XS-0.13/examples</font>  #client和worker端都做了较详细的说明

2. PHP
   (1). <a href="http://gearman.org/getting-started/">http://gearman.org/getting-started/</a>  #见Client和Worker部分，说明较详细。

<strong> 监控</strong>

   <a href="https://github.com/yugene/Gearman-Monitor">https://github.com/yugene/Gearman-Monitor</a>