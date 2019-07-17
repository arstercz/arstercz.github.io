---
id: 237
title: percoba XtraDB Cluster介绍及使用(三)
date: 2014-07-10T19:38:22+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=237
permalink: '/percoba-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e4%b8%89/'
dsq_thread_id:
  - "3590202467"
dsq_needs_sync:
  - "1"
categories:
  - percona
tags:
  - XtraDB
---
<strong>重启Cluster</strong>
详见: <a href="http://galeracluster.com/documentation-webpages/restartingacluster.html"><font color="blue">http://galeracluster.com/documentation-webpages/restartingacluster.html</font></a>

如果需要重启整个集群，可以如下操作:
Occarsionally, you may have to restart the entire Galera Cluster. proceed as follows:
```<font color="blue">
1. Identify the node with the most advanced node state ID. See chapter Identifying the Most Advanced Node.
2. Start the node as the first node of the cluster.
3. Start the rest of the nodes as usual.
</font>
```
<!--more-->


<strong>识别最新的node节点</strong>
查看文件grastate.dat, 默认保存在datadir.状态信息说明如下:

1. 当node节点正常关闭时,seqno正常显示,如下:
```
# GALERA saved state
version: 2.1
uuid:    5ee99582-bb8d-11e2-b8e3-23de375c1d30
seqno:   8204503945773
cert_index:
```
However, if the grastate.dat file looks like the example below, the node has crashed:

2. 在node正常运行时seqno为-1值，关闭后如果为-1表示程序crash或没有正常关闭
```
# GALERA saved state
version: 2.1
uuid:    5ee99582-bb8d-11e2-b8e3-23de375c1d30
seqno:   -1
cert_index:
```
可以通过wsrep-recover选项得到相应的GTID状态信息
To find the sequence number of the last committed transaction, run mysqld with the --wsrep-recover option. This option will recover the InnoDB table space to a consistent state, print the corresponding GTID into the error log and exit. In the error log, you can see something like this:
```
130514 18:39:13 [Note] WSREP: Recovered position: 5ee99582-bb8d-11e2-b8e3-23de375c1d30:8204503945771
```
<font color="red">手工编辑更新正确的seqno字段值, 再正常启动MySQL</font>
This is the state ID. Edit the grastate.dat file and update the seqno field manually or let mysqld_safe automatically recover it and pass it to the mysqld next time you start it.

3. 如果是下面的状态信息, 表示服务在执行期间做了非事务操作或者因为数据不一致引起的中断.
If the grastate.dat file looks like the example below, the node has either crashed during execution of a non-transactional operation (such as ALTER TABLE) or aborted due to a database inconsistency.
```
# GALERA saved state
version: 2.1
uuid:    00000000-0000-0000-0000-000000000000
seqno:   -1
cert_index:
```
You still can recover the ID of the last committed transaction from InnoDB as described above. However, the recovery is rather meaningless as the node state is probably corrupted and may not even be functional. If there are no other nodes with a well defined state, a thorough database recovery procedure (similar to that on a standalone MySQL server) must be performed on one of the nodes, and this node should be used as a seed node for new cluster. If this is the case, there is no need to preserve the state ID.

<strong>重置quorum</strong>
集群中超过半数的节点出现故障的时候, 其它的节点可能会无法连接到PC(primary Component),这种情况下所有的节点都会返回Unknown command 给查询语句。
我们可以通过重置quorum来重新引导PC:
1. 找出具有最新状态的节点:
```
SHOW STATUS LIKE 'wsrep_last_committed'
```
最大值即为最新。
2. 在最新状态的节点上执行:
```
SET GLOBAL wsrep_provider_options='pc.bootstrap=yes'
```
3. 上面两步重置了quorum, 拥有该最新node的组件将会成为PC, 其它节点将同步到该节点的状态, 之后，集群就可以正常处理sql请求.