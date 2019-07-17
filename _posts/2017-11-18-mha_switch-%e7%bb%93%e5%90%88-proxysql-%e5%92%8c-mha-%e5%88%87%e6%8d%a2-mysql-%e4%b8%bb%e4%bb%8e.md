---
id: 886
title: 'mha_switch: 结合 proxysql 和 MHA 切换 MySQL 主从'
date: 2017-11-18T13:45:23+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=886
permalink: '/mha_switch-%e7%bb%93%e5%90%88-proxysql-%e5%92%8c-mha-%e5%88%87%e6%8d%a2-mysql-%e4%b8%bb%e4%bb%8e/'
categories:
  - code
  - database
tags:
  - MHA
  - MySQL
  - proxysql
---
## mha_switch: 结合 proxysql 和 MHA 切换 MySQL 主从

在之前的文章[proxysql 介绍及测试使用](https://highdb.com/proxysql-%E4%BB%8B%E7%BB%8D%E5%8F%8A%E6%B5%8B%E8%AF%95%E4%BD%BF%E7%94%A8/)中, 详细介绍了 [proxysql](https://github.com/sysown/proxysql) 的安装配置等, 不过经过时间的推移, proxysql 工具做了很多的改进, [自动检测及状态切换](https://github.com/sysown/proxysql/blob/80bad8a811dc5ec28f30e29d9dffd21e355acfbf/doc/admin_tables.md#mysql_servers)等功能带给我们很大的便利, 可以取代传统的 haproxy 代理, 不过由于 proxysql 的检测和状态切换机制不是实时进行, 只是间接性检测, 所以会带来了另外的困扰, 如何与已有的工具如[MHA](https://github.com/yoshinorim/mha4mysql-manager)更好的结合以保证数据的一致性. 

## 功能介绍

[mha_switch](https://github.com/arstercz/mha_switch) 通过在自定义的脚本中加入 proxysql 检测和切换的功能比较方便的实现了 MHA 和 proxysql 之间的配合使用. `mha_switch` 主要实现以下功能:

```
解析 masterha-script.cnf 的实例配置信息;
切换 vip 信息(可选, 如果实例通过 vip 对外服务);
block/release 数据库用户;
prxoysql 切换;
```

## 配置说明

自定义脚本读取 `masterha-script.cnf` 文件获取主从实例和 proxysql 的配置信息, 如下所示:
```
10.0.21.7:3308 10.0.21.17:3308
   vip 10.0.21.97   
   block_user ^percona$|^proxysqlmon$
   block_host ^10\.0\.21\.%$
   proxysql admin2:admin2@10.0.21.5:6032:w1:r2,admin2:admin2@10.0.21.7:6032:w1:r2
```

`10.0.21.7:3308 10.0.21.17:3308` 是主从的 ip:port 信息, 如果有一主多从, 所有的 ip:port 都需要写到这里; `vip 10.0.21.97` 表示 master 以 vip 形式对外服务, MHA 在切换的时候也会将 vip 切到新的 master 中, 这种方式只需要程序有重连机制即可, 不需要每次切换的时候都要改一遍程序的数据库连接配置; `block_user` 和 `blcok_host` 是需要对老 master 中进行密码反转的用户信息, 反转密码是很方便且有效的方式, 杜绝切换的时候新的连接进来, 为数据一致性加了一层防护; `proxysql` 是主从前面的 proysql 信息, 多个 proxysql 以逗号分开, 上面的意思大致为: 以用户名 `admin2`, 密码 `admin2` 连接 proxysql(10.0.21.5:6032), 该实例对应的写组是1, 读组是 2, MHA 切换的时候会对这两个组进行操作.

## 如何使用

[How to use](https://github.com/arstercz/mha_switch#how-to-use) 说明了如何使用. 不过需要注意以下几点:
```
1. 如果要切换的 master 是存活状态, 即 --master_state=alive, 可以指定 --orig_master_is_new_slave 选项自动 change master, 不过该功能需要 MHA 0.56 版本;
2. 如果要切换的 master 是非活状态, 即 --master_state=dead, 则 MHA 直接调用 master_ip_failover 脚本, 不对对 proxysql 进行 readonly 操作;
3. 如果对 proxysql 做了主备部署或多点部署, 需要在 masterha-script.cnf 配置中增加所有的 proxysql 信息, 以逗号分隔开;
4. 脚本在更新 proxysql 的时候, 删除了相关的复制组, 禁止了 proxysql 的自动更新;
```

## 其它问题

#### 反转密码问题

为了支持 `--orig_master_is_new_slave`, 对老的 master 增加了密码转回过程, 该过程放到了`stop vip` 过程之后(没有 vip 则在 kill 所有连接的线程之后) , 所以从这点看, 如果主从没有使用 vip, 转回密码后可能还是有程序连接进来, 不过已经设置了 read_only, 不会接受写操作.

#### proxysql 监控 read_only 变量自动识别主从, 为什么还要在 MHA 中操作

proxysql 是间接性检测 read_only 变量, 并不是实时检测, `monitor_read_only_interval` 参数指定检查 `read_only` 的时间间隔, 单位毫秒. 稍微有点量的MySQL实例, 一秒就能有好几千的qps 操作, 从这方面来看 `proxysql` 自身的 `read_only` 检查我觉得是会遗漏一些更新的, 比如已经切换的主, 这时候老的主就是 master, proxysql 还没检查到 read_only 变更, 就会把 sql 转发到老的主, 这个时候程序就会报 `read only` 相关的错误. 当然这种情况只是出现一些更新错误, 程序如果有机制补数据的话就没什么大的问题. 另外我个人觉得 `proxysql` 的 `read_only` 检测机制更适合主挂掉, 从成为新的主的情况, 并不适合主从互相切换的场景.
