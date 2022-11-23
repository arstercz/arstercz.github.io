---
layout: post
title: "tcp 长连接保活注意点"
tags: [tcp keepalive]
comments: true
---

tcp 长连接一直是提升系统性能的重要手段. 不过在复杂网络或者请求很少的时候, 也会通过保活等方式维持连接的建立. 保活可以用来探测连接, 进而可能释放掉已经无效的连接. 在一些跨网以及含有硬防的网络环境中, 一些网络设置可能默认会 kill 掉长时间空闲的 tcp 会话, 这种情况下 tcp 连接的保活就显得更为重要. 本文则记录了 tcp 连接保活的几点事项.

* [保活的方式](#保活的方式)  
* [问题汇总](#问题汇总)  
* [参考](#参考)  

## 保活的方式

通常包含`系统层`和`应用层`两种保活方式.

### 系统层

系统层主要是 `tcp keepalive` 方式, 在 socket 层开启 `SO_KEEPALIVE` 选项, 主要有以下实现方式:
```
1. 框架实现      - 部分框架的网络库可能默认开启;
2. socket 自定义 - 可以自定义保活的时间间隔以及探活次数;
3. linux 系统    - 程序的 socket 需开启 SO_KEEPALIVE 选项, 开启后遵循系统设置;
```

> 备注: 较新版本的 golang, 默认就开启了 tcp keepalive, 且每 15s 保活一次. 更多见: [golang-issue-48622](https://github.com/golang/go/issues/48622).

### 应用层

应用层的保活建立在该连接可以定期请求回复的基础上, 比如很多语言将 `select 1` 作为 MySQL 的保活查询语句. 但是单个请求的执行时间很长, 则不能在应用层保活. 比如 `select sleep(3000)`, 在 SQL 执行完之前, 同一连接是不会有其它数据交互的,  如果网络层有会话超时限制, 该连接就会被 kill.

## 问题汇总

### 硬防注意事项

硬防如果直接删掉 tcp 的会话, 对应的 client 或 server 段可能不会收到 FIN 报文, 其相应的 tcp 连接状态就不会变. 这也是我们可能会碰到下面场景的原因之一:

```
1. server 端  tcp 连接还是  ESTABLISHED, 但是 client 没有 tcp 连接;
2. client, server 端的 tcp 连接都是 ESTABLISHED，但是数据交互超时;
```

### tcp keepalive 怎么实现

系统层保活是一种在不影响数据流内容的情况下探测对方的方式. 探测报文是一个空的数据包(或只包含一个字节). 它的序列号等于对方主机发送的 ACK 报文的最大序列号减 1. 因为这一序列号的数据段已经被成功接收, 所以不会对到达的报文段产生影响, 但探测返回的响应可以确定连接是否正常.

可以自行 tcpdump 抓包, 关注 `TCP Keep-Alive` 报文的详细格式.

### tcp keepalive 可能不生效

这点可能经常出现在 web 环境中, 比如下面的结构:
```
  nginx(DC1)    ->  tomcat(DC1) -> nginx(DC2) -> tomcat(DC2)
```

如果在 `nginx(DC1)` 开启 tcp 的 keepalive(`proxy_socket_keepalive`) 特性, 在上述的流程中, tcp 的保活仅能在 DC1 的流程中. tomcat(DC1) 本身只转发 http 等应用层数据, 所以 DC2 的组件并不会收到 tcp 层的数据包. 如果是应用层开启保活, 比如 tomcat(DC1) 以下面的方式开启保活,  DC2 的 nginx 就能正常收到保活请求:
```
CloseableHttpClient httpClient = HttpClients.createDefault()
HttpParams params = httpClient.getParams();
HttpConnectionParams.setConnectionTimeout(params, 3600000); //connection Timeout
HttpConnectionParams.setSoTimeout(params, 3600000); // Socket Time out
HttpConnectionParams.setSoKeepalive(params, true); //Enable Socket level keep alive time
```

### tcp keepalive 哪边来实现

同样以上述流程为例, 系统层的保活既可以在 `tomcat(DC1)`, 也可以在 `tomcat(DC2)` 层实现. 等同保活可以在 client 或 server 端实现. 分别说明如下:
```
1. client 端实现, 则由 client 端发空包到 server 端, server 端响应;
2. server 端实现, 则由 server 端发空包到 client 端, client 端响应;
```

> 通常 server 端实现更多, 哪边实现可以由具体的架构决定.

### linux 系统参数

系统层主要受以下三个系统参数的影响:
```
net.ipv4.tcp_keepalive_time   - tcp 连接闲置的时长, 从该连接最后一个报文的时间算起, 默认 2 小时(7200 秒);
net.ipv4.tcp_keepalive_intvl  - tcp 探测包的发送间隔, 默认 75 秒;
net.ipv4.tcp_keepalive_probes - 如果对方不应答, 探测包的发送次数, 默认 9 次;
```

默认为 tcp 连接空闲超过 2 小时则开始发送探测包, 在负责网络环境中可以调低 `net.ipv4.tcp_keepalive_time` 的值.

## 参考

[linux-keepalive-howto](https://tldp.org/HOWTO/html_single/TCP-Keepalive-HOWTO/)  
