---
id: 210
title: MongoDB使用及规范介绍
date: 2014-07-08T17:27:55+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=210
permalink: '/mongodb%e4%bd%bf%e7%94%a8%e5%8f%8a%e8%a7%84%e8%8c%83%e4%bb%8b%e7%bb%8d/'
dsq_thread_id:
  - "3468894585"
dsq_needs_sync:
  - "1"
categories:
  - database
  - nosql
tags:
  - nosql
---
<strong>安装部署说明</strong>
<strong>1. 软件获取</strong>

不做源码编译， 采用二进制格式安装(解压即可用)。软件可从官方下载 <a href="http://www.mongodb.org/downloads">http://www.mongodb.org/downloads</a> 

<strong>2. 安装条件</strong>

主机环境应该为RAID10级别，如果硬盘不够可降级为RAID1或RAID5级别(RAID0不安全)。
RAID卡型号选取带有Cache功能的卡，如DELL的H700或H710P。

资源限制: 对应启动文件的参数, ulimit -n 值需大于 最大连接数+mongodb数据文件数, 暂定ulimit -n 16384

<strong>3. 安装方式</strong>
<!--more-->


可以采用Binary方式安装，比如2.4.10版本，升级高版本需做好相关测试；Binary解压后的目录即为MongoDB的basedir目录, 单独存放于不同于数据文件所在的分区(比如/opt/目录)。数据目录不必初始化， 启动即初始。

目录结构说明:
<pre>
/opt/mongodb-linux-x86_64-2.4.10/
├── bin                         # commands dir.
│   ├── bsondump
│   ├── mongo
│   ├── mongod
│   ├── mongodump
│   ├── mongoexport
│   ├── mongofiles
│   ├── mongoimport
│   ├── mongooplog
│   ├── mongoperf
│   ├── mongorestore
│   ├── mongos
│   ├── mongosniff
│   ├── mongostat
│   └── mongotop
├── GNU-AGPL-3.0
├── README
└── THIRD-PARTY-NOTICES
</pre>

<strong>4. 数据目录</strong>

MongoDB数据存储于非根分区，/web(或/data)目录等，比如数据(库)存储路径/web/mongodb/nodeXXXX/data目录，XXXX为端口号四位的表示。

<strong>5. 启动和关闭</strong>

脚本套件结构说明:
获取: <a href="https://github.com/arstercz/mongodb_node_mgr">https://github.com/arstercz/mongodb_node_mgr</a>
<pre>
/web/mongodb/nodexxxx/
├── data                           # 数据目录
├── my.node.conf                   # 参数配置文件
├── node                           # 得到基本的管理信息，可用户操作启动、停止，依赖于参数配置文件my.node.cnf，且和后面的start,status,stop关联
├── noderc                         # 声明BASEDIR路径
├── start                          # 启动
├── status                         # 查看状态
├── stop                           # 停止
└── use                            # 默认连接到相应端口的本地库
</pre>

启动关闭示例: 
<pre>
[root@cz-test1 ~]# cd /web/mongodb/node5700/
[root@cz-test1 node5700]# 
[root@cz-test1 node5700]# ./start
/web/mongodb/node5700/./data/mongod.lock has exists.
waiting node start  mongodb node on pid=675 port=5700   

[root@cz-test1 node5700]# ./use admin
MongoDB shell version: 2.4.10
connecting to: 127.0.0.1:5700/admin
>

[root@cz-test1 node5700]# ./stop
waiting mongodb node shutdown mongodb node off pid=675 port=5700
</pre>

<strong>参数配置说明</strong>

<strong>1. 概述</strong>

所有参数配置信息集中到my.node.conf文件中，每个实例在各自node节点下生成相应的配置文件, 对一些需要经常设置的变量建议放到conf配置文件中(比如port, fork等)，参数配置文件可简单分为必选项和可选项两大类。

<strong>2. 必选项</strong>

<pre>
port = xxxx  # listen port
</pre>
 本地监听端口,默认0.0.0.0:xxxx, 监听端口默认27017， 本文中设置为5700端口。
