---
id: 403
title: MySQL-audit审计插件
date: 2014-11-05T14:52:39+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=403
permalink: '/mysql-audit%e5%ae%a1%e8%ae%a1%e6%8f%92%e4%bb%b6/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3465095647"
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - audit
  - MySQL
---
MySQL SQL审计插件
<a href="https://github.com/mcafee/mysql-audit"><font color="green">https://github.com/mcafee/mysql-audit</font></a>
<a href="https://bintray.com/mcafee/mysql-audit-plugin/release"><font color="green">https://bintray.com/mcafee/mysql-audit-plugin/release</font></a>

安装:
<a href="https://github.com/mcafee/mysql-audit/wiki/Installation"><font color="green">https://github.com/mcafee/mysql-audit/wiki/Installation</font></a>
需要计算出mysqld版本偏移值: <a href="https://github.com/mcafee/mysql-audit/wiki/Troubleshooting"><font color="green">https://github.com/mcafee/mysql-audit/wiki/Troubleshooting</font></a>
<!--more-->


my.cnf配置增加audit选项:
注: audit_offsets由offset-extract.sh脚本生成，依赖gdb;
    audit_whitelist_users增加用户白名单, 以防止程序审核sql的时候重复记录而造成无限循环;
```
# audit plugin
plugin-load=AUDIT=libaudit_plugin.so
audit_offsets=6456, 6504, 4064, 4504, 104, 2584, 8, 0, 16, 24
audit_json_file=1
audit_json_socket_name=/data/mysql/node3306/data/s_audit
audit_json_socket=1
audit_json_log_file=/data/mysql/node3306/data/audit.log
audit_record_cmds=insert,update,delete,select
audit_whitelist_users=root,audit
```

audit插件包括两种输出格式:
1. json输出到指定文件,如上面的audit.log,输出信息很丰富,包括日期，线程id, 查询id, 用户, 主机, 命令类型, 库, 表, SQL语句,对sql审核和检测事务是否正常使用有很好的帮助作用。
```
{"msg-type":"activity","date":"1409226399778","thread-id":"1","query-id":"52","user":"root","priv_user":"root","host":"localhost","cmd":"select","objects":[{"db":"test","name":"t2","obj_type":"TABLE"}],"query":"select * from t2"}
{"msg-type":"activity","date":"1409226477630","thread-id":"1","query-id":"54","user":"root","priv_user":"root","host":"localhost","cmd":"select","objects":[{"db":"test","name":"t2","obj_type":"TABLE"}],"query":"select * from t2 where name = \"cz\""}
```
2. socket文件
这种方式意味着我们可以编写一个socket监听程序(Server端), audit插件连接socket文件以client身份发送信息到程序端, 程序端可以按需处理。
如下所示:
![socket]({{ site.baseurl }}/images/articles/201411/audit-1.png)
