---
layout: post
title: "TokuDB 内存占用过高问题处理"
tags: [tokudb, mysql]
comments: false
---

## 问题说明

近期参考了 [xelabs-tokudb-wiki](https://github.com/xelabs/tokudb/wiki) 将 TokuDB 引擎和 jemalloc 内置到 MySQL 中, 在实际的使用中发现 MySQL 的实例占用的内存特别高, 如下所示的配置:
```
Centos 7 - 3.10.0-862.14.4.el7.x86_64
percona-server-5.6.45-86.1

my.cnf 配置:
   innodb_buffer_size = 16G
   tokudb_cache_size  = 48G
``` 

由于内置了 TokuDB 和 jemalloc, 所以运行数据库的系统未安装 jemalloc. 在使用的过程中内存占用很高, 如下所示:
```
   PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND                 
 21500 mysql     20   0 141.3g 104.7g   7600 S  24.8 23.9 595:38.31 mysqld
```

几台实例都出现此类情况, 总的内存接近 `innodb_buffer_size + 2 * tokudb_cache_size`, 正常的情况应该在 `innodb_buffer_size + tokudb_cache_size` 上下浮动. 

*备注:* 几台实例均为 slave, 处于空闲状态. 并未做 `load data` 等批量更新之类的操作.

## 分析处理

最开始我们以为 jemalloc 存在 [bug-1128](https://github.com/jemalloc/jemalloc/issues/1128) 而引起此类问题, 所以将内置的 jemalloc 变更为以下版本, 在系统为安装 `jemalloc-3.6.0-1.el7.x86_64` 的情况下依旧出现内存高的问题, 如下所示:
```
jemalloc-3.6.0
jemalloc-4.2.1
jemalloc-5.2.1
```

参考以下链接, 可以看到 tokudb 占用内存高的问题反馈已经很多, 不过都没有明确的处理:

[jira-mariadb-13403](https://jira.mariadb.org/browse/MDEV-13403)  
[jire-mariadb-13785](https://jira.mariadb.org/browse/MDEV-13785)  
[jire-percona-3366](https://jira.percona.com/browse/PS-3366)  

在实际的测试中, 仅发现以下方式可以解决内存高的问题, 更多见 [solved-high-mem](https://jira.mariadb.org/browse/MDEV-16838?focusedCommentId=114869&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-114869)
```
We solved the issue by adding this to our cnf file:

[mysqld_safe]
malloc-lib= /path/to/jemalloc

We compiled MariaDB from source, with non-standard configuration files. The problem might have been self inflicted.
```

在 `mysqld_safe` 的代码中, 存在默认加载 `libjemalloc` 的行为, 所以对上述的配置而言, 只要系统安装了 jemalloc, 是否指定 `malloc-lib` 选项, 都不会有什么区别, 如下所示:

```bash
/opt/percona-server-5.6.45-86.1-linux-x86_64/bin/mysqld_safe

...
load_jemalloc=1
...

      --malloc-lib=*)
        set_malloc_lib "$val"
        load_jemalloc=0
        ;;
...
if test $load_jemalloc -eq 1
then
  for libjemall in "${MY_BASEDIR_VERSION}/lib/mysql" "/usr/lib64" "/usr/lib/x86_64-linux-gnu" "/usr/lib"; do
    if [ -r "$libjemall/libjemalloc.so.1" ]; then
      add_mysqld_ld_preload "$libjemall/libjemalloc.so.1"
      break
    fi  
  done
fi
```

Centos 7 中, 如果安装了 `jemalloc-3.6.0-1.el7.x86_64` 的 rpm 包, 默认会以 `/usr/lib64/libjemalloc.so.1` 文件设置 `LD_PRELOAD`, mysqld 进程启动的时候会预加载此文件, 以 jemalloc 来管理运行时需要的内存分配. 

我们通过 [valgrind-mysql](https://www.percona.com/blog/2013/01/09/profiling-mysql-memory-usage-with-valgrind-massif/) 来分析是否预加载 `/usr/lib64/libjemalloc.so.1` 的行为, 不过遗憾的是, 两种方式并未看到异常, 整体的内存分布大致如下
```c
99.87% (7,309,226,237B) (heap allocation functions) malloc/new/new[], --alloc-fns, etc.
->73.33% (5,367,098,317B) 0xF7F9E8: os_malloc_aligned(unsigned long, unsigned long) (os_malloc.cc:222)
| ->73.33% (5,367,098,317B) 0xF7F4AE: toku_xmalloc_aligned(unsigned long, unsigned long) (memory.cc:402)
...
->18.56% (1,358,583,896B) 0xB59197: pfs_malloc(unsigned long, int) (pfs_global.cc:57)
| ->16.94% (1,239,646,296B) 0xB59366: pfs_malloc_array(unsigned long, unsigned long, int) (pfs_global.cc:144)
| | ->04.60% (336,370,400B) 0xB5ABC2: init_instruments(PFS_global_param const*) (pfs_instr.cc:407)
```

*备注:* 分析内存的时候, 需要使用 valgrind 启动 mysqld 的 debug 版本.

#### 其它可能的问题

参考 [comment-mariadb](https://jira.mariadb.org/browse/MDEV-13403?focusedCommentId=105780&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-105780), 其中提到:
```
I finally discovered that my memory problem was caused by innodb not using large pages and there was 
no memory leak in my case, we are not using TokuDb neither. Problem was happening because in huge pages 
configuration I was including the one that were supposed to be used by Innodb but since there were not , 
but still were reserved, when innodb needed memory it was allocated from remaining memory of the system 
so appearing as leaking ... I reconfigured huge pages minus pages needed by innodb and memory usage went 
down immediately.
```

这个评论指出了内存高可能是由于 innodb 和关闭 `huge page` 的原因引起的. 这点在实际的使用中我们还没有碰到过. 毕竟很多公司的实例都是 `TokuDB + InnoDB` 混合使用的, 如果存在这个问题, 官方就会有大量的反馈上报. 另外我们进行以下测试也验证了上述原因是错误的:
```
1. 仅存在 InnoDB 表, 关闭 huge page. 未出现内存过高的情况;
2. 仅存在 TokuDB 表, 不安装 jemalloc-3.6.0-1.el7.x86_64, 出现内存过高的情况;
```

## 处理说明

从 mariadb 的 jira 来看, 各发行版本, Centos, Ubuntu, Debian 等都出现此类问题, 还没有发现该问题的根本原因. 在已知的文档和测试中, 只有 mysqld 预加载 libjemalloc 才能避免此类问题. 可以使用以下方式安装:
```
yum install jemalloc      # centos/redhat

apt install libjemalloc1  # ubuntu/debian
```

`percona mysql 5.6/5.7` 版本中, `mysqld_safe` 启动脚本默认会加载 `libjemalloc.so.1` 文件, 此类方式可以直接启动 mysqld 进行以避免内存高的问题. 其它版本可以在配置中直接指定参数进行设置:
```
[mysqld_safe]
malloc-lib= /path/libjemalloc
```

另外, 如果对内置的 TokuDB 和 jemalloc 方式存在疑虑, 可以参考 [percona-tokudb-install](https://www.percona.com/doc/percona-server/LATEST/tokudb/tokudb_installation.html) 以插件的方式安装 TokuDB 引擎,  这种方式就必须依赖系统安装的 jemalloc, 等同上面的处理方式, 这种方式在实际的使用中还没有出现内存过高的问题. 如下所示, 可以通过 lsof 命令查看是否生效:

```
# lsof /usr/lib64/libjemalloc.so.1 
COMMAND   PID  USER  FD   TYPE DEVICE SIZE/OFF    NODE NAME
mysqld  57639 mysql mem    REG    8,1   212096 1427805 /usr/lib64/libjemalloc.so.1
```

