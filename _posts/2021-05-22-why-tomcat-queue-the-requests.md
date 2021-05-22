---
layout: post
title: "为什么 tomcat 对请求做了排队"
tags: [tomcat, java]
comments: true
---

## 问题说明


近期对 tomcat 一个比较老的版本做了一些长请求的测试, 每个请求会触发 tomcat 做一次 sleep 300 秒的操作:
```
运行环境:
   jdk-1.8.0_152
   tomcat-6.0.37
```

tomcat 的 connector 配置:
```
# 开启 ssl
<Connector port="443" maxHttpHeaderSize="8192" protocol="org.apache.coyote.http11.Http11NioProtocol"
        maxThreads="800" acceptCount="1000" minSpareThreads="50"
        enableLookups="false" disableUploadTimeout="true"
        maxKeepAliveRequests="1000" connectionTimeout="120000"
        SSLEnabled="true" scheme="https" secure="true"
        clientAuth="true" sslProtocol="TLS" />
```

配置中, 连接器使用了 `Http11NioProtocol` 非阻塞协议, Nio 协议默认最大连接数 10000, 同时运行线程数最大 800, 排队最大 1000，从配置来看, tomcat 应该是可以同时运行几百个请求的, 不过从 tcp 抓包来看, 却出现了排队的现象:

```
// tshark 解析抓包的数据
    1 22:47:15.308511   10.11.1.10 → 10.11.1.13 TCP 74 54681 → 443 [SYN] Seq=0 Win=14600 Len=0 MSS=1460 SACK_PERM=1 TSval=1035175627 TSecr=0 WS=128
    2 22:47:15.336250 10.11.1.13 → 10.11.1.10   TCP 74 443 → 54681 [SYN, ACK] Seq=0 Ack=1 Win=28960 Len=0 MSS=1460 TSval=1051388483 TSecr=1035175627 WS=128
    3 22:47:15.336261   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=1 Ack=1 Win=14720 Len=0 TSval=1035175636 TSecr=1051388483
    4 22:47:15.336868   10.11.1.10 → 10.11.1.13 TLSv1.2 286 Client Hello
    5 22:47:15.364301 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [ACK] Seq=1 Ack=221 Win=30080 Len=0 TSval=1051388512 TSecr=1035175636
    6 22:47:15.398569 10.11.1.13 → 10.11.1.10   TLSv1.2 2304 Server Hello, Certificate, Server Key Exchange, Certificate Request, Server Hello Done
    7 22:47:15.398583   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=221 Ack=2239 Win=19200 Len=0 TSval=1035175654 TSecr=1051388546
    8 22:47:15.704171   10.11.1.10 → 10.11.1.13 TLSv1.2 1514
    9 22:47:15.704180   10.11.1.10 → 10.11.1.13 TLSv1.2 179 Ignored Unknown Record
   10 22:47:15.731674 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [ACK] Seq=2239 Ack=1782 Win=28544 Len=0 TSval=1051388879 TSecr=1035175746
   11 22:47:17.371044   10.11.1.10 → 10.11.1.13 TLSv1.2 591 Certificate Verify
   12 22:47:17.371056   10.11.1.10 → 10.11.1.13 TLSv1.2 72 Change Cipher Spec
   13 22:47:17.371101   10.11.1.10 → 10.11.1.13 TLSv1.2 167 Encrypted Handshake Message
   14 22:47:17.398470 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [ACK] Seq=2239 Ack=2313 Win=28032 Len=0 TSval=1051390546 TSecr=1035176246
   15 22:47:17.398809 10.11.1.13 → 10.11.1.10   TLSv1.2 72 Change Cipher Spec
   16 22:47:17.398815   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=2414 Ack=2245 Win=19200 Len=0 TSval=1035176254 TSecr=1051390546
   17 22:47:17.398859 10.11.1.13 → 10.11.1.10   TLSv1.2 167 Encrypted Handshake Message
   18 22:47:17.398865   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=2414 Ack=2346 Win=19200 Len=0 TSval=1035176254 TSecr=1051390546
   19 22:47:17.494386   10.11.1.10 → 10.11.1.13 TLSv1.2 375 Application Data
   20 22:47:17.494409   10.11.1.10 → 10.11.1.13 TLSv1.2 311 Application Data
   21 22:47:17.561281 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [ACK] Seq=2346 Ack=2968 Win=27520 Len=0 TSval=1051390709 TSecr=1035176283
   22 22:55:44.553134 10.11.1.13 → 10.11.1.10   TLSv1.2 327 Application Data
   23 22:55:44.553153   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=2968 Ack=2607 Win=22016 Len=0 TSval=1035328413 TSecr=1051897694
   24 22:55:54.517983   10.11.1.10 → 10.11.1.13 TLSv1.2 151 Encrypted Alert
   25 22:55:54.517992   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [FIN, ACK] Seq=3053 Ack=2607 Win=22016 Len=0 TSval=1035331403 TSecr=1051897694
   26 22:55:54.545383 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [ACK] Seq=2607 Ack=3053 Win=27520 Len=0 TSval=1051907686 TSecr=1035331403
   27 22:55:54.545485 10.11.1.13 → 10.11.1.10   TCP 66 443 → 54681 [FIN, ACK] Seq=2607 Ack=3054 Win=27520 Len=0 TSval=1051907686 TSecr=1035331403
   28 22:55:54.545522   10.11.1.10 → 10.11.1.13 TCP 66 54681 → 443 [ACK] Seq=3054 Ack=2608 Win=22016 Len=0 TSval=1035331411 TSecr=1051907686
```

