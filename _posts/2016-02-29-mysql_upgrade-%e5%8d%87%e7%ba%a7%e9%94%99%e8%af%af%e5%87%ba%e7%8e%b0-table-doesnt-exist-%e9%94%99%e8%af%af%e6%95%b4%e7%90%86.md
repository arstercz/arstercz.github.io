---
id: 626
title: 'mysql_upgrade 升级错误出现 table doesn&#8217;t exist 错误整理'
date: 2016-02-29T10:24:21+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=626
permalink: '/mysql_upgrade-%e5%8d%87%e7%ba%a7%e9%94%99%e8%af%af%e5%87%ba%e7%8e%b0-table-doesnt-exist-%e9%94%99%e8%af%af%e6%95%b4%e7%90%86/'
ultimate_sidebarlayout:
  - default
categories:
  - database
  - percona
tags:
  - mysql，table
  - upgrade
---
从 MySQL 官方的 5.1.48 版本升级到 Percona 5.1.73 版本, 在使用 `mysql_upgrade` 的时候出现一些错误, 该原因可能为innodb表文件丢失或损坏, 或使用了不正确的方式删除表. 错误信息如下所示:
```
[root@cz ~]# cd /opt/Percona-Server-5.1.73-rel14.12-624.Linux.x86_64/
[root@cz Percona-Server-5.1.73-rel14.12-624.Linux.x86_64]# ./bin/mysql_upgrade -S /export/mysql/node3307/data/s3307  -p --verbose
...
Repairing table

test.蔢^
Error    : Table 'test.蔢' doesn't exist
status   : Operation failed
test.蔢^
Error    : Table 'test.蔢' doesn't exist
status   : Operation failed
test.蔢^
Error    : Table 'test.蔢' doesn't exist
status   : Operation failed
```

系统的环境如下:
```
# Percona Toolkit System Summary Report ######################
        Date | 2016-02-29 02:04:05 UTC (local TZ: CST +0800)
    Hostname | cz
      Uptime | 3 days, 23:20,  1 user,  load average: 0.06, 0.03, 0.00
    Platform | Linux
     Release | CentOS release 6.4 (Final)
      Kernel | 2.6.32-573.18.1.el6.x86_64
Architecture | CPU = 64-bit, OS = 64-bit
   Threading | NPTL 2.12
     SELinux | Enforcing
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | physical = 2, cores = 8, virtual = 16, hyperthreading = yes
      Speeds | 16x2260.936
      Models | 16xIntel(R) Xeon(R) CPU E5520 @ 2.27GHz
      Caches | 16x8192 KB
```

