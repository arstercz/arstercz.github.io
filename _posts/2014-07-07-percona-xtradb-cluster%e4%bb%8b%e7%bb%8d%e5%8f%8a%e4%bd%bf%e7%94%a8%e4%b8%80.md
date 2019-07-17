---
id: 191
title: percona XtraDB Cluster介绍及使用(一)
date: 2014-07-07T20:23:05+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=191
permalink: '/percona-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e4%b8%80/'
dsq_thread_id:
  - "3465796994"
dsq_needs_sync:
  - "1"
categories:
  - percona
tags:
  - percona
  - XtraDB
---
<a href="http://www.percona.com/software/percona-xtradb-cluster">http://www.percona.com/software/percona-xtradb-cluster</a>     #software
<a href="http://www.percona.com/doc/percona-xtradb-cluster/5.6/">http://www.percona.com/doc/percona-xtradb-cluster/5.6/</a>     #refernce page
<a href="http://dev.mysql.com/doc/relnotes/mysql/5.6/en/index.html">http://dev.mysql.com/doc/relnotes/mysql/5.6/en/index.html</a>  #5.6 relaese notes
<a href="https://launchpad.net/percona-xtradb-cluster">https://launchpad.net/percona-xtradb-cluster</a>               #bug跟踪
<a href="http://galeracluster.com/documentation-webpages/index.html">http://galeracluster.com/documentation-webpages/index.html</a> #galera cluster ref doc.
<a href="http://galeracluster.com/documentation-webpages/limitations.html">http://galeracluster.com/documentation-webpages/limitations.html</a>   #与MySQL Server的不同

<strong>FAQ:</strong>
1.为什么使用xtradb cluster?
node节点之间数据强同步，不用做后期的数据校验；内置故障切换功能,可以逐步摆脱mha相关的第三方工具依赖；由于数据强一致性的保证，业务不适合做写敏感的架构, 少写多读会得到很好的扩展；公网+encrption可以做到多数据中心的数据同步,适合后期业务的多节点部署；

2.为什么使用5.6版本?
oracle官方在5.5系列中做出了很大的代价来保证基础功能的稳定，5.6逐步增加许多额外的扩展功能，如slave自动同步，buffer pool dump/restore, 内置memcache，fulltext等。 使用5.6可以做到最终业务的版本统一。

<!--more-->


3.xtradb cluster和Oracle MySQL有什么不同?
全部兼容MySQL Server,也可以从Percona MySQL Server升级到Xtradb cluster。两个鲜明的特征包括数据同步和故障恢复。
xtradb cluster主要不同于MySQL包括以下几方面：
<pre>
1. 节点之间的复制(replication)仅支持InnoDB引擎, 其它类型的write不会复制(包括mysql.*表),DDL语句以statement级别复制,即意味着create user ... 和 grant ...可以复制，但是insert into mysql.user .... 不会被复制。

2. 没有主键的表在各节点可能以不同的顺序显示出来,比如select ... limit..., DELETE操作在没有主键的表中不被支持。不要使用没有主键的表(也可能基于row格式的复制)

3. 不要开启 query cache(默认关闭);

4. 由于commit的时候可能会回滚(rollback), 不支持XA事务;

5. 事务大小, Galera Cluster没有限制事务大小, 为了避免大事务(比如LOAD DATA)对节点的影响, wsrep_max_ws_rows和wsrep_max_ws_size限制了事务行数为128K,事务大小1GB。

6. 基于集群级别的并发控制, 一个事务的提交可能会被取消掉。

7. 不支持Windows系统.

8. 不要使用binlog-do-db和binlog-ignore-db, 这些选项仅支持DML语句, 不支持DDL语句, 使用这些选项可能会引起数据的错乱。

9. 如果选择rsync方式传输, 就不要指定character_set_server为utf16, utf32或ucs2字符集, Server可能会崩溃.
</pre>

<strong>一. percona XtraDB Cluster 术语说明</strong>

<b>LSN</b>: 每个InnoDB page(通常16kb大小)含有一个日志序列(log sequence number),称作LSN。LSN是整个database的系统版本号。每个page的LSN表示了最近该页的变动(change)。

<b>GTID</b>: Global transaction id. 在XtraDB中GTID由UUID和一个用来标识顺序更改的序列数字组成.

<b>UUID</b>: 全局唯一标识，唯一标识了状态和节点的序列改变.

<b>HAProxy</b>: 一个基于TCP和HTTP协议的应用，用来提供快速，稳定的高可用服务,包括负载均衡，代理协议等。

<b>Primary Component</b>: 如果一个单节点失效， cluster可能会因为网络的原因分裂成多个部分。在这种状况下，仅有一个部分可以持续修改数据库的状态以避免引起分歧，该部分则成为Primary Component(PC)，

<b>SST</b>: State Snapshot Transfer. 状态(数据)快照传输，全量的从一个node传输到另一个node. 当一个新node加入Cluster的时候, 必须从已有的node传输数据到新node. SST传输方式有三种: mysqldump, rsync, xtrabackup.前两种传输时会锁表, xtrabackup仅在传输系统表的时候锁表.