<pre>
dbpath = /web/mongodb/node5700/data  # location data stored.
</pre>
数据路径信息
<pre>
pidfilepath = /web/mongodb/node5700/data  # pidfile path
</pre>
pid文件路径， 默认生成mongod.lock文件，里面存放pid值, 该lock亦用于区分实例是否占用。
<pre>
fork = true  # run as deamon process.
</pre>
守护模式启动
<pre>
nohttpinterface = true  # disables the HTTP interface.
</pre>
关闭http监听端口，默认为port+1000, 开启http可以查看状态信息
<pre>
auth = true  # requires database authentication for users connecting from remote hosts.
</pre>
开启认证， 所有连接的client端都需要认证
<pre>
profile = 1  # log slow operations
</pre>
记录慢查询操作，类似MySQL的slow-query-log
<pre>
slowms = 300  # The threshold in milliseconds that be considered slow query.
</pre>
查询超过多长时间会被记录，类似MySQL的slow-query-time
<pre>
#sysinfo = true  # print some diagnostic system information, only mongod only outputs the page information and no database process will start.
</pre>
用于诊断， 开启该选项，mongod进程不会启动。
<pre>
nssize = 64   # specifies the default size for namespace files， unit: MB
</pre>
数据命名空间的大小设置， mongod中，每个命名空间的数据都会分成若干组(防止单文件过大引起性能消耗)，类似于MySQL中的分区表。

<strong>3. 可选项</strong>

<pre>
maxConns = 10000  # max number of simultaneous connections.
</pre>
最大连接数，不要超过系统的ulimit -n 值
<pre>
syslog = ture  # log to rsyslogd instead a file.
</pre>
日志信息写到rsyslogd 系统文件中, 易于loganalyzer的监控。
<pre>
diaglog = 1  # log write operations.
</pre>
记录写操作
<pre>
nounixsocket = true
</pre>
不创建用于本地连接的socket文件
<pre>
directoryperdb = true  # stores each database’s files in its own folder in the data directory.
</pre>
每个库一个目录，存储自己的数据, 类似MySQL的innodb_file_per_table。

#replication
<pre>
master = true         
</pre> 
mongod以master模式开启, 在主从环境中作为master的实例需开启该选项。
<pre>
slave = ture
</pre>
mongod以slave模式开启, 在主从环境中作为slave的实例需开启该选项，切需指定source参数值(也可启动后手工添加到local信息中)
<pre>
source = 10.0.21.5:5700
</pre>
设置master的来源，包括ip和port。
<pre>
oplogSize = 200  #unit MB
</pre>
复制环境中更新数据的日志的大小，其类似MySQL的binlog，同时该文件以轮询方式更新(重复写),类似于MySQL的redo log。更新频繁的应用中确保该值够大，以免slave还未同步，oplog却被重写,默认为数据盘的5%大小。

<strong>管理</strong>

即便认证会增加很小的通讯消耗， 也建议mongod服务不允许程序直接连接， mongod的访问机制贯穿用户的创建，访问，备份和监控，增加访问权限后，后续的所有操作都需要认证。
备份和监控也可以考虑使用mongodb官方的api, 详见 <a href="https://mms.mongodb.com/learn-more">https://mms.mongodb.com/learn-more</a>, 类似于percona Cloud, 在本地端安装agent, 所有数据通过agent上传到mongodb的云平台，管理员可以通过web界面查看信息。

<strong>1. 认证</strong>

不同于MySQL， mongod通过以下命令(mongo shell下操作)创建用户:
<pre>
use database             #use dbname即可创建dbname库，如果该库什么都没创建，退出后不存在该库。
db.addUser(userDocument) #为database库增加一个认证用户, 比如 db.addUser("username", "password", true),第三个参数true可选，增加该参数表示该用户为只读权限。
</pre>

认证用户:
<pre>
use database
db.auth("username","password")   #返回1认证成功
</pre>

<strong>2. 数据和备份</strong>

数据的备份方式多样, 包括停止mongod服务，拷贝整个dbpath下的文件, mongodump导出所有数据，但导出过程中会阻断数据的更新(两种方式都类似于MySQL的MyISAM备份)。
线上备份通过mongodump在slave中进行操作:

<pre>
$BASE_DIR/bin/mongodump --port 57XX -uroot -pxxxxxx -o $BACK_DIR/$PRE_DIR
</pre>

<strong>3. 监控</strong>

nagios监控 <a href="https://github.com/mzupan/nagios-plugin-mongodb">https://github.com/mzupan/nagios-plugin-mongodb</a>
cacti监控  <a href="https://github.com/arstercz/mongodb-cacti-plugins">https://github.com/arstercz/mongodb-cacti-plugins</a>