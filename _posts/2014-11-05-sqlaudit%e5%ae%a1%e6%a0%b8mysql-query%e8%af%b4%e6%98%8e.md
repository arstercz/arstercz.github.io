---
id: 406
title: SQL::Audit审核MySQL query说明
date: 2014-11-05T17:22:57+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=406
permalink: '/sqlaudit%e5%ae%a1%e6%a0%b8mysql-query%e8%af%b4%e6%98%8e/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3459322550"
dsq_needs_sync:
  - "1"
categories:
  - database
  - monit
tags:
  - audit
  - sql
---
<strong>SQL 审核说明</strong>
<strong>1.概述</strong>

SQL::Audit模块审核是以MySQL audit插件为基础， 通过分析SQL记录的来源(audit.log或socket)和使用情况(存储引擎, 索引使用,字符集等)以期避免开发对生产环境主机的影响。 审核部分主要包括：操作日志记录、 统计分析、 SQL改写、 SQL索引分析、 SQL安全、 邮件发送。

见:
<a href="https://github.com/mcafee/mysql-audit"><font color="green">https://github.com/mcafee/mysql-audit</font></a>
<a href="https://github.com/arstercz/cz-sql-audit"><font color="green">https://github.com/arstercz/cz-sql-audit</font></a>

<strong>2.审核流程</strong>

sql_audit脚本读取audit插件的日志信息, 通过SQL::Audit完成检查和分析, 异常的信息通过邮件发送到开发组. 同类的sql在Memcached中缓存一天时间, 避免重复分析.
<!--more-->


<pre>
         +--------------------+
         |MySQL (audit plugin)| (1) audit插件生成audit.log日志.
         +--------------------+
                  |        
                  |        
          +---------------+
          | read audit.log| (2) 增量读取json格式的audit.log日志文件.
          +---------------+
                  |        
                  |        
          +---------------+
          |  Memcached    | (3) 缓存同类sql, 已分析过则跳过后续的模块分析.
          +---------------+
                  |        
                  |                            +--------------------+
                  |                          __| SQL::Audit::dbh    |   (4) 获取数据库句柄.
                  |                         /  +--------------------+
                  |                        /        
                  |                       /        
                  |      +------------+   |    +---------------------+
                  +-->   | SQL::Audit |   |----| SQL::Audit::Check   |  (5) 检查表的通用信息,不安全函数和不确定语句,归类sql.
                         +------------+   |    +---------------------+
                                          |        
                                          |    +---------------------+
                                          |----| SQL::Audit::Rewrite |  (6) 改写SQL为SELECT语句.
                                          |    +---------------------+
                                          |        
                                          |    +---------------------+
                                          |----| SQL::Audit::Explain |  (7) 获取Explain SELECT....信息, 得到索引使用情况.
                                          |    +---------------------+
                                          |        
                                          |    +-------------------------+
                                          |----| SQL::Audit::Log::Record | (8) 记录上述模块分析的结果信息.
                                          |    +-------------------------+
                                          |        
                                          |    +-------------------------+
                                          |----| SQL::Audit::Email::Send | (9) 邮件发送分析的结果.
                                               +-------------------------+
</pre>

<strong>3.模块说明</strong>

<strong>1. File::Tail</strong>

该模块以行为单位增量读取指定文件的内容, 文件被移动或重新生成, 则该模块重新获取指定文件的句柄信息. 重新调整为每10s检测一次, 如果日志更新很频繁可能会引起该模块意外中断. 如果脚本通过socket接收audit插件生成的日志信息, 则不需要该模块。

<a href="http://search.cpan.org/~mgrabnar/File-Tail-0.99.3/Tail.pm"><font color="green">http://search.cpan.org/~mgrabnar/File-Tail-0.99.3/Tail.pm</font></a>

<strong>2. SQL::Audit</strong>

封装了子模块信息, 简化用户调用模块的接口。

<strong>3. SQL::dbh</strong>

用于获取指定database的句柄, SQL审计以audit用户重放所有库的sql查询, 所以数据库句柄的用户信息是固定的, database相关的句柄是可变的。

<strong>4. SQL::Audit::Check</strong>

Check模块完成以下功能:
1. 检查指定表的可用性, sql审核用户的权限;
2. table status和engine检查;
3. query中不安全函数和不确定结果集检测;
4. query过滤条件中使用了函数进行检测;
5. 表字符集和存储引擎检测;