10.11.1.10 与 `10.11.1.13` 经过了以下流程:
```
1. 完成了 tcp 三次握手           -->  对应 1 ~ 3    号报文;
2. 完成了 tls/ssl 握手           -->  对应 3 ~ 18   号报文;
3. 10 主机发送请求数据           -->  对应 19, 20   号报文;
4. 13 主机发送 ack 确认          -->  对应 21       号报文;
5. 3 分钟 29 秒后返回数据        -->  对应 22, 23   号报文;
6. 10 主机断开连接, 完成四次挥手 -->  对应 24 ~ 28  号报文; 
```

对应的 13 主机上的 netstat 输出如下所示, 很多连接的接收队列中(Recv-Q)都有数据:
```
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
......  
tcp6       0      0 :::443                  :::*                    LISTEN      4849/java           
tcp6       0      0 127.0.0.1:8005          :::*                    LISTEN      4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44716        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44650        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44744        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44702        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44712        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44722        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44752        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44704        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44693        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44663        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44655        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44642        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44653        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44644        ESTABLISHED 4849/java           
tcp6       0      0 10.11.1.13:443       10.11.1.10:44643        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44685        ESTABLISHED 4849/java           
tcp6     554      0 10.11.1.13:443       10.11.1.10:44711        ESTABLISHED 4849/java       
......
```

从上面的现象来看, tomcat 出现了排队进而形成了整个连接正常完成了 tcp 连接, 并发送数据, 但是一直等待的情况. 相应的, tomcat 正常的请求处理完成后, 开始处理排队中的请求. 所以整体上看, 就出现了下面的问题:

```
同时发送 120 个请求, 却分了两批顺序执行. 即本该 3 分钟左右执行完的操作, 7 分钟多才执行完.
```

## 为什么会产生排队

netstat 的输出可以看到, tomcat 可能产生了排队, 这可能意味着 `maxThreads` 等参数并没有生效. 从下面的 java 线程堆栈来看:
```
"http-443-ClientPoller-0" #23 daemon prio=5 os_prio=0 tid=0x00007f3ea8759800 nid=0x10f81 runnable [0x00007f3e6f8fd000]
   java.lang.Thread.State: RUNNABLE
        at sun.nio.ch.EPollArrayWrapper.epollWait(Native Method)
        at sun.nio.ch.EPollArrayWrapper.poll(EPollArrayWrapper.java:269)
        at sun.nio.ch.EPollSelectorImpl.doSelect(EPollSelectorImpl.java:93)
        at sun.nio.ch.SelectorImpl.lockAndDoSelect(SelectorImpl.java:86)
        - locked <0x0000000726239048> (a sun.nio.ch.Util$3)
        - locked <0x0000000726239038> (a java.util.Collections$UnmodifiableSet)
        - locked <0x0000000726234158> (a sun.nio.ch.EPollSelectorImpl)
        at sun.nio.ch.SelectorImpl.select(SelectorImpl.java:97)
        at org.apache.tomcat.util.net.NioEndpoint$Poller.run(NioEndpoint.java:1591)
        at java.lang.Thread.run(Thread.java:748)

   Locked ownable synchronizers:
        - None
```

