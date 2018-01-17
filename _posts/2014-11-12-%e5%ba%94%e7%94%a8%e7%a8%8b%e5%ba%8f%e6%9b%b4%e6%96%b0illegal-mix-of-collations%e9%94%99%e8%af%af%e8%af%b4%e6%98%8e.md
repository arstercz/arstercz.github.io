---
id: 423
title: 应用程序更新Illegal mix of collations错误说明
date: 2014-11-12T18:39:57+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=423
permalink: '/%e5%ba%94%e7%94%a8%e7%a8%8b%e5%ba%8f%e6%9b%b4%e6%96%b0illegal-mix-of-collations%e9%94%99%e8%af%af%e8%af%b4%e6%98%8e/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3459240476"
categories:
  - database
tags:
  - MySQL
---
完整错误信息如:
<pre>
Illegal mix of collations (latin1_swedish_ci,IMPLICIT) and (gbk_chinese_ci,IMPLICIT) for operation '=' (1267)
INSERT INTO .... name = value ...
</pre>

错误信息描述了操作符 = 两边的数据编码不一致而引起的冲突, 常见的原因有表的字符集可能为latin1, 而应用程序等的字符集为gbk, 当然基于这样的原因，应用程序等select出来的结果集也可能为乱码状态. 确保应用和DB端的编码统一是很重要的事情, 尤其是一些开发者初期不注意编码和排序规则, 后期扩展则出现各种掣肘的问题, 比如Server端的character_%编码和表的编码不一致, 使用Server端的变量创建的表相关的trigger或procedure在更新的时候也可能碰到这类问题.
<!--more-->

出现这类问题的本质原因在于字符编码的不统一: Server变量, table 和 应用程序之间的编码不统一, 这种问题可能会给一些高可用或扩展工具带来不必要的错误, 比如更改表结构或做了主从切换, 还需要做编码相关的测试, 如果有乱码是改回去还是继续修改应用. 确保编码的统一需要注意一下几个因素:
1. Server变量设置:
<pre>
+--------------------------+---------------------------------------------------------------------+
| Variable_name            | Value                                                               |
+--------------------------+---------------------------------------------------------------------+
| character_set_client     | utf8                                                                |
| character_set_connection | utf8                                                                |
| character_set_database   | utf8                                                                |
| character_set_results    | utf8                                                                |
| character_set_server     | utf8                                                                |
| character_set_system     | utf8                                                                |
+--------------------------+---------------------------------------------------------------------+
</pre>

2. 表编码设置:
如:
<pre>
 ENGINE=InnoDB DEFAULT CHARSET=utf8
</pre>
如果不指定编码, 则继承Server变量的设置;详见: <a href="http://dev.mysql.com/doc/refman/5.6/en/adding-character-set.html">http://dev.mysql.com/doc/refman/5.6/en/adding-character-set.html</a>

3. 字段编码设置:
可以设置为相关的编码, 比如表为utf8, 字段编码可以设置为相关的utf8mb4或无关的binary, latin等, 出现中文需要特别注意编码问题.如果没有设置,则继承表编码的设置.

4. 应用端编码设置：
可以在应用配置中指定连接的编码, 或者在应用连接DB后执行set names ... 相关的会话选项设置.