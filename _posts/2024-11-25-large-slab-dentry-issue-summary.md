---
layout: post
title: "slab dentry 缓存过多问题汇总"
tags: [dentry]
comments: true
---

在早期的文章 [Slab dentry 过高引起系统卡顿]({{ site.baseurl }}/centos-%e7%b3%bb%e7%bb%9f-slab-dentry-%e8%bf%87%e9%ab%98%e5%bc%95%e8%b5%b7%e7%b3%bb%e7%bb%9f%e5%8d%a1%e9%a1%bf%e5%88%86%e6%9e%90%e5%a4%84%e7%90%86/), 笔者分析了一个系统卡顿的案例. 本文则对 slab dentry 做一些延伸, 汇总一下 dentry 过多的问题.


## 为什么会有 dentry

参考文章 [Dentry negativity](https://lwn.net/Articles/814535/), 在 linux 内核中, dentry 是一个目录项(directory entry)的内存表示形式, 可以将 dentry 理解为一个路径的特定对象. 比如 `/bin/vi` 这个路径, 就包括 3 个目录项 `/, bin 和 vi`, 而目录项的主要作用就是加快文件和目录的解析查找. 比如下面的示例:

```bash
$ strace -eopenat /usr/bin/echo 'Subscribe to LWN'
On your editor's system, the output looks like:

openat(AT_FDCWD, "/lib64/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD, "/usr/lib/locale/locale-archive", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/usr/share/locale/locale.alias", O_RDONLY|O_CLOEXEC) = 3
[...]
```

如果没有 dentry, 这些路径都需要去遍历 VFS 查找, 效率上会大打折扣. 有了 dentry, 内核可以将其缓存起来供应用程序直接使用. 

## dentry 的结构

```c
# linux/dcache.h
struct dentry {
        atomic_t                 d_count;      /* usage count */
        unsigned long            d_vfs_flags;  /* dentry cache flags */
        spinlock_t               d_lock;       /* per-dentry lock */
        struct inode             *d_inode;     /* associated inode */
        struct list_head         d_lru;        /* unused list */
        struct list_head         d_child;      /* list of dentries within */
        struct list_head         d_subdirs;    /* subdirectories */
        struct list_head         d_alias;      /* list of alias inodes */
        unsigned long            d_time;       /* revalidate time */
        struct dentry_operations *d_op;        /* dentry operations table */
        struct super_block       *d_sb;        /* superblock of file */
        unsigned int             d_flags;      /* dentry flags */
        int                      d_mounted;    /* is this a mount point? */
        void                     *d_fsdata;    /* filesystem-specific data */
        struct rcu_head          d_rcu;        /* RCU locking */
        struct dcookie_struct    *d_cookie;    /* cookie */
        struct dentry            *d_parent;    /* dentry object of parent */
        struct qstr              d_name;       /* dentry name */
        struct hlist_node        d_hash;       /* list of hash table entries */
        struct hlist_head        *d_bucket;    /* hash bucket */
        unsigned char            d_iname[DNAME_INLINE_LEN_MIN]; /* short name */
};
```

## dentry 的三种状态

dentry 一共存在三种状态:

### used

使用状态: 表示一个有效的 inode(d_inode 指向有效的 inode), 说明当前的对象是有效的, 正在被 VFS 引用(等同 d_count > 0). 

### unused

未使用状态: 表示一个有效的 inode(d_inode 指向有效的 inode), 但是 VFS 没有引用(等同 d_count 为 0). 这种状态也表示内核还没有销毁这些对象, 后续有文件需要访问的时候, dentry 可以直接复用, 免去了重新创建 dentry 对象的开销. 

### negative

失效状态: 表示了一个无效的 inode(d_inode 为 NULL), 一般文件被删除, 或者路径名无效的时候, 即为无效的状态.

> 说明: 如果需要清理系统缓存(drop cache), 其中的 `unused 和 negative` 都可以被清理.

## 查看当前系统 dentry 的使用情况


### dentry 状态的结构体说明

```c
struct dentry_stat_t dentry_stat {
    int nr_dentry;
    int nr_unused;
    int age_limit;         /* age in seconds */
    int want_pages;        /* pages requested by system */
    int nr_negative;       /* # of unused negative dentries */
    int dummy;             /* Reserved for future use */
};
```

不同字段含义如下:
```
nr_dentry: shows the total number of dentries allocated (active + unused). 

nr_unused: shows the number of dentries that are not actively used, but are 
           saved in the LRU list for future reuse.

age_limit: is the age in seconds after which dcache entries can be reclaimed 
           when memory is short.

want_pages: is nonzero when shrink_dcache_pages() has been called and the dcache
            isn't pruned yet.

nr_negative: shows the number of unused dentries that are also negative dentries 
             which do not map to any files. Instead, they help speeding up 
             rejection of non-existing files provided by the users.
```
> 更多参考: [dentry-state](https://www.kernel.org/doc/html/v6.6/admin-guide/sysctl/fs.html#dentry-state)  

### 查看 dentry 状态

如下所示:
```
# cat /proc/sys/fs/dentry-state 
239587546       239475968       45      0       187333985       0

或

# sysctl fs.dentry-state
fs.dentry-state = 239587546       239475968       45      0       187333985       0
```

参考 dentry 的结构体, 可以获取以下信息:
```
used:      239587546
unused:    239475968
negative:  187333985
age_limit: 45           # centos 7 中, 内核代码写死 45
```

相应的, 该主机中 slab 的信息如下, 当然也能看到这里的 SIZE 接近(80G):
```
  OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME                   
427924728 239610443  55%    0.19K 10188684       42  81509472K dentry
```

### 计算 dentry 的状态

从上述 dentry 状态可以大致得出三种状态的关系:

```
分配 dentry 的数量:   239587546(active + unused)
使用 dentry 的数量:   111578(239587546 - 239475968)
未使用 dentry 的数量: 239475968
失效 dentry 的数量:   187333985
总 dentry 数量:       426921531(active + unused + negative)
```

## 为什么 dentry 条目很多

了解到上述 dentry 的关系后, 再来看看为什么 dentry 条目很多?

本质上来看, dentry 越多则意味着系统访问的 socket, 目录, 以及文件越多. 可以预见到以下场景的机器的 dentry 都会挺高:
```
1. 应用程序的连接很多/线程很多;
2. 文件服务器, 尤其小文件很多的服务器;
3. 异常的服务 - 比如之前文章中的 curl 请求诱发的 dentry 过多;
```

### 检查什么原因引起的 dentry 过多？

现有的两种方式可以帮助查看系统中是什么程序不停地再诱发  dentry 的创建.

#### systemtap 跟踪

老系统(centos 6/7) 可以通过 systemtap 工具来跟踪 dentry 的创建情况(开销可能很大, 线上环境适当执行). 可以参考笔者以前的文章 [linux-systemtap-toolkit]({{ site.baseurl }}/intro-to-systemtap-toolkit/) 部署 systemtap 环境. 通过 systemtap 跟踪 dentry 创建/销毁的两个探测点即可获取实际的 dentry 活动信息:

```bash
probe kernel.function("dentry_lru_add")
{
    printf("dentry add - [%s] tid: %d, pid: %d, program: %s, path: /%s\n", 
        tz_ctime(gettimeofday_s()), tid(), pid(), execname(), 
        reverse_path_walk($dentry))
}

probe kernel.function("dentry_lru_del")
{
    printf("dentry del - [%s] tid: %d, pid: %d, program: %s, path: /%s\n", 
        tz_ctime(gettimeofday_s()), tid(), pid(), execname(), 
        reverse_path_walk($dentry))
}
```

如下所示:
```
dentry del - [Wed Nov 20 17:24:34 2024 CST] tid: 1, pid: 1, program: systemd, path: /34945/fd/7
dentry del - [Wed Nov 20 17:24:34 2024 CST] tid: 34968, pid: 34968, program: gluster, path: /fs/selinux
dentry add - [Wed Nov 20 17:24:34 2024 CST] tid: 34968, pid: 34968, program: gluster, path: /lib64
dentry add - [Wed Nov 20 17:24:34 2024 CST] tid: 34968, pid: 34968, program: gluster, path: /usr/lib64/libpcre.so.1
```

#### eBPF 跟踪

较新的系统支持 eBPF 特性(比如 ubuntu 18/20), 可以通过 bpftrace 工具跟踪, 比如以下简单的 bt 示例:

```c
#ifndef BPFTRACE_HAVE_BTF
#include <linux/path.h>
#include <linux/dcache.h>
#endif

kprobe:vfs_open
{
  printf("open path: %s, pid: %d, program: %s\n", str(((struct path *)arg0)->dentry->d_name.name), pid, comm);
}
```

如下所示:
```
# bpftrace dentry.bt
......
open path: cgroup.procs, pid: 90562, program: systemd-udevd
open path: cgroup.threads, pid: 90562, program: systemd-udevd
open path: stat, pid: 90619, program: telegraf
```

## dentry 条目多会引起哪些问题

> 参考 [redhat-solution-4982351](https://access.redhat.com/solutions/4982351)  

dentry 过多, 内核需要更多的内存以及哈希数组(`dentry_hashtable`)来存储这些条目, 最直观的感受是系统的 `buffer/cache` 可能很大. 另外也可能会引起以下问题:
```
1. Temporary unresponsiveness of container runtime.

2. Performance issues of processes, commands and/or systemcalls 
   working with files or directories.

3. Slowness or even softlockups during unmount, reclaim and/or 
   lookup routines.

4. Large negative dentries can cause system unresponsiveness 
   during systemd reloads

5. Use of the curl command in OpenShift liveness and/or readiness 
   probes bloats the dentry cache.

6. Need guidance to set the negative-dentry-limit kernel parameter.
```

> 大多集中在性能问题上, 笔者之前的文章中正好对应了第 2 点. 其实前 4 点都是很严重的系统问题, 应用程序很容易出现 `卡顿/阻塞` 的故障.

## 如何解决 dentry 条目过多的问题

### drop cache 清理


参考手册页说明:
```
drop_caches

Writing to this will cause the kernel to drop clean caches, as well as
reclaimable slab objects like dentries and inodes.  Once dropped, their
memory becomes free.

To free pagecache:
  echo 1 > /proc/sys/vm/drop_caches
To free reclaimable slab objects (includes dentries and inodes):
  echo 2 > /proc/sys/vm/drop_caches
To free slab objects and pagecache:
  echo 3 > /proc/sys/vm/drop_caches
```

可回收的 slab 对象均可通过以下方式清理:
```
# To free dentries and inodes:
echo 2 > /proc/sys/vm/drop_caches
```

> 备注: 短期内清理大量的 cache 可能引起短暂的性能问题. 可以在低峰期操作. 如果 `unused 和 negative` 数量很多, 影响理论上就很小.

### negative-dentry-limit 参数调整

比较推荐的方法是设置 `negative-dentry-limit` 系统参数:

```
fs.negative-dentry-limit:

This integer value specifies a soft limit on the total number of
negative dentries allowed in a system as a percentage of the total
system memory available. The allowable range for this value is 0-100.
A value of 0 means there is no limit. Each unit represents 0.1% of
the total system memory. So 10% is the maximum that can be specified.
```

该参数需要注意三点:
```
1. centos 系列中, 仅 centos 7 支持该参数, 且许满足以下条件:
    RHEL7.7.z errata kernel version 3.10.0-1062.21.1.el7
    RHEL7.8 GA kernel version 3.10.0-1127.el7

2. 高版本系统(ubuntu 18/20)去掉了 negative-dentry-limit 系统参数, 内核优化了清理 dentry 的算法;

3. 参数值最终的最大值为系统内存的 10%, 比如设置 3(每个数字代表: n * 0.1% 的总内存大小), 就相当于
   最大内存使用为系统的 0.3%, 理论上 256G 主机失效的 dentry 数量不超过 4214279 个条目(按每个 192 字节算)
```

由于 `fs.negative-dentry-limit` 是失效的 dentry, 所以如果当前活跃的 dentry 很多, 那边该参数对 dentry 的清理病没有多少效果.

### negative-dentry-limit 参数对比

> hostA 设置为 3, hostB 设置为 0

| 调整项 | hostA - 3 (used,unused,negative) | hostB - 0 (used,unused,negative) |
| :-: | :-: | :-: | :-: |
| 调整前 | 239587546, 239475968, 187333985 | 395154018, 200554616, 167335983 |
| 调整后 | 52842213, 52733149, 2087023 | 147393634, 146441244, 53846573
| drop cache 一周后 | 25618330, 25523435, 4000385 | 53870175, 53774420, 32445352 |


可以观察到, drop cache 之后, hostA 的失效条目(negative dentry) 一直在 400w 左右, 而 hostB 的值则随着时间推移越来越大. 另外需要注意的是目前为止系统没有参数来控制总的 dentry 数量大小.


## 总结

dentry 的最终目的是加快路径的查找解析, 不过内核总是尽可能多的缓存 dentry 条目. 但对系统而言, dentry 越多, 带来的风险和性能影响就越大. 在实际场景中可以通过 `drop_cache` 或者 `fs.negative-dentry-limit` 参数来做一些策略调整. 但是需要注意这些策略都是假定有足够多的 `unused 和 negative` 状态的 dentry 条目. 或许以后的内核会直接支持设置最大的 dentry 限制, 免去本文中我们讨论的这些注意事项.
