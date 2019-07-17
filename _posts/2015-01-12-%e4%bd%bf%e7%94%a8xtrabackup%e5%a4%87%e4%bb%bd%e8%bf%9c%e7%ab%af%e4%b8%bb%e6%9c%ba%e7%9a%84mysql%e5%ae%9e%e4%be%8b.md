---
id: 467
title: 使用Xtrabackup备份远端主机的MySQL实例
date: 2015-01-12T20:20:48+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=467
permalink: '/%e4%bd%bf%e7%94%a8xtrabackup%e5%a4%87%e4%bb%bd%e8%bf%9c%e7%ab%af%e4%b8%bb%e6%9c%ba%e7%9a%84mysql%e5%ae%9e%e4%be%8b/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3468412892"
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - MySQL
  - xtrabackup
---
percona Xtrabackup是一款用于MySQL备份的开源工具集, 效果类似MySQL Enterprise Backup, 支持在线备份InnoDB而不影响业务使用. 不过我一直觉得Xtrabackup是迄今为止最强悍的MySQL备份工具,没有之一. 

备份的原理见: <a href="http://arstercz.com/how-innobackupex-works/">http://arstercz.com/how-innobackupex-works/</a>

percona手册页中提供了很详细的示例来说明使用stream选项做备份:
<a href="http://www.percona.com/doc/percona-xtrabackup/2.2/howtos/recipes_ibkx_stream.html">http://www.percona.com/doc/percona-xtrabackup/2.2/howtos/recipes_ibkx_stream.html</a>
<!--more-->

通过使用stream,再加上网络的备份方式可以很方便的以tar/gzip方式来备份非本地的机器, 不过在一些场景下, 我们只想备份一台远端机器的非压缩的备份文件, 比如要备份的机器空间不足, 或者保存备份的空间也不足(如果需要在备份主机恢复的话,至少需要2*back_size大小的磁盘空间), 这种方式不允许我们将备份保存为tar/gzip格式, 因为不够空间做解压操作.

下面的方式可以达到我们的目标, 不用解压而直接获得解压后的备份文件, 以 nc(netcat) 方式为例说明:
# server1
```
mkdir ./2015-01-12-19-55
nc -l 12345 | tar xivf - -C 2015-01-12-19-55/
```

# server2
```
innobackupex --defaults-file=./my.cnf --slave-info --stream=tar ./ | nc server1 12345
```
执行完成后提示使用-i选项提取tar中的数据流, 这也是server1的tar命令为什么会加上-i参数的原因.
150112 19:55:52  innobackupex: Connection to database server closed
innobackupex: You must use -i (--ignore-zeros) option for extraction of the tar stream.

以 ssh 为例说明:

```
ssh root@server1 "cd /data/2015-01-12-19-55; nc -l 12345 | tar xvif - " & sleep 1; \
innobackupex --stream=tar ./ --defaults-file=./my.cnf --slave-info | nc server1 12345
```


如果高版本系统,如Centos 7不支持nc命令的话, 可以使用ssh方式完成:
```
innobackupex --defaults-file=./my.cnf --stream=tar ./ | ssh server1 "tar xivf - -C /data/xtrabackup/2015-01-12-19-55/"
```

备份完成后,记得使用--apply-log恢复日志信息.