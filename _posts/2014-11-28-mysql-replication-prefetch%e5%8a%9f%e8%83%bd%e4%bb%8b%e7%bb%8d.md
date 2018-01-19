---
id: 443
title: MySQL replication prefetch功能介绍
date: 2014-11-28T13:56:27+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=443
permalink: '/mysql-replication-prefetch%e5%8a%9f%e8%83%bd%e4%bb%8b%e7%bb%8d/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3459392450"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - lag
  - replication
  - slave
---
<a href="https://github.com/yoshinorim/replication-booster-for-mysql">https://github.com/yoshinorim/replication-booster-for-mysql</a>
<a href="https://code.launchpad.net/mysql-replication-listener">https://code.launchpad.net/mysql-replication-listener</a>

主从延迟的瓶颈可能有以下几个原因:
1. master为多线程更新, slave 的sql_thread则为单线程更新, 这意味着master大量的更新必然会引起主从延迟的持续增大;
2. slave不对外服务的原因, buffer还未有记录相关的信息, 这造成了sql_thread在重放sql的时候要先通过磁盘IO找到相应的记录再加载到buffer进行更新, 即意味着磁盘IO造成了主从延迟的瓶颈;
<!--more-->



第一种情况可以通过多线程的sql_thread功能实现， MySQL 5.6增加slave_parallel_workers功能以支持并行的执行events, 不过遗憾的是slave_parallel_workers是基于不同database来实现并行复制的, 如果写压力集中在一个database的几张表中, 则该参数没有本质意义的提升;也有一些第三方的补丁(比如MySQL Transfer)实现了并行执行.
第二种情况可以通过预加载行记录信息,使得行信息预先加载到buffer中, 这样sql_thread就可以更快的执行events操作. 这种方式通过(api接口)读取slave接收到的relay-log, 改写更新语句为select语句,之后在slave中执行select语句达到目的. 当然这种方式并不是完全之策,比如master持续频繁的更新, 或者slave对应用提供服务, buffer pool紧张不够用等. 通过预加载方式可以缓解slave的延迟, 并不能根除延迟。

以下为安装及测试replication-listener
1. install mysql-replication-listener

<pre>
export JAVA_HOME=/opt/jdk
export MYSQL_DIR=/opt/mysql/
export MySQL_INCLUDE_DIR=/opt/mysql/include
export MySQL_LIBRARY=/opt/mysql/lib
export JAVA_AWT_LIBRARY=/opt/jdk/jre/lib/amd64/libawt.so
export JAVA_JVM_LIBRARY=/opt/jdk/jre/lib/amd64/server/libjvm.so
</pre>

openssl-devel.x86_64  gcc   gcc-c++   cmake make
error: ‘MYSQL_TYPE_TIME2’ 为5.6版本的错误

/opt/mysql/include/sql_common.h:26:18:  error: error: hash.h: No such file or directoryhash.h: No such file or directory
需要官方的source code,  拷贝include/hash.h 到percona目录的include下.

2. replication-booster-for-mysql

install boost.x86_64 boost-debuginfo.x86_64 libodb-boost-devel.x86_64 boost-static.x86_64

boost没有debug包, 做以下改动:
<pre>
cp /usr/lib64/libboost_thread-mt.a /usr/lib64/libboost_thread-mt-d.a
cp /usr/lib64/libboost_thread-mt.so.5 /usr/lib64/libboost_thread-mt-d.so.5
cp /usr/lib64/libboost_date_time-mt.so.5 /usr/lib64/libboost_date_time-mt-d.so.5
......
cp /usr/lib64/libboost_regex-mt.so.5 /usr/lib64/libboost_regex-mt-d.so.5
......
</pre>
如果安装了boost-debuginfo.x86_64，做以下改动,跳过debuh库的依赖检测:

注释 vi /usr/lib64/boost/Boost.cmake以下信息:
```c
534 #  foreach(file ${_IMPORT_CHECK_FILES_FOR_${target}} )
535 #    if(NOT EXISTS "${file}" )
536 #      message(FATAL_ERROR "The imported target \"${target}\" references the file
537 #   \"${file}\"
538 #but this file does not exist.  Possible reasons include:
539 #* The file was deleted, renamed, or moved to another location.
540 #* An install or uninstall procedure did not complete successfully.
541 #* The installation package was faulty and contained
542 #   \"${CMAKE_CURRENT_LIST_FILE}\"
543 #but not all the files it references.
544 #")
545 #    endif()
546 #  endforeach()
```

CMakeLists.txt增加以下信息：
```c
--- ../../replication-booster-for-mysql/CMakeLists.txt	2014-11-06 16:32:01.466160057 +0800
+++ CMakeLists.txt	2014-11-06 17:19:06.346764919 +0800
@@ -5,9 +5,9 @@
 
 # Find MySQL client library and header files
 find_library(MySQL_LIBRARY NAMES mysqlclient_r mysqlclient PATHS
-/usr/lib64/mysql /usr/lib/mysql)
+/usr/lib64/mysql /usr/lib/mysql /opt/mysql/lib)
 find_path(MySQL_INCLUDE_DIR mysql.h
-  /usr/local/include/mysql /usr/include/mysql)
+  /usr/local/include/mysql /usr/include/mysql /opt/mysql/include)
 include_directories(${MySQL_INCLUDE_DIR})
 
 # Find MySQL replication listener and header files

cmake . -DCMAKE_PREFIX_PATH=/home/mysql/mysql-replication-listener/   #指定replication listener的路径
make编译增加共享库
ln -s /usr/lib64/libicuuc.so.42 /usr/lib64/libicuuc.so
ln -s /usr/lib64/libicui18n.so.42 /usr/lib64/libicui18n.so

运行replication_booster执行以下依赖
cp /home/scripts/mysql-replication-listener/lib/libreplication.so.1 /usr/lib64/
cp /opt/5.6.15/lib/libmysqlclient.so.18 /usr/lib64/
```

指定s选项以执行prefetch转换,如下的processlist:
`# replication_booster --user=root --password=xxxxxx --admin_user=root --admin_password=xxxxxx --socket=/srv/mysql/date3301/data/s8301 -s 10`

<pre>
2014-11-06 18:20:36: Reading relay log file: /srv/mysql/data3301/data/relay-bin.000877 from relay log pos: 173556941
2014-11-06 18:20:36: Replication Booster started.
^C2014-11-06 18:22:26: Stopping Replication Booster..
2014-11-06 18:22:26: Terminating slave monitoring thread.
Running duration:    110.546 seconds
Statistics:
 Parsed binlog events: 4306475
 Skipped binlog events by offset: 2693000
 Unrelated binlog events: 553125
 Queries discarded in front: 720958
 Queries pushed to workers: 334007
 Queries popped by workers: 311333
 Old queries popped by workers: 0
 Queries discarded by workers: 0
 Queries converted to select: 304651
 Executed SELECT queries: 304651
 Error SELECT queries: 0
 Number of times to read relay log limit: 5385
 Number of times to reach end of relay log: 0
</pre>

将更新的sql转为select语句在slave中执行, 通过预加载记录来实现快速更新的目的. 
<pre>
| 67332 | root        | localhost          | data | Query   |     0 | preparing                        | select isnull(coalesce( old_vendorid='7218B947-F03D-4897-92B4-C0A0A57A7B8A', mac='1b0f3abf7bb874a828b1854291f268fb48f31eb5', update_time = now())) from login  user_id = 11111                       |         0 |             0 |         1 |
| 67333 | root        | localhost          | data | Query   |     0 | init                             | select isnull(coalesce( old_vendorid='71B3F8D0-BEB2-4C52-940D-954379996CA6', mac='7b97cc6b16c31565b0377ba2d1c58ececf7cc8f1', update_time = now())) from login  where  user_id = 11111111        |         0 |             0 |         1 |
| 67334 | root        | localhost          | data | Query   |     0 | statistics                       | select isnull(coalesce( charge_status = 1, charge_time = now())) from order_char where  id = 1111111
</pre>