内部线程使用了 nio 相关的连接池, 如下代码:
```
# tomcat-6.0.37/java/org/apache/tomcat/util/net/NioEndpoint.java
2346     // ---------------------------------------------- TaskQueue Inner Class
2347     public static class TaskQueue extends LinkedBlockingQueue<Runnable> {
2348         ThreadPoolExecutor parent = null;
2349         NioEndpoint endpoint = null;
2350 
2351         public TaskQueue() {
2352             super();
2353         }
2354 
2355         public TaskQueue(int initialCapacity) {
2356             super(initialCapacity);
2357         }
2358 
2359         public TaskQueue(Collection<? extends Runnable> c) {
2360             super(c);
2361         }
2362 
2363 
2364         public void setParent(ThreadPoolExecutor tp, NioEndpoint ep) {
2365             parent = tp;
2366             this.endpoint = ep;
2367         }
2368 
2369         public boolean offer(Runnable o) {
2370             //we can't do any checks
2371             if (parent==null) return super.offer(o);                                                 // 1
2372             //we are maxed out on threads, simply queue the object
2373             if (parent.getPoolSize() == parent.getMaximumPoolSize()) return super.offer(o);          // 2
2374             //we have idle threads, just add it to the queue
2375             //this is an approximation, so it could use some tuning
2376             if (endpoint.activeSocketProcessors.get()<(parent.getPoolSize())) return super.offer(o); // 3
2377             //if we have less threads than maximum force creation of a new thread
2378             if (parent.getPoolSize()<parent.getMaximumPoolSize()) return false;                      // 4
2379             //if we reached here, we need to add it to the queue
2380             return super.offer(o);
2381         }
2382     }
```

`public boolean offer(Runnable 0)` 函数用来判断是否创建新的线程:
```
1. return false          表示连接池创建新的线程处理请求;
2. return super.offer(0) 表示将建立的连接(socket 对象)直接放到队列等待处理;
```

对应的几个变量值如下所示, 由于都是通过方法获取的当前值, 所以在并发情况下, 变量的值都不会很准确.
```
parent.getPoolSize:                  连接池中的线程数;
parent.getMaximumPoolSize            连接池中配置的最大线程数;
endpoint.activeSocketProcessors.get  等同当前正在工作的线程数, 开始处理加 1, 处理完成减 1, 该值变化很快, 可能不准确;
```

在上述代码的 4 个 if 判断中:
```
1. 基本不会发生;
2. 实际上在大并发环境下也很难发生, 这种情况不满足我们的条件;
3. 这种概率较大, 当前工作线程数小于连接池已有的线程的时候, tomcat 不会再去创建新的线程; 这种方式猜测应该是想让连接池平滑的增长;
4. 如果不满足 3, 意味着 activeSocketProcessors >= parent.getPoolSize, 这种情况就需要创建新的线程来处理请求;
```

我们着重查看 3, 4 两种情况, 在该函数中增加一些日志输出后, 如下所示, 输出了上述的三个变量以及当前连接池正在运行的线程数(parent.getActiveCount):
```
        public boolean offer(Runnable o) {
            //we can't do any checks
            if (parent == null) {
                System.out.println("xa1111, parent: null"
                        + ", runnable: " + o.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(o)));
                return super.offer(o);
            }

            //we are maxed out on threads, simply queue the object
            if (parent.getPoolSize() == parent.getMaximumPoolSize()) {
                System.out.println("xa2222, parent.poolSize: " + parent.getPoolSize()
                    + ", activeThreadCount: " + parent.getActiveCount()
                    + ", maxPoolSize: " + parent.getMaximumPoolSize()
                    + ", activeSocketProcessors: " + endpoint.activeSocketProcessors.get()
                    + ", runnable: " + o.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(o)));
                return super.offer(o);
            }

            //we have idle threads, just add it to the queue
            //this is an approximation, so it could use some tuning
            if (endpoint.activeSocketProcessors.get() < (parent.getPoolSize())) {
                System.out.println("xa3333, parent.poolSize: " + parent.getPoolSize()
                    + ", activeThreadCount: " + parent.getActiveCount()
                    + ", maxPoolSize: " + parent.getMaximumPoolSize()
                    + ", activeSocketProcessors: " + endpoint.activeSocketProcessors.get()
                    + ", runnable: " + o.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(o)));
                return super.offer(o);
            }
            //if we have less threads than maximum force creation of a new thread
            if (parent.getPoolSize()<parent.getMaximumPoolSize()) {
                System.out.println("xa4444, parent.poolSize: " + parent.getPoolSize()
                    + ", activeThreadCount: " + parent.getActiveCount()
                    + ", maxPoolSize: " + parent.getMaximumPoolSize()
                    + ", activeSocketProcessors: " + endpoint.activeSocketProcessors.get()
                    + ", runnable: " + o.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(o)));
                return false;
            }
            //if we reached here, we need to add it to the queue

            System.out.println("xa5555, parent.poolSize: " + parent.getPoolSize()
                + ", activeThreadCount: " + parent.getActiveCount()
                + ", maxPoolSize: " + parent.getMaximumPoolSize()
                + ", activeSocketProcessors: " + endpoint.activeSocketProcessors.get()
                + ", runnable: " + o.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(o)));
            return super.offer(o);
        }
```

