---
id: 542
title: MySQL slave 延迟复制
date: 2015-06-01T13:49:58+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=542
permalink: '/mysql-slave-%e5%bb%b6%e8%bf%9f%e5%a4%8d%e5%88%b6/'
dsq_thread_id:
  - "3810967952"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - delay
  - MySQL
  - percona
---
MySQL slave 延迟复制

延迟复制是一个很简单的概念，区别于传统的异步复制(接近实时), 比如用户误操作, 删除了重要的表, 延迟复制特性保证了用户有机会从延迟的 slave 中恢复误删除的表. 该特性的问题在于需要保证用户有足够的时间从 slave 阻止误操作复制的发生. 

要理解该特性如何实现, 我们先简单回顾下 MySQL replication 如何实现, 见下图:
<img src="https://img.zhechen.me/articles/201506/Delayed_Replication.jpg"  alt="主从复制" />
当 master 有一个更新操作(create, drop, delete, insert, update 等), 该更新操作应用到本地的磁盘并写到 binary log 里，之后更新操作异步(接近于实时)的从master 的 binary log 复制到 slave 的 relay log, 最后 slave 的 sql thread 线程读取 relay log, 将更新操作应用到 slave 表中.

<!--more-->

1. MySQL 5.6 的延迟复制
MySQL 5.6 允许用户配置复制的延迟时间, 保证 slave 的 sql thread 线程的更新操作落后于 master 的更新. 详见 <a href="http://dev.mysql.com/doc/refman/5.6/en/change-master-to.html">http://dev.mysql.com/doc/refman/5.6/en/change-master-to.html</a> 不过需要注意的是, 即便在延迟复制的过程中, master 出现问题, 更新操作也不会丢失，因为更新操作已经复制到了 slave 的 relay log 中.

延迟特性是在 slave 中实现的, 不会影响 master, relay log的接收等同传统的复制方式, 只是 sql thread 执行更新的过程延迟了指定的时间, 笔者猜测是根据比对sql的执行时间, 只有时间差 >= 指定的delay 时间才会更新到 slave中.
以下命令指定已有复制的延迟时间为 20秒
```
slave> STOP SLAVE;

slave> CHANGE MASTER TO MASTER_DELAY = 20;

slave> START SLAVE;
```
此后, master 中更新一个操作, slave 则在20s 后才进行更新. 这个时间有点短, 如果master 执行了误操作, 需要在 20s 内对slave 进行操作, 为避免更新操作的丢失, 需要先找到 master 中误操作之前的 binlog 位置信息, 可以 mysqlbinlog 查看binary log文件, 也可以在 master 中执行 SHOW BINLOG EVENTS 找到相应的位置信息： binlog_filename, binlog_position, 在 slave 中可以使用复制的 UNTIL 特性让 slave 更新到 误操作之前的位置:
```
slave> START SLAVE UNTIL
 -> MASTER_LOG_FILE=binlog_filename,
 -> MASTER_LOG_POS=binlog_position;
```

2. MySQL 5.1/5.5 的延迟复制
遗憾的是只有5.6支持延迟复制, 不过可以通过 pt-slave-delay 工具 <a href="https://www.percona.com/doc/percona-toolkit/2.2/pt-slave-delay.html">https://www.percona.com/doc/percona-toolkit/2.2/pt-slave-delay.html</a> 实现延迟复制特性.
先看看简单的示例:
```
pt-slave-delay --delay 1m --interval 15s --run-time 10m slavehost
```
pt-slave-delay 工具监控 slave , 通过 start 或 stop 保证复制的 sql thread 线程的更新落后于我们指定的时间, delay 参数为延迟的时间, interval 为工具执行的频率, 所以在实际工作中, slave 延迟的时间在 delay 和 delay + interval 范围内. 
该工具默认基于slave 的 relay log 的位置信息, 所以不需要连接 master(该特性解析relay log, 获取sql执行的时间进行时间差比对). 这种情况适合在 io thread (接收master的更新操作)落后master 时间比较少的时候, 如果落后很多, 工具则需要连接 master 获取 binlog 的相关信息.

该工具监控 slave 中的 IO thread 状态, 如果 io thread 的状态是 'waiting for the SQL thread to free some relay log space' 相关的信息, 则开始连