上述相同的错误重复打印, 查看 5.1 版本的 mysql_upgrade 并没有忽略某表或跳过错误选项, 不像 5.5 版本可以指定 -s 选项只升级系统表; 查看[Percona Server 5.1.73](https://www.percona.com/downloads/Percona-Server-5.1/Percona-Server-5.1.73-rel14.12/source/Percona-Server-5.1.73-rel14.12.tar.gz) 版本的 `client/mysql_upgrade.c` 源文件, mysql_uprade 调用了 `mysqlcheck` 工具对库中的表进行检测升级: 

代码部分:
```
675 static int run_mysqlcheck_upgrade(void)
676 {
677   print_conn_args("mysqlcheck");
678   return run_tool(mysqlcheck_path,
679                   NULL, /* Send output from mysqlcheck directly to screen */
680                   "--no-defaults",
681                   ds_args.str,
682                   "--check-upgrade",
683                   "--all-databases",
684                   "--auto-repair",
685                   opt_write_binlog ? "--write-binlog" : "--skip-write-binlog",
686                   NULL);
687 }
```

从源文件 `client/mysqlcheck.c` 的 main 函数开始, 开启 `--auto-repair` 选项后, main 函数中的下面代码则尝试修复表, for 循环中每次处理一个表 :
```
879   if (opt_auto_repair)
880   {
881     uint i;
882 
883     if (!opt_silent && tables4repair.elements)
884       puts("\nRepairing tables");
885     what_to_do = DO_REPAIR;
886     for (i = 0; i < tables4repair.elements ; i++)
887     {
888       char *name= (char*) dynamic_array_ptr(&tables4repair, i);
889       handle_request_for_tables(name, fixed_name_length(name));
890     }
891   }
```

源文件开始出以 `DYNAMIC_ARRAY` 类型声明了 ` tables4repair` 变量 `DYNAMIC_ARRAY tables4repair`, 在 `include/my_sys.h` 源文件查看 `DYNAMIC_ARRAY` 的类型定义:
```
 347 typedef struct st_dynamic_array
 348 {
 349   uchar *buffer;
 350   ulong elements, max_element;
 351   ulong alloc_increment;
 352   uint size_of_element;
 353 } DYNAMIC_ARRAY;
```

继续查看 `handle_request_for_tables` 函数中, 其存在执行 print_result 函数;
```
716   if (mysql_real_query(sock, query, query_length))
717   {
718     sprintf(message, "when executing '%s TABLE ... %s'", op, options);
719     DBerror(sock, message);
720     return 1;
721   }
722   print_result();
723   my_free(query, MYF(0));
724   return 0;
725 }
```

在 `print_result` 函数中, 打印检查表的信息, main 函数中相关的 `what_to_do` 设置为 `REPAIR, tables4repair` 则由 `my_init_dynamic_array` 处理; 最开始问题描述中的 Error 信息即从此处而来:
```
739   for (i = 0; (row = mysql_fetch_row(res)); i++)
740   {
741     int changed = strcmp(prev, row[0]);
742     my_bool status = !strcmp(row[2], "status");
743 
......
771   /* add the last table to be repaired to the list */
772   if (found_error && opt_auto_repair && what_to_do != DO_REPAIR)
773     insert_dynamic(&tables4repair, (uchar*) prev);
774   mysql_free_result(res);
```


给 `client/mysqlcheck.c` 源文件增加一些调试语句, 看看为什么在重复输出信息:
```
--- ../source/Percona-Server-5.1.73-rel14.12/client/mysqlcheck.c	2014-07-28 16:57:52.000000000 +0800
+++ client/mysqlcheck.c	2016-02-26 23:22:05.956801022 +0800
@@ -712,10 +712,12 @@
     ptr= fix_table_name(ptr, tables);
     ptr= strxmov(ptr, " ", options, NullS);
     query_length= (uint) (ptr - query);
+    printf("XXXX ptr: %s query: %s\n", ptr, query);
   }
   if (mysql_real_query(sock, query, query_length))
   {
     sprintf(message, "when executing '%s TABLE ... %s'", op, options);
+    printf("XXXx message: %s\n", message);
     DBerror(sock, message);
     return 1;
   }
@@ -740,7 +742,7 @@
   {
     int changed = strcmp(prev, row[0]);
     my_bool status = !strcmp(row[2], "status");
-
+    printf("row[0]: %s, row[2]: %s, row[3]: %s, status: %d, changed: %d\n", row[0], row[2], row[3], status, changed);
     if (status)
     {
       /*
@@ -880,12 +882,15 @@
   {
     uint i;
 
+    printf("tables4repair array number: %lu\n", tables4repair.elements);
     if (!opt_silent && tables4repair.elements)
       puts("\nRepairing tables");
     what_to_do = DO_REPAIR;
     for (i = 0; i < tables4repair.elements ; i++)
     {
       char *name= (char*) dynamic_array_ptr(&tables4repair, i);
+      printf("XXXX i: %u\n", i);
+      printf("XXXX repair table name: %s\n", name);
       handle_request_for_tables(name, fixed_name_length(name));
     }
   }
```

重新编译后, 手动执行 `mysqlcheck` 程序, 很不幸 `tables4repair.elements` 的值特别大(68719476736), for 循环中基本等同于无限循环, 如下所示:
```
$ ./bin/mysqlcheck -S /export/mysql/node3307/data/s3307 --database test -p --check-upgrade --auto-repair
.....
XXXX ptr:  query: CHECK TABLE `users`  FOR UPGRADE
row[0]: test.users, row[2]: status, row[3]: OK, status: 1, changed: -116
test.users                                  OK
tables4repair array number: 68719476736         ################ 11位的 ulong 数

Repairing tables
XXXX i: 0
XXXX repair table name: <E8>u#<BE><F5>^?
XXXX ptr:  query: REPAIR TABLE `<E8>u#<BE><F5>^?` 
row[0]: test.<E8>u#<BE><F5>^?, row[2]: Error, row[3]: Table 'test.<E8>u#<BE><F5>^?' doesn't exist, status: 0, changed: -116
test.<E8>u#<BE><F5>^?
Error    : Table 'test.<E8>u#<BE><F5>^?' doesn't exist
row[0]: test.<E8>u#<BE><F5>^?, row[2]: status, row[3]: Operation failed, status: 1, changed: 0
status   : Operation failed
....
```

不清楚为何 `tables4repair` 经过 `my_init_dynamic_array` 处理后, `elemants` 的值会这么大, i 是一直自增的, 但是字符串 name 的值 `dynamic_array_ptr(&tables4repair, i)` 的结果(表名)却一直没变;
未找到 `my_init_dynamic_array` 函数的信息, 基于此问题, 我们可以在 `mysql_upgrade.c` 源文件中可以注释掉 `--auto-repair` 选项跳过上述的 REPAIR 处理, `mysqlcheck` 只做升级检查而不做自动修复, 如下:
```
--- ../source/Percona-Server-5.1.73-rel14.12/client/mysql_upgrade.c	2014-07-28 16:57:52.000000000 +0800
+++ client/mysql_upgrade.c	2016-02-26 23:56:53.994213592 +0800
@@ -681,7 +681,7 @@
                   ds_args.str,
                   "--check-upgrade",
                   "--all-databases",
-                  "--auto-repair",
+                  //"--auto-repair",
                   opt_write_binlog ? "--write-binlog" : "--skip-write-binlog",
                   NULL);
 }
```
最后的结果相当于5.5版本的 `-s` 选项, 仅修复系统表:
```
...
test.t1_bk_201101                         OK
test.t1_expired                           OK
test.t1_log                               OK
test.t1_status                            OK
Running 'mysql_fix_privilege_tables'...
OK
```