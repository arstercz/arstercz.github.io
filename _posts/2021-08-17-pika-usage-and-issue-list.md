---
layout: post
title: "pika 使用及问题汇总"
tags: [redis, pika]
comments: true
---

对于 redis 而言, 数据越多就意味着需要更多的内存, 不管是升级单实例的配置还是扩展其为集群方式, 成本都是我们需要考虑的因素. 实际上, 大多数的业务可能只是数据量大, 访问量反倒不高. 在这种场景下, [pika](https://github.com/OpenAtomFoundation/pika) 可以作为 redis 的一种有效补充. 

下述的问题列表则主要介绍在使用 pika 的过程中可能碰到的问题. 一些问题可能会随着 pika 的版本迭代而修复, 更多的可以关注 [pika-issue](https://github.com/OpenAtomFoundation/pika/issues) 列表来确定具体问题的解决方式.

## 问题列表

* [指令集不兼容](#指令集不兼容)
* [编译注意事项](#编译注意事项)
* [线上如何使用](#线上如何使用)
* [内存占用问题](#内存占用问题)
* [重写配置崩溃问题](#重写配置崩溃问题)
* [事务问题](#事务问题)
* [备份问题](#备份问题)
* [简单压测](#简单压测)
* [更多参考](#更多参考)

## 指令集不兼容

不同机器的指令集可能不兼容, 如下所示:

```
# /opt/pika-v3.4.0/bin/pika -c /opt/pika-v3.4.0/conf/pika.conf

Illegal instruction
```

同一类型的架构最好源码编译一次. 更多见 [issue-161](https://github.com/OpenAtomFoundation/pika/issues/161).


## 编译注意事项


依赖了不少 zstd, snappy, glog 等选项, gcc 至少需要 4.8.x 版本:

```
yum install gflags-devel snappy-devel glog-devel protobuf-devel zlib-devel lz4-devel libzstd-devel
yum install gcc gcc-c++

cd pika-source # 可以使用稳定版的分支, 具体见: https://github.com/OpenAtomFoundation/pika/wiki/%E5%AE%89%E8%A3%85%E4%BD%BF%E7%94%A8
make -j4
```

如果开启 tcmalloc 特性, 需要安装:

```
gperftools-devel gperftools-libs
```

不过 centos7 默认的 2.6 版本, 会出现 coredump 的问题, 如下所示:

```
# /opt/pika/bin/pika -c /opt/pika/conf/pika.conf
......

src/tcmalloc.cc:284] Attempt to free invalid pointer 0x2e3d5c0 

Aborted
```

需要使用更高版本的来编译, 不过从测试情况来看只能支持 2.7 版本. 2.9 版本可以编译, 但是无法使用 tcmalloc 内存分配. 更多见: [issue-908](https://github.com/OpenAtomFoundation/pika/issues/908).

#### tcmalloc 问题

编译 gperftools 的时候, 可以选择以下任意方式编译, 降低锁争用的开销:

```
1. 安装 libunwind 依赖;
2. configure 时指定 --enable-frame-pointers
```

更多见: [tcmalloc 解密](https://zhuanlan.zhihu.com/p/51432385).


## 线上如何使用

同类架构的机器编译一次即可, 其他机器可以直接部署编译后的包. 我们以 pika-v3.4.0 版本为基础, 合并了以下几个 bug:


[issue-988](https://github.com/OpenAtomFoundation/pika/pull/988)  
[issue-990](https://github.com/OpenAtomFoundation/pika/pull/990)  
[issue-1017](https://github.com/OpenAtomFoundation/pika/pull/1017)  
[issue-1041](https://github.com/OpenAtomFoundation/pika/pull/1041)  


**备注**: 目前[最新版-f1778bd](https://github.com/OpenAtomFoundation/pika/tree/master)已合并上述的补丁. 编译和部署的脚本及依赖的 rpm 文件均放到了 `tag v3.4.0-1` 下, 目前部署脚本仅支持 `Redhat/Centos 7` 系统.

#### 1. 如何编译

```
git clone --branch v3.4.0-1 https://github.com/arstercz/pika
cd pika
git submodule init
git submodule update

bash setup.sh R620    # 这里按主机架构具体的型号指定, 一些云厂商的没有硬件类型字段, 这里我们手动指定
......
generate pika-v3.4.0-R620.tar.gz ok.    # 生成对应的二进制包

```

#### 2. 其他同架构主机如何安装

```
tar xf pika-v3.4.0-R620.tar.gz -C /opt/
bash /opt/pika/utils/deploy.sh 9221 /data    # 9221 为端口号, 可以自定义修改, /data 为 base 目录, 按实际情况填写, 比如 /data, /web 等.
```

**备注:** deploy.sh 仅适用于 Redhat/Centos 7, Ubuntu/Debian 等系统需要安装对应的依赖包.

#### 3. pika 占用的端口
 
pika 实例在启动的时候默认占用三个端口, 比如以下:
```
9221   # 程序连接端口
10221  # rsync daemon 端口, 方便数据全量同步, 同时也进行文件的续传校验;
11221  # slave 连接的端口, 和程序连接的区别开;
```
 
默认情况下, 采用以下规则制定 rsync daemon 和 slave 连接的端口:

```
// include/pika_define.h
/* Port shift */
const int kPortShiftRSync      = 1000;
const int kPortShiftReplServer = 2000;
 
// src/pika_repl_client_thread.cc
  if (ip == g_pika_server->master_ip()
    && port == g_pika_server->master_port() + kPortShiftReplServer

// src/pika_server.cc
  pika_rsync_service_ = new PikaRsyncService(g_pika_conf->db_sync_path(),
                                             g_pika_conf->port() + kPortShiftRSync);
```
 
## 内存占用问题

rocksdb 本身没有内存上限的配置, 在实际的使用中可以参考 [issue-177](https://github.com/OpenAtomFoundation/pika/issues/177).


## 重写配置崩溃问题
 
执行 `config rewrite` 命令的时候, 出现了崩溃的现象, 从日志来看, 是因为 IO 权限不足引起:
```
May 19 12:41:14 db4 pika_debug[30972]: [INFO] (src/base_conf.cc:263) ret IO error: /opt/pika/conf/pika.conf.tmp: Permission denied
May 19 12:41:14 db4 kernel: CliProcessorPoo[31014]: segfault at 0 ip 00000000006e68b0 sp 00007f08ca005250 error 4 in pika_debug[400000+ab3000]
```
 
对应的, strace 可以看到以下信息:

```
[pid 72142] 18:34:07.788874 <... epoll_wait resumed>[{EPOLLIN, {u32=170, u64=172097587204063402}}], 10240, 3000) = 1
[pid 72142] 18:34:07.788964 read(170, "*2\r\n$6\r\nconfig\r\n$7\r\nrewrite\r\n", 16384) = 29
[pid 72142] 18:34:07.789099 futex(0x245a23c, FUTEX_CMP_REQUEUE_PRIVATE, 1, 2147483647, 0x245a210, 144) = 24
[pid 72142] 18:34:07.789240 epoll_ctl(7, EPOLL_CTL_MOD, 170, {0, {u32=170, u64=172097587204063402}} <unfinished ...>
[pid 72116] 18:34:07.789285 <... futex resumed>) = 0
[pid 72142] 18:34:07.789316 <... epoll_ctl resumed>) = 0
[pid 72116] 18:34:07.789348 futex(0x245a210, FUTEX_WAKE_PRIVATE, 1 <unfinished ...>
[pid 72142] 18:34:07.789382 epoll_wait(7,  <unfinished ...>
[pid 72116] 18:34:07.789416 <... futex resumed>) = 1
[pid 72115] 18:34:07.789458 <... futex resumed>) = 0
[pid 72115] 18:34:07.789570 futex(0x245a210, FUTEX_WAKE_PRIVATE, 1) = 1
[pid 72113] 18:34:07.789682 <... futex resumed>) = 0
[pid 72116] 18:34:07.789705 open("/opt/pika/conf/pika.conf.tmp", O_RDWR|O_CREAT|O_TRUNC|O_CLOEXEC, 0644 <unfinished ...>
[pid 72115] 18:34:07.789758 futex(0x245a23c, FUTEX_WAIT_PRIVATE, 145, NULL <unfinished ...>
[pid 72113] 18:34:07.789785 futex(0x245a210, FUTEX_WAKE_PRIVATE, 1 <unfinished ...>
[pid 72116] 18:34:07.789819 <... open resumed>) = -1 EACCES (Permission denied)
[pid 72113] 18:34:07.789861 <... futex resumed>) = 1
[pid 72112] 18:34:07.789884 <... futex resumed>) = 0
[pid 72116] 18:34:07.789934 --- SIGSEGV {si_signo=SIGSEGV, si_code=SEGV_MAPERR, si_addr=NULL} --
```

可以看到权限不足后, pika 即收到 SIGSEGV 信号进而崩溃. 需要赋予进程用户对 `/opt/pika/conf` 目录的写权限. 
 
## 事务问题

pika 不支持 lua 及事务相关的 `multi, exec, watch, unwatch` 命令. 如果业务一定要使用 lua 或事务, 就只能选择官方版 redis.

## 备份问题
 
目前 pika 通过快照方式(文件硬链接)备份, 不过备份目录的时间紧精确到天, 如下所示:

```
db0 after prepare bgsave
db0 bgsave_info: path=/export/pika/dump/20210529/db0,  filenum=813, offset=29855508
```
 
从代码来看, 命令仅精确到天, 每次 bgsave 的时候会先清理同名的文件, 再重新打快照:

```c
394 // Prepare engine, need bgsave_protector protect
395 bool Partition::InitBgsaveEnv() {
396   slash::MutexLock l(&bgsave_protector_);
397   // Prepare for bgsave dir
398   bgsave_info_.start_time = time(NULL);
399   char s_time[32];
400   int len = strftime(s_time, sizeof(s_time), "%Y%m%d%H%M%S", localtime(&bgsave_info_.start_time));
401   bgsave_info_.s_start_time.assign(s_time, len);
402   std::string time_sub_path = g_pika_conf->bgsave_prefix() + std::string(s_time, 8);     // 这里, 取时间的前 8 位, 对应到天
403   bgsave_info_.path = g_pika_conf->bgsave_path() + time_sub_path + "/" + bgsave_sub_path_;
404   if (!slash::DeleteDirIfExist(bgsave_info_.path)) {
405     LOG(WARNING) << partition_name_ << " remove exist bgsave dir failed";
406     return false;
407   }
......
```
 
猜测采用这种方式的原因可能是为了避免产生很多快照目录而导致磁盘不足. 实际使用中我们遵循此规则, 不做代码修改. 备份拷贝文件的时候, 如果一天要备份多次, 需要修改目的端的路径名. 同时线上也建议打开以下选项:

```
dump-prefix : pika9221_         # 快照目录前缀, 可以添加端口信息来标识. 最后生成类似如下目录: /export/pika/dump/pika9221_20210529
dump-expire : 7                 # 保留 7 天
dump-path : /export/pika/dump/
```

## 简单压测
 
构造 5 亿条(其中 1 亿条设置超时时间 86400)随机的 key(50bytes) - value(40 bytes) 对 pika 进行 set 压测:

```
# Keyspace
# Time:2021-05-14 10:03:12
# Duration: 512s
db0 Strings_keys=500000000, expires=100000000, invalid_keys=0
db0 Hashes_keys=0, expires=0, invalid_keys=0
db0 Lists_keys=0, expires=0, invalid_keys=0
db0 Zsets_keys=0, expires=0, invalid_keys=0
db0 Sets_keys=0, expires=0, invalid_keys=0
 
 
127.0.0.1:9221> tcmalloc stats
 1) "------------------------------------------------"
 2) "MALLOC:     1357838856 ( 1294.9 MiB) Bytes in use by application"
 3) "MALLOC: +    648765440 (  618.7 MiB) Bytes in page heap freelist"
 4) "MALLOC: +      2675784 (    2.6 MiB) Bytes in central cache freelist"
 5) "MALLOC: +      2631424 (    2.5 MiB) Bytes in transfer cache freelist"
 6) "MALLOC: +     23595696 (   22.5 MiB) Bytes in thread cache freelists"
 7) "MALLOC: +      3145728 (    3.0 MiB) Bytes in malloc metadata"
 8) "MALLOC:   ------------"
 9) "MALLOC: =   2038652928 ( 1944.2 MiB) Actual memory used (physical + swap)"
10) "MALLOC: +     40476672 (   38.6 MiB) Bytes released to OS (aka unmapped)"
11) "MALLOC:   ------------"
12) "MALLOC: =   2079129600 ( 1982.8 MiB) Virtual address space used"
13) "MALLOC:"
14) "MALLOC:           6903              Spans in use"
15) "MALLOC:             79              Thread heaps in use"
16) "MALLOC:           8192              Tcmalloc page size"
17) "------------------------------------------------"
18) "Call ReleaseFreeMemory() to release freelist memory to the OS (via madvise())."
19) "Bytes released to the"
```
 
压测期间, 整个 pika 实例的内存及 qps 情况, 整体上比较稳定, 内存使用的变化幅度也不大:
![pika_set_bench]({{ site.baseurl }}/images/articles/202108/pika_set_bench.png)
 
## 更多参考


| 说明 | 链接 |
| :-: | :-: |
| wiki 文档 | [wiki](https://github.com/OpenAtomFoundation/pika/wiki) |
| 配置说明 | [configure](https://github.com/OpenAtomFoundation/pika/wiki/pika-%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6%E8%AF%B4%E6%98%8E) |
| info 信息说明 | [info-message](https://github.com/OpenAtomFoundation/pika/wiki/pika-info%E4%BF%A1%E6%81%AF%E8%AF%B4%E6%98%8E) |
| 管理命令 | [admin-command](https://github.com/OpenAtomFoundation/pika/wiki/pika%E7%9A%84%E4%B8%80%E4%BA%9B%E7%AE%A1%E7%90%86%E5%91%BD%E4%BB%A4%E6%96%B9%E5%BC%8F%E8%AF%B4%E6%98%8E) |
| 兼容 redis 情况 | [redis-compatible](https://github.com/OpenAtomFoundation/pika/wiki/pika-%E6%94%AF%E6%8C%81%E7%9A%84redis%E6%8E%A5%E5%8F%A3%E5%8F%8A%E5%85%BC%E5%AE%B9%E6%83%85%E5%86%B5) |
| 最佳实践 | [best-practice](https://github.com/OpenAtomFoundation/pika/wiki/Pika-Best-Practice) |