重新编译该文件后生成 tomcat-coyote.jar 包, 替换 `tomcat lib` 目录下原有的 jar 包, 以同样的参数进行测试, 同时发起 120 个请求:
```
# 批操作平台开始执行
xa3333, parent.poolSize: 5, activeThreadCount: 0, maxPoolSize: 800, activeSocketProcessors: 0, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@73564b1b    ==> 1
xa3333, parent.poolSize: 5, activeThreadCount: 1, maxPoolSize: 800, activeSocketProcessors: 1, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@6d42899e
xa3333, parent.poolSize: 5, activeThreadCount: 2, maxPoolSize: 800, activeSocketProcessors: 2, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@7a63a066
xa3333, parent.poolSize: 5, activeThreadCount: 3, maxPoolSize: 800, activeSocketProcessors: 3, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@3f49bd1e
xa3333, parent.poolSize: 5, activeThreadCount: 4, maxPoolSize: 800, activeSocketProcessors: 4, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@3eb01d19
xa4444, parent.poolSize: 5, activeThreadCount: 5, maxPoolSize: 800, activeSocketProcessors: 5, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@68b72979
xa4444, parent.poolSize: 6, activeThreadCount: 6, maxPoolSize: 800, activeSocketProcessors: 6, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@25026a2d
xa4444, parent.poolSize: 7, activeThreadCount: 7, maxPoolSize: 800, activeSocketProcessors: 7, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@487dada9
...
xa3333, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 89, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@15c39f47
xa3333, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 89, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@6d2a0994
xa3333, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 89, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@28db91d9
xa3333, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 89, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@646a3a78
xa3333, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 89, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@10ae62a7
xa4444, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 90, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@414496b0   ==> 2

第一批 90 个执行完, 等待 300s 左右后, 第二批开始执行

xa4444, parent.poolSize: 91, activeThreadCount: 91, maxPoolSize: 800, activeSocketProcessors: 91, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@151978be   ==> 3
xa4444, parent.poolSize: 92, activeThreadCount: 92, maxPoolSize: 800, activeSocketProcessors: 92, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@2a95501b
xa4444, parent.poolSize: 92, activeThreadCount: 92, maxPoolSize: 800, activeSocketProcessors: 92, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@1f27612
....
xa3333, parent.poolSize: 63, activeThreadCount: 2, maxPoolSize: 800, activeSocketProcessors: 1, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@1db266b7
xa3333, parent.poolSize: 63, activeThreadCount: 3, maxPoolSize: 800, activeSocketProcessors: 3, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@325177
xa3333, parent.poolSize: 63, activeThreadCount: 2, maxPoolSize: 800, activeSocketProcessors: 2, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@6aef6ea3
xa3333, parent.poolSize: 59, activeThreadCount: 0, maxPoolSize: 800, activeSocketProcessors: 0, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@baa6f57      ==> 4
第二批执行完
```

这里的 parent.poolSize 初始为 5, 该值对应 tomcate 的 `minSpareThreads` 参数, 

*备注*: 在 tomcat 6 中, `minSpareThreads` 和 maxSpareThreads` 参数不允许修改, 默认均为 5, 如下所示:

```
# tomcat/java/org/apache/tomcat/util/net/NioEndpoint.java
 529     /**
 530      * Dummy maxSpareThreads property.
 531      */
 532     public int getMaxSpareThreads() { return Math.min(getMaxThreads(),5); }
 533 
 534 
 535     /**
 536      * Dummy minSpareThreads property.
 537      */
 538     public int getMinSpareThreads() { return Math.min(getMaxThreads(),5); }
 ...
