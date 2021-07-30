---
layout: post
title: "为什么 redis 提示 need enable AOF"
tags: [redis]
comments: true
---

有些程序在连接 Redis 的时候可能出于方便的原因会做一些管理性的操作, 比如 `bgsave, bgrewriteaof, slaveof` 等操作, 这些可能会产生一些意想不到的错误, 比如以下提示信息, 虽然不是致命的错误, 但看起来也很困惑:
```
[95138] 28 Jul 03:18:45.763 # Redis needs to enable the AOF but can't trigger a background AOF rewrite operation. Check the above logs for more info about the error.
[95138] 28 Jul 03:18:45.763 # Redis needs to enable the AOF but can't trigger a background AOF rewrite operation. Check the above logs for more info about the error.
```
可以看到这个提示是和 `AOF` 相关的, 默认没有开启 redis 的 `AOF` 设置, 不过程序在连接建立的时候会执行一次 `config set appendonly yes` 操作, 在 redis 中, `config set appendonly yes` 操作会自动触发一次 `startAppendOnly()` 操作, 如下所示:
```
# src/config.c
 642     } else if (!strcasecmp(c->argv[2]->ptr,"appendonly")) {
 643         int enable = yesnotoi(o->ptr);
 644 
 645         if (enable == -1) goto badfmt;
 646         if (enable == 0 && server.aof_state != REDIS_AOF_OFF) {
 647             stopAppendOnly();
 648         } else if (enable && server.aof_state == REDIS_AOF_OFF) {     // 之前为 no, 修改为 yes 时
 649             if (startAppendOnly() == REDIS_ERR) {                     // 执行 startAppendOnly
 650                 addReplyError(c,
 651                     "Unable to turn on AOF. Check server logs.");
 652                 return;
 653             }
 654         }
```

`startAppendOnly` 则主要执行了 `BGREWRITEAOF` 相关的操作, 如下所示:
```
 # src/aof.c
 190 /* Called when the user switches from "appendonly no" to "appendonly yes"
 191  * at runtime using the CONFIG command. */
 192 int startAppendOnly(void) {
 193     server.aof_last_fsync = server.unixtime;
 194     server.aof_fd = open(server.aof_filename,O_WRONLY|O_APPEND|O_CREAT,0644);
 195     redisAssert(server.aof_state == REDIS_AOF_OFF);
 196     if (server.aof_fd == -1) {
 197         redisLog(REDIS_WARNING,"Redis needs to enable the AOF but can't open the append only file: %s",strerror(errno));
 198         return REDIS_ERR;
 199     }
 200     if (rewriteAppendOnlyFileBackground() == REDIS_ERR) {
 201         close(server.aof_fd);
 202         redisLog(REDIS_WARNING,"Redis needs to enable the AOF but can't trigger a background AOF rewrite operation. Check the above logs for more info about the error.");
 203         return REDIS_ERR;
 204     }
 205     /* We correctly switched on AOF, now wait for the rerwite to be complete
 206      * in order to append data on disk. */
 207     server.aof_state = REDIS_AOF_WAIT_REWRITE;
 208     return REDIS_OK;
 209 }

...
 993 /* This is how rewriting of the append only file in background works:
 994  *
 995  * 1) The user calls BGREWRITEAOF
 996  * 2) Redis calls this function, that forks():
 997  *    2a) the child rewrite the append only file in a temp file.
 998  *    2b) the parent accumulates differences in server.aof_rewrite_buf.
 999  * 3) When the child finished '2a' exists.
1000  * 4) The parent will trap the exit code, if it's OK, will append the
1001  *    data accumulated into server.aof_rewrite_buf into the temp file, and
1002  *    finally will rename(2) the temp file in the actual file name.
1003  *    The the new file is reopened as the new append only file. Profit!
1004  */
1005 int rewriteAppendOnlyFileBackground(void) {
1006     pid_t childpid;
1007     long long start;
1008 
1009     if (server.aof_child_pid != -1) return REDIS_ERR;
1010     start = ustime();
1011     if ((childpid = fork()) == 0) {
1012         char tmpfile[256];
......
```

因为已经自动触发了 `BGREWRITEAOF` 操作(数据越多, `bgrewriteaof` 的耗时越长), 程序的连接再执行此操作的时候就会满足条件 `if (server.aof_child_pid != -1) return REDIS_ERR;`, 相应的也会满足下面的条件:
```
 200     if (rewriteAppendOnlyFileBackground() == REDIS_ERR) {
 201         close(server.aof_fd);
 202         redisLog(REDIS_WARNING,"Redis needs to enable the AOF but can't trigger a background AOF rewrite operation. Check the above logs for more info about the error.");
 203         return REDIS_ERR;
 204     }
```

因此就会产生上述的错误提示 `"Redis needs to enable the AOF but can't trigger a background AOF rewrite operation. Check the above logs for more info about the error."`, 不过该提示不会影响程序正常的请求处理.

> 备注: 如果redis 初始开启了 aof 或者手动在运行过程中设置了 `config set appendonly yes`, 之后程序每次连接执行 `BGREWRITEAOF` 就不会触发 `startAppendOnly()` 操作, 相应的也就不会满足条件 `if (server.aof_child_pid != -1) return REDIS_ERR;`, 所以不会再有上述的提示.

#### 如何避免此类问题?

对应用程序而言, 我们使用 redis 是建议去掉所有 redis 管理类的命令使用, 并遵守以下原则:
```
1. 程序仅做常规的数据操作命令;
2. 管理类命令由中间层工具或管理员操作;
```
