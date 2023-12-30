---
layout: post
title: "如何杀掉 close_wait 状态的连接"
tags: [close_wait]
comments: true
---

## CLOSE_WAIT 连接状态说明

在 tcp 连接状态中, `LISTEN`, `ESTABLISHED` 和 `TIME_WAIT` 可能是最为常见的三类状态. 相比而言 `CLOSE_WAIT` 就比较少见, 大多数情况下 `CLOSE_WAIT` 状态持续的时间会很短, 如果持续时间很长, 就意味着程序处理可能出现了异常. 如下图所示:

```
      TCP A                                                    TCP B

  1.  ESTABLISHED                                                  ESTABLISHED

  2.  (Close)
      FIN-WAIT-1  --> <SEQ=100><ACK=300><CTL=FIN,ACK>          --> CLOSE-WAIT

  3.  FIN-WAIT-2  <-- <SEQ=300><ACK=101><CTL=ACK>              <-- CLOSE-WAIT

  4.                                                               (Close)
      TIME-WAIT   <-- <SEQ=300><ACK=101><CTL=FIN,ACK>          <-- LAST-ACK

  5.  TIME-WAIT   --> <SEQ=101><ACK=301><CTL=ACK>              --< CLOSED

  6.  (2 MSL)
      CLOSED
```


在 A, B 两端都为 `ESTABLISHED` 的情况下, B 收到 A 的 fin 包后(比如 A 主动要断开该连接), 同时返回给 ack 包给 A, 连接状态就会变更为 `CLOSE-WAIT`, 此后, B 继续发送 fin 包给 A 后, 连接状态才能改变到 `LAST-ACK`. 由此可以猜想到 B 的连接状态如果一直处于 `CLOSE-WAIT`(系统不会回收该状态, 直到人为干预或重启程序), 就表示 B 没有发 fin 包给对方. 通常造成这种情况很大的一部分原因是 B 的服务程序没有正常关闭连接.


## 如何杀掉 CLOSE_WAIT 状态的连接

了解到原理后, 可以猜到有两种方式杀掉 `CLOSE_WAIT` 状态的连接:

### 重启程序

如果可以重启程序, 这种就是最有效的方式, 但所有连接都会释放, 重启后还是会出现新的 `CLOSE_WAIT` 连接. 这种方式最好是在修复程序后再重启.

### 不重启程序

要在不影响程序的前提下释放 `CLOSE_WAIT`, 就需要想办法干预到该 tcp 连接状态. 干预的方式大致可以分为 `伪造数据包` 和 `gdb 调试` 两种方式:


#### 伪造数据包

一些开源工具提供了干预 tcp 连接状态的方法, 比如 [killcx](https://killcx.sourceforge.net/) 和 [kill-close-wait-connections](https://github.com/rghose/kill-close-wait-connections), 这两种工具本质上都是伪造数据包向 tcp 连接的两端发送数据, 让原始的端响应进而引起 tcp 连接状态改变, 前者可以很好的处理 `ESTABLISHED` 状态的连接,  后者则由于难以干预到程序服务的连接会出现 kill 失败的情况. 

#### gdb 调试

gdb 方式更为稳妥, 原理则主要是先获取到处于 CLOSE_WAIT 连接的 fd 句柄, 再通过 gdb 对该进程的执行关闭 fd 的操作. 可以参考文章 [remove_close-wait-connection](https://www.baeldung.com/linux/remove-close_wait-connection), 执行以下操作:

```
# 通过 ss 拿到对应连接的 fd

ss -tap | grep CLOSE-WAIT
CLOSE-WAIT 1   0       10.0.0.11:9999      10.0.0.12:56990      users:(("nc",pid=6117,fd=417)


# 通过 gdb 强制关闭对应的 fd

gdb -p 6117 -batch -ex 'print (int)close(417)'
```

上述两种方式各有优缺点, 不过也给我们提供了很多处理类似问题的思路. 但重要的是不管采用哪种方式, 都需要在测试环境做更多的测试.

## 参考

[https://www.baeldung.com/linux/remove-close_wait-connection](https://www.baeldung.com/linux/remove-close_wait-connection)  
[https://killcx.sourceforge.net/](https://killcx.sourceforge.net/)  
[https://github.com/rghose/kill-close-wait-connections](https://github.com/rghose/kill-close-wait-connections)  
[https://access.redhat.com/solutions/437133](https://access.redhat.com/solutions/437133)  