```

可以在配置文件中指定这两个参数, 不过不会生效, 如下启动日志:
```
May 20, 2021 2:01:08 PM org.apache.catalina.startup.SetAllPropertiesRule begin
WARNING: [SetAllPropertiesRule]{Server/Service/Connector} Setting property 'minSpareThreads' to '50' did not find a matching property.
```

在上述的日志中, `activeSocketProcessors` 与 `activeThreadCount` 应该是等同的关系, 由于突然连接 120 个请求的原因, 在并发环境下两个值会有轻微的差异.

可以看到, 大部分的输出都是在 if 判断的条件 3 和 4, 满足 3 则排队, 满足 4 则新建线程处理请求, 从上面的输出可以看到官方文档对 [http Connector](https://tomcat.apache.org/tomcat-6.0-doc/config/http.html) 工作模式的描述是有点出入的, 如下所示:
```
Each incoming request requires a thread for the duration of that request. If more simultaneous requests are received than 
can be handled by the currently available request processing threads, additional threads will be created up to the configured 
maximum (the value of the maxThreads attribute). If still more simultaneous requests are received, they are stacked up 
inside the server socket created by the Connector, up to the configured maximum (the value of the acceptCount attribute). 
Any further simultaneous requests will receive "connection refused" errors, until resources are available to process them.
```

文档中描述的模式, 在大量请求同时来的时候, 我们容易理解成下面的流程:
```
   +------+     +------------------+    +-----------------------+    +------------------+     +----------+
   | 请求 | ->  |  当前连接池的线程   | -> |  最大线程数 maxThreads  | -> | 队列 acceptCount  | - > | 拒绝处理  |
   +------+     +------------------+    +-----------------------+    +------------------+     +----------+
```

实际上应该是下面的流程:
```
   +------+     +-------------------+       +------------------+    +-----------------------+    +------------------+     +----------+
   | 请求 | ->  |  请求队列(backlog)  |   ->  | 当前连接池的线程    | -> |  最大线程数 maxThreads | -> |  队列 acceptCount | - > |  拒绝处理  |
   +------+     +-------------------+       +------------------+    +-----------------------+    +------------------+     +----------+
