---
layout: post
title: "MySQL 及 jdbc 问题汇总"
tags: [mysql, charset, procedure]
comments: false
---

## 问题列表

* [存储过程与编码](#存储过程与编码)
* [jdbc 直接执行 sql](#jdbc-直连执行-sql)
* [jdbc useSSL 参数变更](#jdbc-useSSL-参数变更)
* [jdbc 通信异常](#jdbc-通信异常)  
* [MySQL 命令无法输入中文问题处理](MySQL-命令无法输入中文问题处理)  
* [MySQL 启动很慢](MySQL-启动很慢)  

### 存储过程与编码

MySQL 存储过程中, 表和数据的编码与数据库和存储过程默认的编码不同则可能出现 sql 不会使用索引的情况, 因为 MySQL 会对条件列的数据做相应的编码转换, 比如以下, 表数据为 `latin1`, MySQL 解析器会做一些转换:
```sql
... WHERE namecolumn =  NAME_CONST('in_namecolumn',_utf8'MP201022' COLLATE 'utf8_general_ci')
```

可以在存储过程中进行相应的编码转换(通常修改 `varchar/char` 字段)使得可以正常使用索引, 更多见: [mysql-slow-when-run-as-stored-proc](https://stackoverflow.com/questions/7873965/mysql-queries-are-fast-when-run-directly-but-really-slow-when-run-as-stored-proc/21687188#21687188)
```sql
... WHERE namecolumn = convert(in_namecolumn using latin1) collate latin1_swedish_ci
```

### jdbc 直连执行 sql

通过 jdbc 连接执行 sql 的时候, 如果编码不一致, 同样需要对 `varchar, char` 类型进行转换, 如下所示:
```
... WHERE namecolumn = convert(in_namecolumn using latin1) collate latin1_swedish_ci
```
否则可能出现以下编码不一致的错误(随 mysql-connector 版本不同可能有不同的行为):
```
SQL state [HY000]: error code [1267]: Illegal mix of collations (latin1_swedish_ci,IMPLICIT) and (utf8mb4_general_ci,COERCIBLE) for operation '='
```

### jdbc useSSL 参数变更

在 `mysql-connector-java` 配置中, `useSSL` 参数有以下不同, 从 `5.1.38` 开始 `useSSL` 开始按 `MySQL 5.5.45+, 5.6.26+ or 5.7.6+` 的版本默认开启, 对应的 requireSSL, verifyServerCertificate 两个参数也会跟着开启:

```
< 5.1.38:
  ConnectionProperties.useSSL=Use SSL when communicating with the server (true/false), defaults to 'false'

>= 5.1.38
  ConnectionProperties.useSSL=Use SSL when communicating with the server (true/false), default is 'true' when connecting to MySQL 5.5.45+, 5.6.26+ or 5.7.6+, otherwise default is 'false'
```

`MySQL 5.7.x` 及以上的版本, 默认会启用 `ssl`, 客户端连接的时候会自协商加密, 除非显示指定不加密. `mysql-connector-java` 从 `5.1.38` 开始默认开启 useSSL. 所以用低版本 jdbc 连接 `MySQL 5.7.x` 不会有加密的问题, 用高版本 jdbc 连接 5.7.6+ 以上会有加密问题, 需要显示指定 `useSSL=false`, 用高版本的 `jdbc` 连接 `MySQL 5.5, 5.6` 不会有加密问题.

### jdbc 通信异常

由于 mysql 连接 `wait_timeout` 等参数的设定, 实践中我们通常都不会将其设置的很大, 以避免吃满 db 的连接. 低版本的 `mysql-connector-j` 可能出现一下错误:
```
Caused by: com.mysql.jdbc.exceptions.jdbc4.CommunicationsException: The last packet successfully received from the server was 39,579,221 milliseconds ago.  The last packet sent successfully to the server was 39,579,221 milliseconds ago. is longer than the server configured value of 'wait_timeout'. You should consider either expiring and/or testing connection validity before use in your application, increasing the server configured values for client timeouts, or using the Connector/J connection property 'autoReconnect=true' to avoid this problem.
```

程序应该开启 `autoReconnect` 选项, 如果开启了还出现上述的错误, 需要升级 `mysql-connector-j` 至少到 `5.1.45` 版本, 低版本存在通信上的问题, 更多见 [bug-88242](https://bugs.mysql.com/bug.php?id=88242), 官方 changelog 中亦有提示:

```
Version 5.1.45
.....
  - Fix for Bug#88242 (27040063), autoReconnect and socketTimeout JDBC option makes wrong order of client packet.
```

### MySQL 命令无法输入中文问题处理

见 [MySQL 命令无法输入中文问题处理]({{ site.baseurl }}/mysql-can-not-input-chinese/).

### MySQL 启动很慢

见 [为什么 Percona MySQL 开启 NUMA 选项后启动很慢]({{ site.baseurl }}/percona-mysql-start-slowly/).


