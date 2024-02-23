---
layout: post
title: "mysql 客户端访问崩溃排查"
tags: [mysql crash]
comments: true
---

## 错误说明

近期在测试 [shardingsphere-proxy](https://shardingsphere.apache.org/) 工具的时候, 接连碰到几例 mysql 客户端崩溃的情况, 各 mysql 客户端分布在不同主机, 以及不同版本上. 通过 gdb 直接跟踪可以看到如下错误所示:

```c
# 所有版本以 gdb 方式连接:
gdb -ex run -ex bt --args  mysql -h ... -p ...


# ubuntu 22.04  - mysql-5.7.44

Program received signal SIGSEGV, Segmentation fault.
__strlen_avx2 () at ../sysdeps/x86_64/multiarch/strlen-avx2.S:74
74      ../sysdeps/x86_64/multiarch/strlen-avx2.S: No such file or directory.
#0  __strlen_avx2 () at ../sysdeps/x86_64/multiarch/strlen-avx2.S:74
#1  0x0000555555595931 in my_strdup (key=0, from=0x0, my_flags=16)
    at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/mysys/my_malloc.c:320
#2  0x000055555558192f in init_username () at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/client/mysql.cc:5850
#3  init_username () at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/client/mysql.cc:5838
#4  0x000055555558b296 in construct_prompt () at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/client/mysql.cc:5741
#5  read_and_execute (interactive=<optimized out>) at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/client/mysql.cc:2282
#6  0x000055555557fd93 in main (argc=<optimized out>, argv=<optimized out>)
    at /mnt/jenkins/workspace/ps5.7-autobuild-RELEASE/test/percona-server-5.7-5.7.44-48/client/mysql.cc:1449


# centos 7 - mysql-5.7.28
Program received signal SIGSEGV, Segmentation fault.
0x00007ffff5fd98c1 in __strlen_sse2_pminub () from /lib64/libc.so.6
#0  0x00007ffff5fd98c1 in __strlen_sse2_pminub () from /lib64/libc.so.6
#1  0x000000000041cd6c in my_strdup (key=0, from=0x0, my_flags=16)
    at /mnt/workspace/percona-server-5.7-binaries-release-rocks-new/label_exp/min-centos-6-x64/test/percona-server-5.7.28-31/mysys/my_malloc.c:320
#2  0x0000000000408924 in init_username ()
    at /mnt/workspace/percona-server-5.7-binaries-release-rocks-new/label_exp/min-centos-6-x64/test/percona-server-5.7.28-31/client/mysql.cc:5846
#3  0x000000000040a515 in construct_prompt ()
    at /mnt/workspace/percona-server-5.7-binaries-release-rocks-new/label_exp/min-centos-6-x64/test/percona-server-5.7.28-31/client/mysql.cc:5736
#4  0x00000000004077ed in read_and_execute (interactive=true)
    at /mnt/workspace/percona-server-5.7-binaries-release-rocks-new/label_exp/min-centos-6-x64/test/percona-server-5.7.28-31/client/mysql.cc:2287
#5  main (argc=11, argv=0x9c2438)
```

## 处理分析

直接看 `my_malloc.c` 代码:
```c
317 char *my_strdup(PSI_memory_key key, const char *from, myf my_flags)
318 {
319   char *ptr;
320   size_t length= strlen(from)+1;
321   if ((ptr= (char*) my_malloc(key, length, my_flags)))
322     memcpy(ptr, from, length);
323   return ptr;
324 }
```

可以对比堆栈信息来看:
```
#1  0x000000000041cd6c in my_strdup (key=0, from=0x0, my_flags=16)
```

可以看到 my_strdup 函数的 from 参数为 NULL, 相应的函数 `strlen` 就是对空指针进行计算, 最终导致 mysql 客户端崩溃.

> 备注: 堆栈中的 `../sysdeps/x86_64/multiarch/strlen-avx2.S: No such file or directory.` 消息容易误导我们, 不同发行版和架构会有不同的提示. 我们可以在各主机下简单通过 c 的 strlen 函数进行验证, 如下代码:

```
#include <stdio.h>
#include <string.h>

int main()
{

  int length = strlen(NULL);
  printf("Length of string is : %d\n", length);

  return 0;
}
```
在 `ubuntu 22.04` 系统运行的时候出现了类似的崩溃信息:
```
Program received signal SIGSEGV, Segmentation fault.
__strlen_evex () at ../sysdeps/x86_64/multiarch/strlen-evex.S:77
77      ../sysdeps/x86_64/multiarch/strlen-evex.S: No such file or directory.
```

## 辅助分析

根据上述分析, 分别进行 mysql 通信时的抓包分析:
```
# mysql-sniffer -P 13099 -i eth0 -n -v
Initializing MySQL sniffing on eth0:3309...
2024/02/22 20:13:11.949926   10.10.0.3:35934:select @@version_comment limit 1 ## type: 3, bytes: 32, time: 0.00
2024/02/22 20:13:11.981929   10.10.0.3:35934:select USER() ## type: 3, bytes: 13, time: 0.00
```

tcpdump 抓包则未发现响应:
```
20:12:12.002638 IP 10.10.0.3.35738 > 10.10.0.46.3309: Flags [P.], seq 126:144, ack 205, win 229, length 18
E..:..@.9..B
...
.#...3+?.S..i..P............select USER()................
20:12:12.004388 IP 10.10.0.46.3309 > 10.10.0.3.35738: Flags [P.], seq 205:271, ack 144, win 229, length 66
E..j..@.@.$e
```

也就是 mysql 客户端在执行了 `select USER()` 语句后出现了崩溃的情况, 直接连接 `shardingsphere-proxy` 可以发现其直接返回了空数据:
```sql
mysql > select USER();
+--------+
| USER() |
+--------+
|        |
+--------+
1 row in set (0.09 sec)
```

> 这里的空不是空字符串

对应上述 `strlen` 函数的空指针.

## 如何处理

据此, 可以知晓有两种处理方式:

### shardingsphere-proxy 支持语法

可以反馈给官方支持此类 SQL 语法, 这样 mysql 不会出现空指针的情况. 但这种反馈修复的时间一般都很长, 不适合我们用户侧.

### mysql 客户端调整

另一种可以让 mysql 客户端不去执行不支持的语法, 如下所示, 之所以指定了 `select USER()`, 也是因为 my.cnf 里开启了 prompt 功能：
```
[mysql]
prompt = 'mysql \u@[\h:\p \d] > '
default-character-set = utf8mb4
```

这里的 `\u` 即让 mysql 在连接后执行了 `init_username(select USER())` 操作, 配置中去掉 `\u` 即可解决该问题:
```
# 见 src/client/mysql.cc

5658 static const char* construct_prompt()
5659 {
......
5734       case 'u':
5735         if (!full_username)
5736           init_username();
......
......
5833 static void init_username()
5834 {
5835   my_free(full_username);
5836   my_free(part_username);
5837 
5838   MYSQL_RES *result= NULL;
5839   if (!mysql_query(&mysql,"select USER()") &&
5840       (result=mysql_use_result(&mysql)))
```

## 总结

大部分 mysql 协议兼容的工具产品(比如 clickhouse, shardingsphere) 等都没有完全兼容 mysql 的语法, 在通过 mysql 客户端测试的时候也更容易出现一些兼容性的问题. 另外通过应用程序去测试即便不会出现文章中的此类问题, 但也需要对业务用到的 SQL 语法做更多的访问测试.