<b>IST</b>: Incremental State Transfer. 用来替代SST传输数据的方式, 只有在写集(writeset)还存在于donor的writeset cache中时,IST才可以抓取批量收到的writeset.

<b>donor node</b>:  被选举为提供状态传输(SST或IST)的节点。

<b>Xtrabackup</b>: 支持MySQL热备的开源工具, 备份InnoDB期间不会加锁, 该工具由percona公司开发。

<b>cluster replication</b>: 为cluster members提供的正常replication, 能以单播或多播的方式进行加密。

<b>joiner node</b>: 要加入到cluster中的node, 通常也是状态传输的目标。

<b>node</b>:一个集群的节点就是一个处于集群中的MySQL实例。

<b>quorum</b>: 多数节点( > 50%), 在一个网络区域中, 只有cluster保持有quorum, 并且quorum中的node默认处于Primary状态。

<b>primary cluster</b>: 一个持有quorum的cluster. 一个non-primary集群不会允许任何操作，并且任何试图read或write的client端都会返回'Unknown command error'错误。

<b>split brain</b>: 当集群中的两部分(part)不能连接，一部分(one part)确信另一个部分(the other part)不在运行的时候则发生分裂(splite brain), 这种情况会造成数据不一致。

<b>.opt</b>: MySQL在每个database中都有一个.opt后缀的文件保存该database的选项信息(比如charset, collation).


<strong>二. percona XtraDB Cluster生成文件说明</strong>

<b>GRA_x.log</b>：在row格式下执行失败的事务(比如drop一个不存在的表等),这些文件保存了这些事务的binlog events。该功能禁止了slave thread应用这些执行失败的事务。warning或error信息会在mysql error log中显示。比如在一个node中drop不存在的表, 其他node会生成GRA_x.log文件,error log中也会显示一下信息:
<pre>
Jun  5 11:34:42 cz-test2 mysqld-3321: 2014-06-05 11:34:42 26423 [ERROR] Slave SQL: Error 'Unknown table 'percona.list'' on query. Default database: 'percona'. Query: 'drop table list', Error_code: 1051
</pre>

<b>galera.cache</b>: 该文件存储主要的写集(writeset), 被实现为一个永久的环路缓冲区(ring-buffer),在node初始化的时候,它被用来在磁盘上预分配空间,默认128M, 这个值过大的话，更多的写集会被缓冲, 而且重新加入的的节点(rejoining node)更倾向于采用IST来取代SST传输数据。

<b>grastate.dat</b>：保存了Galera的状态信息。

<b>三. Percona XtraDB Cluster 如何保证写一致性(consistency of writes)</b>
<img src="http://img.arstercz.com/articles/201407/XtraDBClusterUML1.png">

所有的query在本地node执行， 并且仅在commit存在特殊的处理。当commit有问题时， 事务必须在所有node验证, 没有验证通过则返回error信息. 随后，事务被应用到本地node。

commit响应时间包括:
<pre>
网络轮询时间；
验证时间；
本地应用；(远程apply事务不影响commit响应时间)。
</pre>
两个重要的特性:
<pre>
1. 控制wsrep_slave_threads参数来实现多并发replication.
2. 一些其它因素，比如master的性能更好,执行事件要比slave快，这就造成了短暂的同步不一致(out-of-sync),这时候读取slave结果就为空, wsrep_causal_reads参数用来控制读取slave的行为，它使得操作一直等待直到事件被执行；
</pre>

<b>四. 监控</b>
<b>1. cluster完整性检测</b>
status 变量:
wsrep_cluster_state_uuid: cluster中的所有node的该变量的值必须一样, 不一样表示node没有连接到cluster。

wsrep_cluster_conf_id: 次变量用来表示node是否在它相应的cluster中。cluster中所有node的该变量值应该一样， 不一样则表示nodes被分隔开了, node恢复的时候该变量也会恢复。

wsrep_cluster_size: 表示cluster中有多少node节点， 等于预期的数量则表示所有node连接到了cluster。

wsrep_cluster_status:  正常情况下值为Primary, 如果不为Primay,则该node当前不能操作(归咎于多成员关系的改变和quorum的缺失), 同时也可能满足split-brain的条件。


如果cluster中没有node 连接上(connected) PC(就是所有node属于同一部分,但是node都是non-primary状态), 可以参考<a href="http://galeracluster.com/documentation-webpages/quorumreset.html#id1">http://galeracluster.com/documentation-webpages/quorumreset.html#id1</a> 来操作Reset quorum。
如果不能Reset quorum, cluster则必须手动进行重引导(rebootstrapped),如下:
<pre>
1. 关闭所有node节点；
2. 从最近更新(most advanced node)的node节点开始重启所有的nodes(检查 wsrep_last_committed状态变量找到最近更新的node节点)。
</pre>

