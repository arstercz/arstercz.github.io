---
id: 981
title: 监控 redis warn 级别日志信息
date: 2018-05-11T14:15:26+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=981
permalink: '/%e7%9b%91%e6%8e%a7-redis-warn-%e7%ba%a7%e5%88%ab%e6%97%a5%e5%bf%97%e4%bf%a1%e6%81%af/'
categories:
  - monit
  - nosql
tags:
  - redis
  - syslog
---
## 介绍

我们现有的 redis 监控包括 [zabbix](https://github.com/arstercz/zabbix_redis), cacti 以及定制的 redis-sentinel-notify 脚本. 在不进行 sentinel 切换的前提下, 很难发现 redis 是否出现了其它错误, 比如连接占满, 同步异常, 后台线程中断等. redis 的日志级别提供了更为详细的诊断的信息. 从 redis 源代码中搜索 redisLog 函数的 REDIS_WARNING 相关的参数即可管中窥豹的了解到 warn 级别提供的大多都是有用的诊断信息, 基于此我们可以通过 warn 信息来了解更精确的诊断信息.

## redis 日志级别

以 `redis-4.0.8` 版本为例说明, server.h 文件中其包含系统的 syslog.h 头文件, 可以看到 redis 日志级别遵循 syslog 的级别信息, 不过只用到了以下 4 个级别:
```
/usr/include/sys/syslog.h 文件
....
#define LOG_WARNING     4       /* warning conditions */
#define LOG_NOTICE      5       /* normal but significant condition */
#define LOG_INFO        6       /* informational */
#define LOG_DEBUG       7       /* debug-level messages */
```

redis 的所有代码中日志的打印输出都通过 serverLog(旧版本 redisLog) 函数完成, redisLog 则通过 serverLogRaw(旧版本为 redisLogRaw 函数) 函数完成最终的输出:
```
# server.c 
void serverLog(int level, const char *fmt, ...) {
    va_list ap;
    char msg[LOG_MAX_LEN];

    if ((level&0xff) < server.verbosity) return;

    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    serverLogRaw(level,msg);
}
```

serverLogRaw 函数则实现了不同级别的输出, 在往日志文件输出的时候, 不同级别对应不同的前缀标识, 不过如果开启了 syslog_enabled, 则仅按 syslog 级别输出信息. 如下所示:
```
void serverLogRaw(int level, const char *msg) {
    const int syslogLevelMap[] = { LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING };
    const char *c = ".-*#";
    FILE *fp;
......

    if (rawmode) {
        fprintf(fp,"%s",msg);
    } else {
        int off;
        struct timeval tv;
......
        fprintf(fp,"%d:%c %s %c %s\n",
            (int)getpid(),role_char, buf,c[level],msg);
    }
    fflush(fp);

    if (!log_to_stdout) fclose(fp);
    if (server.syslog_enabled) syslog(syslogLevelMap[level], "%s", msg);
}
```

从 `fprintf... role_char, c[level], msg` 可以看到, 在往日志文件打印日志的时候, redis 提供了较为细致的分类, 提供了角色和日志级别信息. 其中的 `role_char` 为 redis 实例的角色信息:
```
C 为 RDB/AOF writing child
M 为 master
S 为 slave
X 为 sentinel
```
`c[level]` 则对应 `const char *c = ".-*#"`: 
```
LOG_DEBUG 对应 `.`
LOG_INFO 对应 `-`
LOG_NOTICE 对应 `*`
LOG_WARNING 对应 `#`
```
比如以下的日志消息为 master 进行了 `shutdown` 操作:
```
27883:M 10 May 11:40:36.446 # User requested shutdown...
27883:M 10 May 11:40:36.448 # Redis is now ready to exit, bye bye...
```

当然我们也可以将这两个信息打印到 syslog 中, 不过需要重新编译, 而且也不够通用. 

## 监控日志信息

#### syslog 方式

从上述的描述来看, 开启 syslog 选项后, redis 打印的信息较少, 不过可以通过 rsyslog 的报警机制对 redis 日志进行过滤, 不过因为缺少前缀信息, 不方便对需要的信息进行匹配. 一个解决方式是将上述提到的两个信息加到 serverLogRaw 函数中进行编译运行. 不过这种方式不通用, 不能解决已经运行的 redis 实例.

#### 日志文件
 
另外可以监控 redis 日志文件, 按上述提到的, WARNNING 级别的日志都有 `#` 作为日志消息的前缀, 我们只需要单独过滤这类消息即可. 一个方式是通过 [sys-log-syslog](https://github.com/arstercz/sys-toolkit#sys-log-syslog) 将需要的日志增量发送到指定的 syslog server 中, 通过 rsyslog 进行匹配报警即可. 这种方式不需要 rsyslog 再进行处理, 因为接收到的日志已经是 warn 级别, 如下:
```
sys-log-syslog -f /opt/redis4.0/log/redis.log -t redis6381 -r '\s+#\s+' -d
2018_05_10_18_02_11 [info] redis6381 logger send ok
```
`-r` 选项兼容 perl 正则, 可以用来设置需要过滤的正则表达式, 这里只匹配含有 `#` 标识的日志信息. 更多信息参见 `--help` 选项. rsyslog 只需要简单匹配 `app-name` 即可:
```
$app-name contains 'redis'
```

其它的报警方式则与此类似, 都是着重于过滤 warn 级别的消息.

## 总结说明

仅监控 redis 的性能还不足以让我们了解到运行时的细节问题, warn 级别的日志消息则给我们提供了很详细的诊断信息, 通过这些信息可以具体发生了哪些问题. `sys-log-syslog` 是本文中用到的小工具, 大家也可以依据上文提到的准则以其它方式监控, 以满足具体的需求.