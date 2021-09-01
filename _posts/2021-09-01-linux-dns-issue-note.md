---
layout: post
title: "Linux 系统设置 DNS 注意事项"
tags: [dns]
comments: true
---

在文章[Linux 系统如何处理名称解析]({{ site.baseurl }}/linux-%e7%b3%bb%e7%bb%9f%e5%a6%82%e4%bd%95%e5%a4%84%e7%90%86%e5%90%8d%e7%a7%b0%e8%a7%a3%e6%9e%90/)中, 提到了 Linux 系统处理域名解析的流程. 实际上出于性能相关的原因, 不同编程语言或框架对 DNS 的解析可能做了不同程度的封装. 典型的, 比如 [JDK](https://docs.oracle.com/javase/7/docs/technotes/guides/net/properties.html) 在没有开启安全管理(默认)的情况下, 会对 DNS 的解析条目缓存 30 秒. 又比如 [libevent](https://github.com/libevent/libevent) 提供了阻塞和非阻塞两种处理 DNS 请求的方式, 自由度更高.

这些设计方面的差异, 通常会让我们碰到以下几类 DNS 问题:

* [DNS Server 失效](#DNS-Server-失效)   
* [修改 /etc/{resolv.conf,hosts} 不生效](#修改-/etc/{resolv.conf,hosts}-不生效) 
* [DNS 解析性能不足](#DNS-解析性能不足)  

下面我们分别对这几个问题进行说明.

## DNS Server 失效

该问题最为常见, 通常系统中 `/etc/resolv.conf` 配置的 `nameserver` 出现故障(比如被攻击, 网络问题)的时候, 系统中的业务就可能出现 DNS 解析超时或失败的问题. 在这个问题中, 最常见的设置问题是仅在 `/etc/resolv.conf` 配置了一个 `nameserver`. 实际环境中, 我们建议配置三个 `nameserver`, 以轮询方式提供解析服务, 这样单个 `nameserver` 故障时仅影响一小部分解析请求. 如下所示:

```
options rotate timeout:1 attempts:1
nameserver xx.xx.xx.xx
nameserver xx.xx.xx.xx
nameserver xx.xx.xx.xx
```

可以多次执行以下命令, 验证多个 `nameserver` 是否生效:
```
strace -f  -e trace=connect curl -s -I baidu.com 2>&1 | grep 'htons(53)'
```

> **备注**: 目前大部分 Linux 发行版中, 由于 MAXNS 的限制, `/etc/resolv.conf` 中最多可以有 3 个 `nameserver`, 实际使用的时候我们也建议配置 3 个 nameserver. 云环境中, 可以设置两个云厂商的 dns 和一非云的 dns(比如 114.114.114.114).

## 修改 /etc/{resolv.conf,hosts} 不生效

通常情况下, 应用程序都会遵循 Linux 系统的规则(见 /etc/nsswitch.conf)来进行域名解析, 默认优先选择 `/etc/hosts`, 再进行 `dns server` 解析. 不过很多应用程序所依赖的网络库, 仅在启动的时候加载了一次 `/etc/hosts` 和 `/etc/resolv.conf` 配置. 

这种情况下, 在程序(尤其是静态编译的程序)运行的时候, 修改 `hosts` 或 `resolv.conf` 文件就不会生效, 只能通过重启程序使之生效. 比如上述的 `DNS Server 失效` 问题, 如果 `nameserver` 出现故障, 即便配置了多个 `nameserver` 进行轮询, 程序还是会使用失效的 server 进行解析. 

> **备注**: 解释型语言的程序一般在请求的时候大多都会重新访问 `/etc/resolv.conf` 文件.

在文章[Linux 系统如何处理名称解析]({{ site.baseurl }}/linux-%e7%b3%bb%e7%bb%9f%e5%a6%82%e4%bd%95%e5%a4%84%e7%90%86%e5%90%8d%e7%a7%b0%e8%a7%a3%e6%9e%90/)中, 我们提到了 `Centos 7` 在 `glibc-2.17.202` 版本中合并了自动检测 `resolv.conf` 修改的功能:
```
# rpm -q --changelog glibc-2.17-260
...
* Fri Sep 29 2017 Florian Weimer <fweimer@redhat.com> - 2.17-202
....
- Detect and apply /etc/resolv.conf changes in libresolv (#1432085)
```

这个功能可以让运行的程序获取到变化的 `nameserver`. 不过并不是所有编程语言或框架都支持此功能, 具体实现需要以实际的测试为准. 比如文章开头我们提到的 JDK, 默认缓存 30s, 通过 `strace` 工具也可以发现, JDK 也会定期的读取并加载 `/etc/resolv.conf` 中的配置, 该功能其实也是得益于 glibc 特性的支持.


另外一个值得一提的情况是有的网络库(比如 libevent)自己实现了 dns 的解析请求, 不依赖 glibc 的特性. 在程序运行的时候, 修改 `hosts/resolv.conf` 文件都不会生效. 

开头我们提到 libevent 提供了两种处理 dns 请求的方式:

```
1. blocking 方式;
2. non-blocking 方式;
```

两种方式的底层仅提供了基本的方法实现, 所以都是单线程的进行 dns 处理, 更高效的处理方式需要用户自己实现. 从官方文档来看, 如果需要使用第二种方式, `evdns_base_new` 函数需要注意以下信息:

```c
# interface
struct evdns_base *evdns_base_new(struct event_base *event_base,
       int initialize);

void evdns_base_free(struct evdns_base *base, int fail_requests);


note: The evdns_base_new() function returns a new evdns_base on success, and NULL on failure. If the initialize argument is 1, it tries to configure the DNS base sensibly given your operating system’s default. If it is 0, it leaves the evdns_base empty, with no nameservers or options configured.
```

函数 evdns_base_new 的第二个参数需要注意:

```
1. 当为 1 时, 该函数通过系统的配置来配置 dns 信息;
2. 当为 0 时, 需要我们手动设置 evdns_base 选项来配置 dns 信息;
```

第 2 个参数为 0 时, 可以设置的选项包括以下:

```c
#define DNS_OPTION_SEARCH 1
#define DNS_OPTION_NAMESERVERS 2
#define DNS_OPTION_MISC 4
#define DNS_OPTION_HOSTSFILE 8
#define DNS_OPTIONS_ALL 15

int evdns_base_resolv_conf_parse(struct evdns_base *base, int flags,
                                 const char *filename);
```

如果应用程序仅设置了 `DNS_OPTION_NAMESERVERS` 选项, 在程序启动后不会再监听加载 `/etc/hosts`, 仅和 `/etc/resolv.conf` 中的 dns server 交互. 这种情况下, 修改 hosts 文件程序程序就不会生效. 同样的, 在程序启动后即便修改 `/etc/resolv.conf`, `nameserver` 也不会生效.

所以, 如果想让程序可以生效, 应用程序在使用一些网络库的时候, 需要满足以下条件:
```
1. 查阅依赖的网络库是否遵循系统环境;
2. 尽量使用系统提供的标准函数;
3. 如果使用自定义函数, 需要明确其带来的风险, 准备一些补救措施;
```

## DNS 解析性能不足

这个问题通常发生于一些偏底层的应用程序, 比如 `C/C++` 程序, Linux 系统层(比如 glibc 等)通常仅提供标准的 api 函数, 并不会提供更高层面的封装实现(比如多线程解析, DNS 缓存等等). 

可以想象, 在没有多线程或 dns 缓存的情况下, 如果程序做了大量的 `http/https` 请求, 由于每个请求都需要做一次 dns 解析, 就会导致 dns 解析的性能瓶颈, 进而影响 `http/https` 的响应时间.

基于这个问题, 可以参考以下方案进行处理:
```
1. 引入支持多线程或 dns 缓存的三方库;
2. 自己实现对底层 api 的封装, 支持多线程或缓存;
3. 使用 glibc 提供的 nscd 组件, 加快 dns 的解析;
```

第一种方式, 比如 [cpp-netlib(基于 boost::asio)](https://cpp-netlib.org/), 程序在调用三方库的时候, 最好也验证一遍是否存在 `修改 /etc/{resolv.conf,hosts} 不生效` 的问题.

第二种方式对技术实力要求较高, 如果想避免 `修改 /etc/{resolv.conf,hosts} 不生效` 的问题, 实际上需要做很多的工作, 如果只是提高解析性能, 可以只考虑支持缓存的功能.

第三种方式则更为通用, 直接使用 glibc 提供的 nscd 组件来提高性能, 应用程序仅保证使用系统函数(`getaddrinfo()`)即可. nscd 相关的配置可以参考文章 [nscd-configure-sample]({{ site.baseurl }}/nscd-configure-sample/). 文章[Linux 系统如何处理名称解析]({{ site.baseurl }}/linux-%e7%b3%bb%e7%bb%9f%e5%a6%82%e4%bd%95%e5%a4%84%e7%90%86%e5%90%8d%e7%a7%b0%e8%a7%a3%e6%9e%90/)中也提到了 nscd 的工作机制. 

在实际的生产环境种, 我们建议采用第三种方式, 对应用程序的改动最小, 不需要程序自己实现 dns 缓存以及监听 hosts 文件的变化, 且修改 `/etc/resolv.conf` 也能很快生效. 即便使用了低版本 glibc(没有合并自动检测功能), nscd 也能很好的对修改的 nameserver 进行检测. 另外安全性和稳定性方面也都有保障. 比如以下 nscd 测试:

```c
// 禁用 nscd 时
Running benchmark
getaddrinfo: 1024/1024 successful lookups
getaddrinfo: 1.474190ms average per lookup

// 开启 nscd 时
Running benchmark
getaddrinfo: 1024/1024 successful lookups
getaddrinfo: 0.008714ms average per lookup
```

> 测试代码见: [getaddrinfo_bench.c](https://gist.github.com/arstercz/125d1f982f7c9dd772fc7f2bef3ddff6)

可以看到性能的提升还是很明显的, 原先 1s 只能解析约 678 次, 开启 nscd 后, 1s 可以解析约 114757 次.


## 总结

从上述的几个问题来看, 在出现 DNS 问题的时候, 修改 `hosts/resolv.conf` 文件对应用程序是否生效决定了我们的服务质量. 如果程序可以多活, 即便修改不生效, 也能通过逐次重启程序的方式减小 DNS 问题带来的影响. 如果程序单点不能重启, 则 DNS 问题只能越来越严重. 实际使用中, 多注意上述三类问题, 也就能避免大多数的 DNS 故障.