接 master 获取 binlog 相关的信息, 如下代码所示, 可以看到 master 为可选配置:
```
4179    my $master_dbh;
4180    if ( $master_dsn ) {
4181       PTDEBUG && _d('Connecting to master via DSN from cmd-line');
4182       $master_dbh = get_dbh($dp, $master_dsn);
4183    }
4184    elsif ( $o->get('use-master')
4185            || $status->{slave_io_state} =~ m/free enough relay log/ )
4186    {
4187       # Try to connect to the slave's master just by looking at its
4188       # SLAVE STATUS.
4189       PTDEBUG && _d('The I/O thread is waiting, connecting to master');
4190       my $spec    = "h=$status->{master_host},P=$status->{master_port}";
4191       $master_dbh = get_dbh($dp, $dp->parse($spec, $slave_dsn));
4192    }
```

最后来看看 delay 如何实现: 

```
4229    $slave_dbh->do('START SLAVE IO_THREAD');   #确保 IO thread 正常运行
4236       $now = time();                          #取当前时间点
```
注意以下的信息, position 结构以当前时间, slave复制master的文件位置信息组成, 每次通过 SHOW SLAVE STATUS获取相关的信息, 下面部分的while循环中处理 $now - delay 到 $now 之间的更新操作. 以此方式保证 slave 落后于 master 指定的delay 时间值. 
```
4302          {
4303             push @positions,
4304                [ $now, $res->{file}, $res->{position} ];
4305          }
4306       }
...
4335          my $pos;
4336          my $i = 0;
4337          while ( $i < @positions
4338                  && $positions[$i]->[$TS] <= $now - $o->get('delay') ) {
4339             $pos = $i;
4340             $i++;
4341          }
```
在 sql_thread 停止的时候:
```


# 找出上述的 binlog 后，通过 start slave sql_thread until ... 保证slave 总是落后 master delay的秒数, 处理上述 $now - delay 到 $now之间的更新.
4356             if ( $position->[$FILE] ne $status->{relay_master_log_file}
4357                || $position->[$POS] != $status->{exec_master_log_pos} )
4358             {
4359                $slave_dbh->do(
4360                   "START SLAVE SQL_THREAD UNTIL /*$position->[$TS]*/ "
4361                      . "MASTER_LOG_FILE = '$position->[$FILE]', "
4362                      . "MASTER_LOG_POS = $position->[$POS]"
4363                );

```

在 sql_thread 启动的时候, 没有显示的 STOP SLAVE until ..., 因为上述的 START 过程确保了延迟复制.该过程是一个循环检测的过程, 一旦 seconds_behind_master < delay 值, 就进行关闭 sql_thread 操作.
```
4382       elsif ( ($status->{seconds_behind_master} || 0) < $o->get('delay') ) {
4383          my $position = $positions[-1];
4384          my $behind = $status->{seconds_behind_master} || 0;
4385          $next_start = $now + $o->get('delay') - $behind;
4386          info("STOP SLAVE until "
4387             . ts($next_start)
4388             . " at master position $position->[$FILE]/$position->[$POS]");
4389          $slave_dbh->do("STOP SLAVE SQL_THREAD");
4390       }
4391       else {
4392          my $position = $positions[-1];
4393          my $behind = $status->{seconds_behind_master} || 0;
4394          info("slave running $behind seconds behind at"
4395             . " master position $position->[$FILE]/$position->[$POS]");
4396       }
4397 
4398       sleep($o->get('interval'));
4399    }
```
pt-slave-delay 通过 SHOW  SLAVE  STATUS方式来实现复制延迟, 因为没有解析 relay log, 所以并不能通过 sql 更新的时间戳达到目标, 这点可能不同于 MySQL 5.6, 但实现的目标是一样的.

综上, MySQL 5.6 和 pt-slave-delay 工具的延迟功能都确保了 relay-log 能够以传统方式接受 master 的更新操作, 延迟的实现在 slave 端, 该特性确保了在延迟复制的过程中, IO thread 一直接收 master 的更新操作, 所以即便master 出现问题, 更新操作也不会丢失.

参见:
<a href="http://www.clusterdb.com/mysql-replication/delayed-replication-in-mysql-5-6-development-release">http://www.clusterdb.com/mysql-replication/delayed-replication-in-mysql-5-6-development-release</a>
<a href="https://www.percona.com/doc/percona-toolkit/2.2/pt-slave-delay.html">https://www.percona.com/doc/percona-toolkit/2.2/pt-slave-delay.html</a>
<a href="http://www.xaprb.com/blog/2007/08/04/introducing-mysql-slave-delay/">http://www.xaprb.com/blog/2007/08/04/introducing-mysql-slave-delay/</a>
<a href="http://mechanics.flite.com/blog/2014/02/12/fast-forwarding-a-delayed-mysql-replica/">http://mechanics.flite.com/blog/2014/02/12/fast-forwarding-a-delayed-mysql-replica/</a>