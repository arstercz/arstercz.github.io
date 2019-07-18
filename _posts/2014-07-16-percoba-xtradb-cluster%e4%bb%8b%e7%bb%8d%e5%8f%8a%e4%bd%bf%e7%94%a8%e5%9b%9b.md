---
id: 229
title: percoba XtraDB Cluster介绍及使用(四)
date: 2014-07-16T11:13:36+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=229
permalink: '/percoba-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e5%9b%9b/'
dsq_thread_id:
  - "3580062974"
dsq_needs_sync:
  - "1"
categories:
  - percona
tags:
  - XtraDB
---
<strong>流控</strong>
Flow Control
<a href="http://galeracluster.com/documentation-webpages/nodestates.html"><font color="green">http://galeracluster.com/documentation-webpages/nodestates.html</font></a>
<a href="http://galeracluster.com/documentation-webpages/weightedquorum.html"><font color="green">http://galeracluster.com/documentation-webpages/weightedquorum.html</font></a>

测试环境说明见 <a href="http://arstercz.com/percona-xtradb-cluster%E4%BD%BF%E7%94%A8%E4%BA%8C/">http://arstercz.com/percona-xtradb-cluster%E4%BD%BF%E7%94%A8%E4%BA%8C/</a>
以下说明以重启test3节点为例:

按手册的介绍来看， 节点状态分为以下6种:
![galerafsm](images/articles/201407/galerafsm.png)

集群节点状态变化

```
1. 节点开始连接到集群中的PC(primary component);
2. 开始传输状态及数据等, 新加的节点环岛writesets;
3. 节点接收集群数据状态的镜像, 并且开始应用缓存中的writeset到本地, 流控也切换到减少slave队列的模式;
4. 节点赶上了cluster, wsrep_ready为on状态,节点可以处理事务请求;
5. 正常的节点接收到状态传输的请求, 流控将其更为donor状态,如下面的test2;
6. donor传输完后，更为joined状态；如下的test2;
```