<strong>5. SQL::Audit::Rewrite</strong>

Rewrite模块完成以下功能
1. 转换update, delete, insert语句为select语句;
2. 去除sql语句中的评注信息;
3. 略写in列表中的元素信息;
4. 过于复杂的sql语句截取select或join相关的信息, 也可能出现转换失败的情况;
5. 增加query_statistic方法进行统计分析, 避免重复的审核同类的sql;

<strong>6. SQL::Audit::Explain</strong>

Explain模块完成以下功能:

1. query增加EXPLAIN头信息, 返回explain的结果;
2. 正规化explain结果, 处理多值信息或空信息;
3. 生成索引使用的简易报告;
4. 分析索引使用的type, join类型等, 是否使用filesort, temporary等;

<strong>7. SQL::Audit::Log::Record</strong>

Record模块完成以下功能:
1. 封装Log::Dispatch模块;
2. 格式化输出信息,增加时间戳和level级别信息;
3. 提供不同的leve 输出函数;

<strong>8. SQL::Audit::Email::Send</strong>

Send模块完成以下功能:
1. 调用系统mail命令作为发件人发送邮件;
2. 连接指定的邮箱账户作为发件人发送邮件;
3. 不支持附件;

<strong>4.MySQL audit插件安装说明</strong>

见: <a href="http://highdb.com/mysql-audit%e5%ae%a1%e8%ae%a1%e6%8f%92%e4%bb%b6/"><font color="green">http://highdb.com/mysql-audit%e5%ae%a1%e8%ae%a1%e6%8f%92%e4%bb%b6/</font></a>

<strong>5.SQL::Audit安装说明</strong>

<pre>
   git clone https://github.com/arstercz/cz-sql-audit.git

   perl Makefile.PL
   make
   make test
   make install
</pre>

详细信息见:
perldoc SQL::Audit
perldoc SQL::Audit::dbh
perldoc SQL::Audit::Rewrite
perldoc SQL::Audit::Explain
perldoc SQL::Audit::Check
perldoc SQL::Audit::Log::Record
perldoc SQL::Audit::Email::Send

<strong>6.模块依赖</strong>

SQL::Audit 依赖的模块包括:

perl-DBI
perl-DBD::mysql
perl-Log-Dispatch
perl-Authen-SASL (如果指定了邮箱账户发送邮件)


审核脚本依赖模块包括:

perl-File-Tail
perl-JSON-XS
perl-Cache-Memcached
perl-MD5

<strong>7.示例说明</strong>
进入cz-sql-audit/examples目录, 执行审核脚本:
<pre>
perl sql_log_audit.pl --verbose --host=127.0.0.1 --user=audit --port=3306 --password=xxxxxxxx --memhost=127.0.0.1 --memport=11211 --mail=mail.cnf
</pre>
--user指定的用户名应该是mysql-audit插件的白名单用户, 以避免File::Tail模块重复的读取相同sql的日志信息.
--mail指定的文件内容为收件人,如下格式:
<pre>
recv = arstercz@gmail.com, ......
</pre>
多个收件人以逗号(,)分隔; 如果以系统的mail命令发送邮件, Centos 5中的mail命令不支持 -r 选项可能会引起邮件发送异常.

接收邮件信息如下:
<pre>
+-- Date: 2014-11-05T16:34:43
+-- Thread: 239191
+-- Client: 127.0.0.1, Server: localhost
+-- Database: test, Table: test
+-- Query: select * from test where op = 1 and type = 1 order by show_rank
+-- error index: ALL
+-- error index: Using_filesort
</pre>
Date: sql执行时的时间, 即记录到audit.log文件的时间;
Thread: 运行该sql的线程id, 后期版本可以通过thread信息验证事务是否正常使用(执行时间过长或没有commit提交);
Client: 哪台机器连接的Server端;
Server: MySQL实例所在的主机;
Database： sql执行连接的database信息;
Table:  sql执行操作的表的信息;
Query: Client端执行的sql语句, 不显示Rewrite之后的语句;
Conver to: 如果是更新的语句, 会被Rewrite模块改写为SELECT语句,比如:
<pre>
+-- Query: update site set time = '2014-10-22 17:00:00' where id = 1
+-- convert to: SELECT  time FROM site WHERE  id = 1
</pre>
error index: ALL: 表示没有使用索引, 为全表扫描; Using_filesort: 表示用到了文件排序; Using_temporary: 表示用到了临时表.