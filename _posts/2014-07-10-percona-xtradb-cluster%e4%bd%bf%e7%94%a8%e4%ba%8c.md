---
id: 216
title: percona XtraDB Cluster介绍及使用(二)
date: 2014-07-10T15:34:55+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=216
permalink: '/percona-xtradb-cluster%e4%bd%bf%e7%94%a8%e4%ba%8c/'
dsq_thread_id:
  - "3468523591"
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - percona
  - XtraDB
---
<strong>安装说明</strong>
Centos系统安装参考 <a href="http://www.percona.com/doc/percona-xtradb-cluster/5.6/howtos/cenots_howto.html"><font color="green">http://www.percona.com/doc/percona-xtradb-cluster/5.6/howtos/cenots_howto.html</font></a>

<pre>
node #1
CentOS release 6.5 (Final)
hostname: cz-cluster1
IP: 10.0.21.5

node #2
CentOS release 6.5 (Final)
hostname: cz-cluster2
IP: 10.0.21.7

node #3
CentOS release 6.5 (Final)
hostname: cz-cluster3
IP: 10.0.21.17
</pre>

三台node都以binary方式安装(解压即可用)<a href="http://www.percona.com/software/percona-xtradb-cluster">http://www.percona.com/software/percona-xtradb-cluster</a>
<!--more-->


node节点配置和手册页略有不同,如下:
<pre>
port = 3321
datadir = /web/mysql/node3321/data

#XtraDB needed.
wsrep_provider=/opt/Percona-XtraDB-Cluster-5.6.15-25.5.769.Linux.x86_64/lib/libgalera_smm.so # Path to Galera library
wsrep_cluster_address=gcomm://10.0.21.5,10.0.21.7,10.0.21.17  # Cluster connection URL contains the IPs of each node.
explicit_defaults_for_timestamp
binlog_format=ROW                   # In order for Galera to work correctly binlog format should be ROW
innodb_autoinc_lock_mode = 2        # how InnoDB autoincrement locks are managed and is a requirement for Galera
wsrep_node_address = 10.0.21.7   # node address
wsrep_sst_method = xtrabackup-v2    # sst method
wsrep_cluster_name = test-cluster   # cluster name
wsrep_sst_auth="sstuser:s3cret"     # Authentication for SST method
</pre>
wsrep_provider提供相应路径的库文件名, cluster为三台node的ip地址；
innodb_autoinc_lock_mode用来控制自增键的增长，因为在cluster中多个node都是可以写的, 自增键需要控制，该值为2表示自增键可以间断增长,见<a href="http://dev.mysql.com/doc/refman/5.6/en/innodb-auto-increment-handling.html">http://dev.mysql.com/doc/refman/5.6/en/innodb-auto-increment-handling.html</a>;
sst传输方式选择xtrabackup(常见的几种方式为mysqldump, rsync, rsync_wan, xtrabackup), 以支持热拷贝,开启该选项,每个node节点需要安装innobackupex(xtrabackup); 
sst_auth设置的用户和密码需要手工在xtraDB中设置,xtrabackup通过sst_auth用户来完成SST或IST。

<font color="red">注: MyISAM, InnoDB的配置和传统配置一样，这里不再贴出来, 不过在5.6版本中(包括cluster和传统的)同步方式新增了GTID机制， 有很多MyISAM表的话，可能会引起其它一些问题。</font>


<strong>启动方式</strong>:
第一台node启动需要以bootstrap-pxc方式初始化wsrep_cluster_address(cluster地址),新建了一个集群,如下启动脚本：
<pre>
 'bootstrap-pxc')
    echo "Bootstrapping PXC (Percona XtraDB Cluster)"
    $0 start --wsrep-new-cluster
 ;;
</pre>
剩下两台node以普通方式启动。

查看wsrep状态,三台node的状态都是一致的:
<pre>
show status like 'wsrep%'
| wsrep_local_state_uuid       | 9848cdcf-e869-11e3-94a5-3f8583faad7e |
| wsrep_protocol_version       | 5                                    |
| wsrep_last_committed         | 53                                   |
| wsrep_replicated             | 18                                   |
| wsrep_cluster_state_uuid     | 9848cdcf-e869-11e3-94a5-3f8583faad7e |
| wsrep_cluster_status         | Primary                              |
| wsrep_connected              | ON                                   |
| wsrep_local_bf_aborts        | 0                                    |
| wsrep_local_index            | 1                                    |
| wsrep_provider_name          | Galera                               |
| wsrep_provider_vendor        | Codership Oy <info@codership.com>    |
</pre>

做一个简单的多节点插入说明:
node1节点创建test表，node2,node3正常显示test表
<pre>
       Table: test
Create Table: CREATE TABLE `test` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(30) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8
</pre>

分别插入一条记录(测试的时候以node2 bootstrap-pxc启动的, 和阅读者的测试结果会略有不同,但结论是一样的):
<pre>
#节点1
mysql root@[cz-cluster1:s3321 percona] > insert into test (name) values('cluster-test1');
Query OK, 1 row affected (0.01 sec)
#节点3
mysql root@[cz-cluster3:s3321 percona] > insert into test (name) values('cluster-test3');
Query OK, 1 row affected (0.01 sec)
#节点2
mysql root@[cz-cluster2:s3321 percona] > insert into test (name) values('cluster-test2');
Query OK, 1 row affected (0.01 sec)
</pre>

查看插入的记录, 注意自增键的变化:
<pre>
mysql root@[localhost:s3321 percona] > select * from test;
+----+---------------+
| id | name          |
+----+---------------+
|  2 | cluster-test1 |
|  3 | cluster-test3 |
|  4 | cluster-test2 |
+----+---------------+
3 rows in set (0.00 sec)
</pre>

<strong>防火墙设置</strong>
各节点之间需要互通以下端口:
<pre>
3306: mysqld服务端口, mysqldump SST;
4567: Gelera Cluster复制;
4568: IST;
4444: 所有的SST,包括mysqldump;
</pre>

术语及理论说明见: <a href="http://highdb.com/percona-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e4%b8%80/"><font color="blue">http://highdb.com/percona-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e4%b8%80/</font></a>