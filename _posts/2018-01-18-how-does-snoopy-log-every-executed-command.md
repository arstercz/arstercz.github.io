---
id: 953
title: How does snoopy log every executed command
date: 2018-01-18T17:53:50+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=953
permalink: /how-does-snoopy-log-every-executed-command/
categories:
  - system
tags:
  - snoopy
---
## snoopy 介绍

[snoopy](https://github.com/a2o/snoopy) 是一个轻量级的lib库, 用来记录系统中所有执行过的命令(以及参数). 我们在实际环境的使用过程中, 结合 snoopy 和 rsyslog 可以很方便的搜集所有主机的历史执行命令, 这种方式给安全审计和故障排错带来了很大的便利. 不同于以往的 `shell + history` 方式, snoopy 是以预加载 (`preload`) 的方式实现历史命令的记录, 整个会话环境的信息都可以记录下来, 而前者则仅仅记录执行的命令, 且容易绕过记录, 难以满足我们的需求. 安装部署可参考 [install](https://github.com/a2o/snoopy/blob/master/doc/INSTALL.md), [rpm-install](https://github.com/arstercz/sys-rpm). 下文则详细介绍 snoopy 如何实现以及使用事项.

## snoopy 如何工作

linux 的 `ld.so, ld-linux.so`(动态链接)机制可以让程序在运行的时候加载或预处理需要的动态库文件(使用 `--static` 选项编译的程序除外). 其提供以下不同的文件:

```
/lib/ld.so
    a.out dynamic linker/loader
/lib/ld-linux.so.{1,2}
    ELF dynamic linker/loader
/etc/ld.so.cache
    File containing a compiled list of directories in which to search for libraries and an ordered list of candidate libraries.
/etc/ld.so.preload
    File containing a whitespace separated list of ELF shared libraries to be loaded before the program.
lib*.so*
    shared libraries
```
snoopy 即是通过 `preload` 的方式在程序进行 `execv()` 和 `execve()` 系统调用的时候记录下所有需要的信息. 这种方式即意味着 snoopy 对用户和程序是透明的, 仅做记录处理, 不能改变用户或程序的命令. 已经运行的程序不受 preload 机制约束, 因为`execv` 和 `execve` 两个函数仅用于新执行一个程序. 当然如果执行的是一个脚本, 而脚本中又有 `execv` 和 `execve` 相关的系统调用(比如脚本里调用系统命令), snoopy 也会记录下来. 这在故障排错和审计的场景中是一个非常有用的功能.

### 系统调用

`unix/linux` 提供了 7 中不同的 exec 函数来初始执行新的程序, 如下所示:

```c
#include <unistd.h>

int execl(const char *pathname, const char *arg0, ... /* (char *)0 */ );
int execv(const char *pathname, char *const argv []);
int execle(const char *pathname, const char *arg0, .../* (char *)0, char *const envp[] */ );
int execve(const char *pathname, char *const argv[], char *const envp []);
int execlp(const char *filename, const char *arg0,... /* (char *)0 */ );
int execvp(const char *filename, char *const argv []);
int fexecve(int fd, char *const argv[], char *const envp[]);
```
这些函数中前 4 个函数取路径名作为参数, 后两个取文件名作为函数, 最后一个取文件描述符作为参数.这几个函数的参数表传递略有不同, 含有 `l` 的函数为列表 list, 比如 execl, execlp, execle 要求将新程序的每个命令行参数都说明为一个单独的参数; 含有 `v` 的函数为矢量 vector, 比如 execv, execvp, execve, fexecve 等需要先构造一个指向各参数的指针数组, 再讲数组地址作为函数的参数; 含有 `e` 结尾的函数, 比如 execle, execve, fexecve 可以传递一个指向环境字符串指针数组的指针.

### 封装 execv, execve

snoopy 的[内部](https://github.com/a2o/snoopy/blob/master/doc/internals/README.md)则通过封装 `execv`, `execve` 函数实现记录命令的目的. 即在执行程序之前, 通过 preload 机制, 预先加载封装好的 `execv` 和 `execve` 函数, 记录执行的命令, 则实际执行真实的命令.

[execve_wrapper.c](https://github.com/a2o/snoopy/blob/master/src/eventsource/execve_wrapper.c) 源文件包含了这两个函数的封装:
```c
#include <dlfcn.h>
...
#define FN(ptr, type, name, args)   ptr = (type (*)args)dlsym (REAL_LIBC, name)
...
int execv (const char *filename, char *const argv[]) {
    static int (*func)(const char *, char **);

    FN(func, int, "execv", (const char *, char **const));
    snoopy_log_syscall_execv(filename, argv);

    return (*func) (filename, (char **) argv);
}

int execve (const char *filename, char *const argv[], char *const envp[])
{
    static int (*func)(const char *, char **, char **);

    FN(func, int, "execve", (const char *, char **const, char **const));
    snoopy_log_syscall_execve(filename, argv, envp);

    return (*func) (filename, (char**) argv, (char **) envp);
}
```

`snoopy_log_syscall_execv` 和 `snoopy_log_syscall_execve` 函数则无论成功与否都不会影响后续程序的真实执行, 在 [log.c](https://github.com/a2o/snoopy/blob/master/src/log.c) 源文件中处理, 两个都通过调用 `snoopy_log_syscall_exec` 函数进行处理, 该函数则包括解析配置, 初始化, 过滤, 输出等功能.

### 流程说明

我们以 `strace uptime >/tmp/uptime.log 2>&1` 命令为例, 追踪具体的处理流程:
```
execve("/usr/bin/uptime", ["uptime"], [/* 37 vars */]) = 0
brk(0)                                  = 0xceb000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fe960e52000
access("/etc/ld.so.preload", R_OK)      = 0
open("/etc/ld.so.preload", O_RDONLY)    = 3
fstat(3, {st_mode=S_IFREG|0644, st_size=28, ...}) = 0
mmap(NULL, 28, PROT_READ|PROT_WRITE, MAP_PRIVATE, 3, 0) = 0x7fe960e51000
close(3)                                = 0
open("/usr/local/lib/libsnoopy.so", O_RDONLY) = 3
......
......
```
系统直接以 `execve` 函数开始执行 `uptime` 程序, 第 4 行开始访问 `/etc/ld.so.preload`, 进而加载 `/usr/local/lib/libsnoopy.so`, 后续内容则为具体的执行信息. 而 snoopy 的输出则包含以下:
```
Jan 18 16:19:52 cz-test1 snoopy[16530]: [uid:0 sid:24493 tty:/dev/pts/3 cwd:/root filename:/usr/bin/strace]: strace uptime
Jan 18 16:19:52 cz-test1 snoopy[16533]: [uid:0 sid:24493 tty:/dev/pts/3 cwd:/root filename:/usr/bin/uptime]: uptime
```
snoopy 搜集了很全的信息, 包括 uid, sid, cwd 等. 更多输出选项可通过 `snoopy.ini` 配置文件查看.

## 配置处理

在较新的 2.x.x 版本中, snoopy 增加了 `snoopy.ini` 配置文件供用户配置记录所需的信息, 主要包含下面几个选项:

#### message_format

`message_format` 为输出格式选项, 支持的列都在配置文件中进行了说明, 上述示例的输出是通过以下面的配置获取的:
```bash
message_format = "[uid:%{uid} sid:%{sid} pid:%{pid} tty:%{tty} cwd:%{cwd} filename:%{filename}]: %{cmdline}"
```

#### filter_chain

`filter_chain` 为过滤规则, 可以只记录某个 uid 的所有操作, 也可以忽略记录某个 uid 的操作. 真实的环境中, 我们可能忽略一些监控用户的所有操作避免监控引起 snoopy 频繁的输出日志. 下面的配置则为忽略记录 uid 为 496 的用户的所有操作:

```bash
filter_chain = exclude_uid:496
```

#### output

output 为输出选项, 支持的种类较多, 可以是 devlog, denull, devtty, file, socket, stderr, stdout, syslog 等. 默认为 `devlog`, snoopy 通过 socket 方式输出到本地的 syslog, `/dev/log` 详见内核文件 devices.txt:
```
        Sockets and pipes
Non-transient sockets and named pipes may exist in /dev.  Common entries are:

/dev/printer    socket          lpd local socket
/dev/log        socket          syslog local socket
/dev/gpmdata    socket          gpm mouse multiplexer
```

file 选项使用的也比较多, 可以输出到指定的文件, stdout 则为标准输出, socket 方式则相对高级, 用户可以指定 snoopy 输出到指定的 socket 中, socket 文件的另一端有其它程序接收即可收到日志信息.

syslog 选项在旧版中存在比较严重的 bug, 可能会引起系统挂死, 详见 [FAQ](https://github.com/a2o/snoopy/blob/master/doc/FAQ.md) 1, 2 两个条目说明.

#### syslog_xxx

`syslog_xxx` 几个选项规定了以什么格式传给 syslog, `syslog_level` 为日志级别, 默认为 `LOG_INFO`, `syslog_facility` 日志分类, 默认为 `LOG_AUTHPRIV`, `syslog_ident` 为程序名, 默认为 `snoopy`. rsyslog 将收到的信息归属到哪个日志文件, 由 rsyslog 配置的 `authpriv` 决定, 一般情况下都会在以下几个文件中:
```
/var/log/auth*
/var/log/messages
/var/log/secure
```

## 注意事项

[FAQ](https://github.com/a2o/snoopy/blob/master/doc/FAQ.md) 文档中描述了所有需要注意的问题. 实际上对于 snoopy 而言, 其通过封装 `execv` 和 `execve` 函数来记录执行的命令, 从性能方面来看, snoopy 可能延长正常的命令执行的时间. 

如果中间的过程处理不当也可能引起其它方面的 bug, 比如 faq 中提到的 `hangs systemd based system` 以及 [issue106](https://github.com/a2o/snoopy/issues/106) 等问题, 所以在实际使用中, 尽量安装最新的版本, 也建议大家多看看 [snoopy](https://github.com/a2o/snoopy) 的 issue 列表, 以及相关的 faq 文档.另外 snoopy 并不是万能的, 用户可以通过 `LD_PRELOAD` 环境变量绕过 snoopy 的记录, 详见 faq 文档说明;

同样的如果 snoopy 产生的日志过大, 可以在 `snoopy.ini` 中尽量配置需要忽略的选项, 配置完成后已经运行的程序不会立即生效, 需要重启程序以重新加载 `preload`.

## 总结

整体上看, snoopy 通过封装系统调用来实现记录执行的命令, 这就存在一定的风险, 比如降低系统性能, 和其它软件相冲突, 以及 hang 住系统等严重的问题, 但也带来了其它方面的好处, 在安全审计和故障排错的场景中尤为有用. 当然我们也可以按需开启 snoopy, 比如在排错的场景中, 排错前开启, 完成后再关闭即可. 不过已经运行的程序不受 `preload` 机制的影响, 毕竟 上述介绍的 exec 相关的函数仅用来执行新的程序, 未使用上述的两个系统调用则不会被 snoopy 处理.