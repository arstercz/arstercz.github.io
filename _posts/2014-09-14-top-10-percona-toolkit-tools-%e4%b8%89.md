---
id: 331
title: top 10 percona toolkit tools (三)
date: 2014-09-14T21:02:26+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=331
permalink: '/top-10-percona-toolkit-tools-%e4%b8%89/'
dsq_thread_id:
  - "3912287008"
dsq_needs_sync:
  - "1"
ultimate_sidebarlayout:
  - default
categories:
  - database
  - percona
tags:
  - percona
  - tool
---
### 5. pt-summary
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-summary.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-summary.html</font></a>
搜集系统信息: 非常详细的列出系统相关的信息， 包括硬件信息， CPU, Memory, 分区, 当前运行的进程, 网络连接, 网卡等信息。对于不经常做更新的系统而言， 该工具可以很好的当做系统运行镜像来使用。该工具和pt-mysql-summary类似， 但更侧重于系统信息的搜集。同样以bash shell编写。
输出信息如下:

```
# pt-summary
# Percona Toolkit System Summary Report ######################
        Date | 2014-09-14 11:36:21 UTC (local TZ: CST +0800)
    Hostname | cz
      Uptime | 27 days,  3:20,  1 user,  load average: 0.00, 0.00, 0.00
...
# Processor ##################################################
  Processors | physical = 2, cores = 8, virtual = 16, hyperthreading = yes
...
# Memory #####################################################
       Total | 31.3G
        Free | 28.1G
        Used | physical = 3.3G, swap allocated = 10.0G, swap used = 0.0, virtual = 3.3G
...
# Mounted Filesystems ########################################
...
# Disk Partioning ############################################
...
# Network Config #############################################
...
# Interface Statistics #######################################
...
# Network Connections ########################################
...
# Top Processes ##############################################
...
```
部分信息并不是我们所必须的， 同样有些信息也没有出现， 比如ip地址信息, 不过bash shell脚本给我们定制功能提供了很大的便利性，大家可以按需修改。
其它参数:
<pre>
--save-samples: 将报告生成在指定的空目录下, 类似pt-mysql-summary, 不同的信息按照文件存放.比如:
#pt-summary --save-samples=summary
[root@z6 ~]# ls summary
dmesg_file  dmidecode  ip  memory  mounted_fs  netstat  network_devices  notable_procs  partitioning  proc_cpuinfo_copy  processes  raid-controller  summary  sysctl  uptime  vmstat

--read-samples： 读取指定目录里的文件，生成报告信息;比如读取上述的summary目录:
# pt-summary --read-samples=summary

--sleep: 在搜集vmstat信息的时候， sleep多长时间。
</pre>

### 6. pt-online-schema-change
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-online-schema-change.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-online-schema-change.html</font></a>
在线更改表结构: 可能线上操作经常碰到这样的场景, 一个相对较大的表(比如1个G), 如果写较频繁， 在直接用alter table等语句修改表结构的时候会引起原表较长时间的锁(alter为表级锁),想想alter table表的过程(创建新的临时表结构， 给原表加锁防止数据不一致, 拷贝数据到新的表, 完成后再做交换操作);对应的，连接进来的更新数据的线程会处于锁等待状态， 如果锁的时间很长， 线程数则越积越多， 最终达到设置的上限值， 引起"ERROR: Can't create a new thread"等错误; 这是很常见的表锁引起的问题，我们可通过临时增加进程limit缓解：echo -n "Max processes=SOFT_LIMIT:HARD_LIMIT" > /proc/`pidof mysqld`/limits , pt-online-schema-change工具主要目的在于避免长时间的锁来实现表结构的更改, 主要原理见下:
```
[root@cz ~]# pt-online-schema-change -S /web/mysql/data/3306.sock A=utf8,h=localhost,P=3306,D=test,t=tm,p=xxxxxx --alter='engine = "innodb"' --execute
Operation, tries, wait:
  copy_rows, 10, 0.25
  create_triggers, 10, 1
  drop_triggers, 10, 1
  swap_tables, 10, 1
  update_foreign_keys, 10, 1
Altering `test`.`tm`...
Creating new table...
Created new table test._tm_new OK.
Altering new table...
Altered `test`.`_tm_new` OK.
Creating triggers...
Created triggers OK.
Copying approximately 1 rows...
Copied rows OK.
Swapping tables...
Swapped original and new tables OK.
Dropping old table...
Dropped old table `test`.`_tm_old` OK.
Dropping triggers...
Dropped triggers OK.
Successfully altered `test`.`tm`.
```
上述过程为更改test库tm表的engine为innodb的过程, 可以看看它如何避免长时间加锁:
```
1. 创建新的表test._tm_new, _tm_new表为alter参数之后的结构, 即engine = innodb;
2. 开始创建更新相关的trigger, 包括insert, update, delete相关的三个trigger, 该目的为在应用更新原表的时候, 通过trigger将更新也应用到新的_tm_new表中, 该步骤防止了数据的不一致;
3. 开始拷贝数据， 因为测试中记录很少，大家只看到Copying approximately 1 rows...这一行; 实际上这步是通过分组来执行的， 比如我们有1亿条记录， select filed1, files2,... from tm 同样会引起长时间的表锁, 但是分组查询比如每次读取1k行记录"select filed1, filed2... from tm where id >= ? and id < ?"则只需要很短时间的表锁(可能是ns, ms级别), 然后更新数据到新表_tm_new中， 后面的依次循环; 这步的主要思想就是一个长时间锁的操作拆分为很多个小锁的操作。
4. 拷贝完成后做交换表操作, 将原tm表和_tm_new表做一个交换;
5. 删除原表;也可以指定参数--[no]drop-old-table保留原表;
6. 删除2过程创建的3个trigger;
```
综上，总体思想为拆分, 该工具的思想最早由facebook通过php实现, percona通过perl进行了重写， 同时增加了很多控制参数, 比如slave延迟较大, Thread线程数较多则暂停执行等。使用该工具需要原表具有主键或唯一键, 以防止引起数据不一致。

其它参数:
```
--alter: 更改表结构参数, 该参数等同于 alter table 'table_name'  .., 比如要增加一个键, 只需要添加 "add key ...", 该参数可以接受多个操作, 以','分隔;

--[no]check-alter: 对alter参数进行解析并检查, 以防错误的sql语句;

--check-interval: 如果指定了max-lag,则在更改表的时候每sleep指定时间就检查一次slave的lag延迟;

--[no]check-plan: 检查query语句的执行计划;

--check-slave-lag: 如果slave延迟时间大于max-lag值, 则暂停更新操作;

--chunk-index: 首选指定的索引来完成分组操作;

--chunk-size: 每次分组的大小, 默认为1000;

--critical-load: 每次分组完成后, 检查SHOW GLOBAL STATUS信息， 如果指定参数超过了阈值则中断更新操作;

--dry-run: 创建和更改新表， 但是不创建trigger和拷贝数据; 类似于rsync的dry-run功能(-n option);

--max-load: 每次分组完成后, 检查SHOW GLOBAL STATUS信息， 如果指定参数超过了阈值则暂停更新操作; 比如Thread_running过大的话，肯能需要暂停操作， 以免引起其它问题;

--print: 打印操作过程的SQL语句;
```

备注: 对于大表的更新, 最好加上 nodrop-old-table 选项, 避免 drop 步骤的时候大量刷新内存脏页, 从而降低数据库性能, 如果被改的表频繁更新, 没有该选项对数据库的影响还是很大的, 可以等两三个小时, 到后台将脏页都刷新完毕后可以手动删除旧的表.