```

这里的请求队列实际上是 tcp socket 的 backlog 属性, tomcat 中由 acceptCount 参数决定, 如下所示:
```
# tomcat/java/org/apache/catalina/connector/Connector.java
 301      protected static HashMap replacements = new HashMap();
 302      static {
 303          replacements.put("acceptCount", "backlog");           ==> 等同设置 tcp 连接的 backlog 属性
 304          replacements.put("connectionLinger", "soLinger");
 305          replacements.put("connectionTimeout", "soTimeout");
 306          replacements.put("connectionUploadTimeout", "timeout");
 ...
```

所有的 tcp 连接建立后放到 socket 的连接队列中, tomcat 的 worker 循环的检测并接收一个请求后就放到连接池进行处理, 随着请求的增加连接池开始做一系列活动. 对照上面的日志, 可以看到, 请求是逐个处理的, 当处理一个请求走到 if 条件 3 时, 则进行排队：
```
2374             //we have idle threads, just add it to the queue
2375             //this is an approximation, so it could use some tuning
2376             if (endpoint.activeSocketProcessors.get()<(parent.getPoolSize())) return super.offer(o); 
```

从注释说明来看, 这个判断不是精确的, 对比日志来看, `activeSocketProcessors 应该是小于 parent.poolSize 的`, 此时 90 个线程正在工作, 剩余的 30 个请求则在排队:
```
xa4444, parent.poolSize: 90, activeThreadCount: 90, maxPoolSize: 800, activeSocketProcessors: 90, runnable: org.apache.tomcat.util.net.NioEndpoint$SocketProcessor@414496b0
```

在 300 秒过后, 有线程执行完, 线程池继续从队列里取对象, 进而跳过条件 3, 满足条件 4, 创建线程继续处理. 参考照官方的几个 bug 来看:

[bz-44199](https://bz.apache.org/bugzilla/show_bug.cgi?id=44199)  
[bz-49730](https://bz.apache.org/bugzilla/show_bug.cgi?id=49730)  
[bz-64155](https://bz.apache.org/bugzilla/show_bug.cgi?id=64155)  

在 `BZ 44199` 中:
```
In a properly configured
production system, there should be rare situations where connections wait for a
worker thread to be handled. Our client complained on high latency of web
requests, but the measurement on servlet did not show high latency.
```

该 bug 在 2008 年提出, 提出者重新构造了一个自定义类就解决了等待的问题. 2017 年后官方合并了此类补丁, 对比 tomcat 7 和 tomcat 8 的情况来看, `Tomcat Connector` 自带的连接池做了很大的改变, 所以连接池的处理最好还是使用执行器(Executor) 的连接池. 从这方面来看解决上述的问题可以从几方面方面来入手.

## 如何处理

#### 1. 关闭 NIO 连接池

在 tomcat 6 的连接器 HTTP 文档中, `useExecutor` 属性决定了是否使用自身的 NIO(对应协议 `org.apache.coyote.http11.Http11NioProtocol`) 连接池, 更多见 [option-useExecutor](https://tomcat.apache.org/tomcat-6.0-doc/config/http.html), 如下所示:
```
(bool)Set to true to use the NIO thread pool executor. The default value is true. 
If set to false, it uses a thread pool based on a stack for its execution. 
Generally, using the executor yields a little bit slower performance, but yields 
a better fairness for processing connections in a high load environment as the 
traffic gets queued through a FIFO queue. If set to true(default) then the max 
pool size is the maxThreads attribute and the core pool size is the minSpareThreads. 

This value is ignored if the executor attribute is present and points to a valid 
shared thread pool.
```

`useExecutor` 选项默认为 true, 使用了 `NIO thread pool`, 我们碰到的问题即是在此连接池下的行为. 如果关闭此选项后, 则依据实际的请求数量创建线程, 最大不超过 `maxThreads`, 不过性能略不如连接池方式高效. 如下所示

```
# tomcat-6.0.37/java/org/apache/tomcat/util/net/NioEndpoint.java
# 最大 worker 数为 maxThreads
1169     /**
1170      * Create (or allocate) and return an available processor for use in
1171      * processing a specific HTTP request, if possible.  If the maximum
1172      * allowed processors have already been created and are in use, return
1173      * <code>null</code> instead.
1174      */
1175     protected Worker createWorkerThread() {
1176 
1177         synchronized (workers) {
1178             if (workers.size() > 0) {
1179                 curThreadsBusy++;
1180                 return (workers.pop());
1181             }
1182             if ((maxThreads > 0) && (curThreads < maxThreads)) {
1183                 curThreadsBusy++;
1184                 if (curThreadsBusy == maxThreads) {
1185                     log.info(sm.getString("endpoint.info.maxThreads",
1186                             Integer.toString(maxThreads), address,
1187                             Integer.toString(port)));
1188                 }
1189                 return (newWorkerThread());
1190             } else {
1191                 if (maxThreads < 0) {
1192                     curThreadsBusy++;
1193                     return (newWorkerThread());
1194                 } else {
1195                     return (null);
1196                 }
1197             }
1198         }
1199     }
```

在实际的测试中, 我们关闭此选项后, 所有请求(不超过 maxThreads 的数量)可以同时执行, 没有了排队的现象.

#### 2. 使用执行器的连接池

同 `useExecutor` 选项, 在开启的情况下, 如果指定了 `executor` 选项, 则会忽略 NIO 的连接池, 使用 Excutor 的连接池, 如下所示, 在 `conf/server.xml `配置中增加配置, 实际使用中, 我们都建议使用此配置:
```
# service 部分增加 Executor
    <Executor name="tomcatThreadPool" namePrefix="catalina-exec-" 
        maxThreads="800" minSpareThreads="50" maxIdleTime="60000"/>

# Connector 中指定 executor
    <Connector port="8080" maxHttpHeaderSize="8192" protocol="org.apache.coyote.http11.Http11NioProtocol"
    	executor="tomcatThreadPool" enableLookups="false" disableUploadTimeout="true"
        maxKeepAliveRequests="1000" connectionTimeout="120000" />
```

#### 3. 升级 tomcat 版本

`tomcat-6.0.37` 为 2013 年比较老的版本, 对比 tomcat 7 和 8, `NIO thread pool` 做了很大的改动, 从实际的测试来看, 使用 `tomcat 8` 版本的 Nio thread pool 也可以正常执行. 同样, 业务在使用 tomcat 8 的时候, 也建议 2 中的设置.