<b>2. 节点状态检查</b>
wsrep_ready: 该状态变量为On(Ture)时， 该node可以接受SQL,否则所有sql query返回'Unknown Command Error',并且需要检查wsrep_connected和wsrep_local_state_comment,在一个PC中wsrep_local_state_comment变量的值通常包括Joining, Waiting for SST, Joined, Synced或者Donor。在wsrep_ready = OFF时， 且wsrep_local_state_comment为Joining, Waiting for SST,或者Joined时，该node仍然在和cluster同步(syncing)；在non-primay部分里,节点的wsrep_local_state_comment状态应该是Initialized。

wsrep_connected: 值为OFF,表示该node没有连接到任何cluster 部分。


<b>3. 复制健康检查</b>
wsrep_flow_control_paused: 如果该变量值的范围是0.0 ~ 1.0, 表示复制从上次 show status命令后停止的时间。1.0为完全停止(complete stop). 该变量的值应该接近0.0。保证该值的主要方式包括增加wsrep_slave_threads的数量和从cluster移除执行慢的节点。

wsrep_cert_deps_distance: 该变量表示平均有多少事务可以并发的执行。wsrep_slave_threads的值不应该超过该变量的值。

<b>4. 检测网络延迟问题</b>
如果网络中存在延迟现象， 检查以下变量的值:
wsrep_local_send_queue_avg: 该变量的值较高的话， 网络链接可能存在延迟。如果是这个原因，原因可能分布在多层,包括从物理到系统方面的层次。

<b>五. cluster故障恢复</b>
当nodes连接到一个cluster后，该node即成为cluster的成员; 没有相关配置来明确定义所有可能cluster node的列表。因此，在一个节点加入cluster的时候，cluster的大小就增加，反之减小。cluster的大小用来实现quorum的选举。当一个或多个node没有响应(被怀疑已经不是cluster的一部分)的时候，则完成quorum的选举。响应超时由evs.suspect_timeout(default 5 s)指定,当然在一个node关闭的时候，写操作可能会被blocked,blocked的时间可能超过timeout时间。

一旦一个node或多个node断开连接, 剩下的node则会进行quorum的选举操作; 在断开之前，如果总nodes里的多数node保持连接,则保留分区。对于网络分区(network partition) 一些node可能在非连接(network disconnect)区域内继续存活(alive and active),这种状况下只有quorum是一直运行的，没有quorum运行的分区中的节点则会进入non-primary状态。

鉴于以上的原因，在2个node的集群中做自动故障恢复几乎是不可能的， 因为失败的node节点会使得剩下的node进入non-primary状态(只有一个node没法做quorum)。更多的，在网络不连通的时候，不同交换机下的两个node可能会有一点满足分裂(split brain)条件的可能性,这时候不会保留quorum,并且两个node都会进入non-primary状态。所以对自动故障恢复来说，以下的'3 原则'值得推荐:
<pre>
  单交换机下的cluster至少应该有3个node；
  分布不同交换机下的cluster, 应该至少跨越3个交换机；
  分布不同网络(子网)下的cluster, 应该至少3个网络；
  分布于不同数据中心下的cluster, 应该至少3个数据中心；
</pre>
以上是在预防自动故障恢复工作过程中的防止分裂的方法。当然出于成本的考虑，增加交换机、数据中心等在很多情况下是不太现实的，Galera arbitrator(仲裁)是个可选的方式，它可以参与到quorum的选举，以组织split brain发生，但是它不会保留任何数据，也不会启动mysqld服务, 它是一个独立的deamon程序，详见<a href="http://galeracluster.com/documentation-webpages/arbitrator.html">http://galeracluster.com/documentation-webpages/arbitrator.html</a>


<b>关于quorum举例如下:</b>
假如我们有3个nodes的cluser, 如果手工隔离1个node,则现在2个node可以互相通信，1个node只能看到它自己，这个时候2个node部分进行quorum计算,达到了2/3(66%),1个node则只达到1/3(33%),这种情况下一个node部分就会停止服务(因为quorum没有达到50%)。quorum算法有助于选举一个Primary组件(Primary Component)并且保证了cluster中没有多个PC(primary component)。如果增加了pc.ignore_quorum, 停掉的node也可以继续接受queries, 单会引起两边数据的不一致，在cluster各节点恢复的时候, 会引起错误,设置了pc.ignore_quorum的node所作的更新会重新被覆盖(SST)。

<b>2 nodes cluster配置(pc.ignore_quorum 和 pc.ignore_sb)</b>: <a href="http://www.mysqlperformanceblog.com/2012/07/25/percona-xtradb-cluster-failure-scenarios-with-only-2-nodes/">http://www.mysqlperformanceblog.com/2012/07/25/percona-xtradb-cluster-failure-scenarios-with-only-2-nodes/</a>

重置quorum: <a href="http://galeracluster.com/documentation-webpages/quorumreset.html">http://galeracluster.com/documentation-webpages/quorumreset.html</a>