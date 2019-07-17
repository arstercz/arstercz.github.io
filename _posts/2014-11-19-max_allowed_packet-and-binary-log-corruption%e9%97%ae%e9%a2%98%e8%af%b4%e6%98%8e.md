---
id: 431
title: max_allowed_packet and binary log corruption问题说明
date: 2014-11-19T17:00:33+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=431
permalink: '/max_allowed_packet-and-binary-log-corruption%e9%97%ae%e9%a2%98%e8%af%b4%e6%98%8e/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3468459853"
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - error
  - MySQL
---
max_allowed_packet参数指定了Server可以读取或创建的最大网络包的大小,在5.6.5版本之前默认为1MB, 5.6.6及之后的版本默认为4MB, 该参数最大可指定1GB大小, 在主从环境中关于该参数的限制有下面2点:
<pre>
1. master端写binlog中的事件不能大于max_allowed_packet参数指定的大小;
2. 在所有slave 节点上的max_allowed_packet参数的值应该和master一样;
</pre>
正常情况下, slave 得到 max_allowed_packet 相关的错误信息， 通常加大max_allowed_packet(上限1GB) 就可以处理该问题, 不过在异常情况下, 错误信息可能提示存在大于1G的包, 这是不可能的错误, 大部门原因是由于binlog文件中断引起, 举例如下:
<!--more-->


出错信息:
<pre>
Got fatal error 1236 from master when reading data from binary log: 'log event entry exceeded max_allowed_packet; Increase max_allowed_packet on master; the first event 'bin-log.001114' at 56397426'
</pre>
查找master bin-log-001114文件的56397426位置信息, 提示数据大小为1.9G, binlog只是给出相对抽象的信息, 1.9G是不可能的大小(max binlog size 默认1G)，原因可能是由于binlog损坏引起的错误, 见下
<pre>
[root@cz tmp]# mysqlbinlog --start-position 56397426 bin-log.001114 >/tmp/114.log
ERROR: Error in Log_event::read_log_event(): 'Event too big', data_len: 1953720692, event_type: 99
</pre>

hexdump 查看binlog信息， 56397426转为16进制35c8e72, 找出的dump信息：
hexdump -C bin-log.001114 
<pre>
035b6ff0  21 00 21 00 62 62 73 6e  65 77 00 52 45 50 4c 41  |!.!.bbsnew.REPLA|
035b7000  43 45 20 49 4e 54 4f 20  75 64 62 5f 63 6f 6d 6d  |CE INTO udb_comm|
035b7010  6f 6e 5f 73 79 73 63 61  63 68 65 20 53 45 54 20  |on_syscache SET |
035b7020  60 63 6e 61 6d 65 60 3d  27 61 64 6d 69 6e 6d 65  |`cname`='adminme|
......
......
035baa20  2c 30 2c 30 2c 30 2c 30  2c 30 2c 30 2c 30 2c 30  |,0,0,0,0,0,0,0,0|
*
035baa50  5c 22 3b 73 3a 31 32 3a  5c 22 69 6e 76 69 74 65  |\";s:12:\"invite|

035bf250  22 61 64 64 72 65 73 73  5c 22 3b 73 3a 37 3a 5c  |"address\";s:7:\|
*
035bf270  22 7a 69 70 63 6f 64 65  5c 22 3b 73 3a 37 3a 5c  |"zipcode\";s:7:\|
035bf280  22 7a 69 70 63 6f 64 65  5c 22 3b 73 3a 34 3a 5c  |"zipcode\";s:4:\|
035bf290  22 73 69 74 65 5c 22 3b  73 3a 34 3a 5c 22 73 69  |"site\";s:4:\"si|
035bf2a0  74 65 5c 22 3b 73 3a 33  3a 5c 22 62 69 6f 5c 22  |te\";s:3:\"bio\"|
035bf2b0  3b 73 3a 33 3a 5c 22 62  69 6f 5c 22 3b 73 3a 38  |;s:3:\"bio\";s:8|
035bf2c0  3a 5c 22 69 6e 74 65 72  65 73 74 5c 22 3b 73 3a  |:\"interest\";s:|
035bf2d0  38 3a 5c 22 69 6e 74 65  72 65 73 74 5c 22 3b 73  |8:\"interest\";s|
035bf2e0  3a 37 3a 5c 22 73 69 67  68 74 6d 6c 5c 22 3b 73  |:7:\"sightml\";s|
*
035bf300  3a 31 32 3a 5c 22 63 75  73 74 6f 6d 73 74 61 74  |:12:\"customstat|
......
035c8e70  5c 22 7a 7a 69 6e 63 5f  73 74 61 74 69 73 74 69  |\"zzinc_statisti|
035c8e80  63 73 5c 22 3b 69 3a 31  3b 73 3a 33 31 3a 5c 22  |cs\";i:1;s:31:\"|
......
035d1ee0  00 62 62 73 6e 65 77 00  43 4f 4d 4d 49 54 9d bd  |.bbsnew.COMMIT..|
</pre>
整个更新语句的大小为035d1ee0 - 035b6ff0 = 110320 bytes, 期间还有3个中断部分, 可以看到35c8e72位置信息在035c8e70和035c8e80之间, 处于事件的中间, 并不是事件的结尾部分或下一事件的开头部分, 所以对于slave的错误：log event entry exceeded max_allowed_packet， 可能是由于中断引起的错误信息;

处理方式可以在master中 flush binary logs,轮询到新的bin-log-001115文件, binlog 1114中间漏掉的内容可以通过percona pt-table-checksum工具补上, 近期准备重做slave, percona部分可以忽略掉;

详见: <a href="http://www.percona.com/blog/2014/05/14/max_allowed_packet-and-binary-log-corruption-in-mysql/"><font color="green">http://www.percona.com/blog/2014/05/14/max_allowed_packet-and-binary-log-corruption-in-mysql/</font></a>