<strong>详细介绍各节点的状态信息</strong>:
<strong>open</strong>: 此状态的节点不是Cluster的一部分, 不能进行replicate和缓存writesets操作，也不存在流控；该状态主要用来和Cluster中的其它节点进行必要的信息(如UUID等)校验, 并完成选举(quorum),如以下信息:
```
<font color=red>Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Shifting CLOSED -> OPEN (TO: 0)</font>
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Opened channel 'test-cluster'
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Waiting for SST to complete.
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 2, memb_num = 3
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: STATE EXCHANGE: Waiting for state UUID.
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: STATE EXCHANGE: sent state msg: c7f31091-07f9-11e4-b5db-d3836cc0ef24
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: STATE EXCHANGE: got state msg: c7f31091-07f9-11e4-b5db-d3836cc0ef24 from 0 (cz-test2)
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: STATE EXCHANGE: got state msg: c7f31091-07f9-11e4-b5db-d3836cc0ef24 from 1 (cz-test1)
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: STATE EXCHANGE: got state msg: c7f31091-07f9-11e4-b5db-d3836cc0ef24 from 2 (cz-test3)
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Quorum results:
Jul 10 14:16:51 cz-test3 mysqld-3321: #011version    = 3,
Jul 10 14:16:51 cz-test3 mysqld-3321: #011component  = PRIMARY,
Jul 10 14:16:51 cz-test3 mysqld-3321: #011conf_id    = 24,
Jul 10 14:16:51 cz-test3 mysqld-3321: #011members    = 2/3 (joined/total),
Jul 10 14:16:51 cz-test3 mysqld-3321: #011act_id     = 47,
Jul 10 14:16:51 cz-test3 mysqld-3321: #011last_appl. = -1,
Jul 10 14:16:51 cz-test3 mysqld-3321: #011protocols  = 0/5/2 (gcs/repl/appl),
Jul 10 14:16:51 cz-test3 mysqld-3321: #011group UUID = 9848cdcf-e869-11e3-94a5-3f8583faad7e
```
<strong>primary</strong>:和open状态类似,此状态的节点不是Cluster的一部分, 不能进行replicate和缓存writesets操作，也不存在流控;该状态完成(state transfer)状态及数据传输的准备工作, 如计算增量的传输信息, 数据传输的方式, 选取哪个节点为donor等，如下:
```
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Flow-control interval: [28, 28]
<font color=red>Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: Shifting OPEN -> PRIMARY (TO: 47)</font>
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: State transfer required: 
Jul 10 14:16:51 cz-test3 mysqld-3321: #011Group state: 9848cdcf-e869-11e3-94a5-3f8583faad7e:47
Jul 10 14:16:51 cz-test3 mysqld-3321: #011Local state: 9848cdcf-e869-11e3-94a5-3f8583faad7e:31
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Note] WSREP: New cluster view: global state: 9848cdcf-e869-11e3-94a5-3f8583faad7e:47, view# 25: Primary, number of nodes: 3, my index: 2, protocol version 2
Jul 10 14:16:51 cz-test3 mysqld-3321: 2014-07-10 14:16:51 399 [Warning] WSREP: Gap in state sequence. Need state transfer.
Jul 10 14:16:53 cz-test3 mysqld-3321: 2014-07-10 14:16:53 399 [Note] WSREP: Running: 'wsrep_sst_xtrabackup-v2 --role 'joiner' --address '10.0.21.17' --auth 'sstuser:s3cret' --datadir '/web/mysql/node3321/data/' --defaults-file '/web/mysql/node3321/my.node.cnf' --parent '399'  '' '
Jul 10 14:16:53 cz-test3 mysqld-3321: WSREP_SST: [INFO] Streaming with xbstream (20140710 14:16:53.880)
Jul 10 14:16:53 cz-test3 mysqld-3321: WSREP_SST: [INFO] Using socat as streamer (20140710 14:16:53.883)
Jul 10 14:16:55 cz-test3 mysqld-3321: WSREP_SST: [INFO] Evaluating timeout 100 socat -u TCP-LISTEN:4444,reuseaddr stdio | xbstream -x; RC=( ${PIPESTATUS[@]} ) (20140710 14:16:55.023)
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Prepared SST request: xtrabackup-v2|10.0.21.17:4444/xtrabackup_sst
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: wsrep_notify_cmd is not defined, skipping notification.
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: REPL Protocols: 5 (3, 1)
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Service thread queue flushed.
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Assign initial position for certification: 47, protocol version: 3
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Service thread queue flushed.
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Prepared IST receiver, listening at: tcp://10.0.21.17:4568
<font color=red>Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Member 2.0 (cz-test3) requested state transfer from '*any*'. Selected 0.0 (cz-test2)(SYNCED) as donor.</font>
```
该过程中选取了test2节点为donor.
<strong>donor</strong>: 新加的节点选取该节点为Cluster的数据源进行数据及状态的传输,如下:
```
<font color=red>Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: Shifting SYNCED -> DONOR/DESYNCED (TO: 47)</font>
Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: IST request: 9848cdcf-e869-11e3-94a5-3f8583faad7e:31-47|tcp://10.0.21.17:4568
Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: wsrep_notify_cmd is not defined, skipping notification.
<font color=red>Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: Running: 'wsrep_sst_xtrabackup-v2 --role 'donor' --address '10.0.21.17:4444/xtrabackup_sst' --auth 'sstuser:s3cret' --socket '/web/mysql/node3321/data/s3321' --datadir '/web/mysql/node3321/data/' --defaults-file '/web/mysql/node3321/my.node.cnf'   '' --gtid '9848cdcf-e869-11e3-94a5-3f8583faad7e:31' --bypass' </font>
Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: sst_donor_thread signaled with 0
Jul 10 14:16:56 cz-test2 mysqld-3321: 2014-07-10 14:16:56 26423 [Note] WSREP: async IST sender starting to serve tcp://10.0.21.17:4568 sending 32-47
Jul 10 14:16:56 cz-test2 mysqld-3321: WSREP_SST: [INFO] Streaming with xbstream (20140710 14:16:56.987)
Jul 10 14:16:56 cz-test2 mysqld-3321: WSREP_SST: [INFO] Using socat as streamer (20140710 14:16:56.989)
Jul 10 14:16:57 cz-test2 dhclient[912]: DHCPREQUEST on eth0 to 10.0.21.9 port 67 (xid=0x5bb66842)
Jul 10 14:16:57 cz-test2 dhclient[912]: DHCPACK from 10.0.21.9 (xid=0x5bb66842)
Jul 10 14:16:58 cz-test2 mysqld-3321: WSREP_SST: [INFO] Bypassing the SST for IST (20140710 14:16:58.163)
Jul 10 14:16:58 cz-test2 mysqld-3321: WSREP_SST: [INFO] Evaluating xbstream -c ${INFO_FILE} ${IST_FILE} | socat -u stdio TCP:10.0.21.17:4444; RC=( ${PIPESTATUS[@]} ) (20140710 14:16:58.170)
Jul 10 14:16:58 cz-test2 mysqld-3321: WSREP_SST: [INFO] Total time on donor: 0 seconds (20140710 14:16:58.211)
Jul 10 14:16:58 cz-test2 mysqld-3321: WSREP_SST: [INFO] Cleaning up temporary directories (20140710 14:16:58.214)
Jul 10 14:17:03 cz-test2 mysqld-3321: 2014-07-10 14:17:03 26423 [Note] WSREP: 0.0 (cz-test2): State transfer to 2.0 (cz-test3) complete.
<font color=red>Jul 10 14:17:03 cz-test2 mysqld-3321: 2014-07-10 14:17:03 26423 [Note] WSREP: Shifting DONOR/DESYNCED -> JOINED (TO: 47)</font>
Jul 10 14:17:03 cz-test2 mysqld-3321: 2014-07-10 14:17:03 26423 [Note] WSREP: 2.0 (cz-test3): State transfer from 0.0 (cz-test2) complete.
```
<strong>joiner</strong>:该状态的节点不会应用writesets到本地, 而是缓存writesets,缓存的大小受gcs.recv_q_hard_limit,gcs_max_throttle和gcs.recv_q_soft_limit三个参数的控制, 如下,接收donor传输过来的数据到本地cache:
```
<font color=red>Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Shifting PRIMARY -> JOINER (TO: 47)</font>
Jul 10 14:16:56 cz-test3 mysqld-3321: 2014-07-10 14:16:56 399 [Note] WSREP: Requesting state transfer: success, donor: 0
Jul 10 14:16:58 cz-test3 mysqld-3321: WSREP_SST: [INFO] xtrabackup_ist received from donor: Running IST (20140710 14:16:58.232)
Jul 10 14:16:58 cz-test3 mysqld-3321: WSREP_SST: [INFO] Total time on joiner: 0 seconds (20140710 14:16:58.235)
Jul 10 14:16:58 cz-test3 mysqld-3321: WSREP_SST: [INFO] Removing the sst_in_progress file (20140710 14:16:58.238)
Jul 10 14:16:58 cz-test3 mysqld-3321: 2014-07-10 14:16:58 399 [Note] WSREP: SST complete, seqno: 31
......
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] Event Scheduler: Loaded 0 events
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Signalling provider to continue.
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: inited wsrep sidno 2
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: SST received: 9848cdcf-e869-11e3-94a5-3f8583faad7e:31
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Receiving IST: 16 writesets, seqnos 31-47
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: IST received: 9848cdcf-e869-11e3-94a5-3f8583faad7e:47
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: 0.0 (cz-test2): State transfer to 2.0 (cz-test3) complete.
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: 2.0 (cz-test3): State transfer from 0.0 (cz-test2) complete.
```

<strong>joined</strong>:此状态的节点可以应用writeset到本地, flow control也通过控制writeset缓存来确保该节点可以赶上cluster集群。如下(测试的时候没有做数据更细, 就没有显示apply相关的信息):
```
<font color=red>Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Shifting JOINER -> JOINED (TO: 47)</font>
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Member 0.0 (cz-test2) synced with group.
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Member 2.0 (cz-test3) synced with group.
```
<strong>synced</strong>:flow control切换到尽量减少slave队列的模式， 该状态的节点wsrep_ready为on，及可以接受应用程序的sql请求。如下:
```
<font color=red>Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Shifting JOINED -> SYNCED (TO: 47)</font>
Jul 10 14:17:03 cz-test3 mysqld-3321: 2014-07-10 14:17:03 399 [Note] WSREP: Synchronized with group, ready for connections
```

综上, 流控发生在joined和synced两个状态, 即正常运行的node， 都有发生的可能, 本质上是为了控制复制及复制相关的处理。更多信息见: <a href="http://www.mysqlperformanceblog.com/2013/05/02/galera-flow-control-in-percona-xtradb-cluster-for-mysql/"><font color="green">http://www.mysqlperformanceblog.com/2013/05/02/galera-flow-control-in-percona-xtradb-cluster-for-mysql/</font></a>
