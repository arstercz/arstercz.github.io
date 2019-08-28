---
layout: post
title: "radon 工具使用及问题汇总"
tags: [hash, mysql]
comments: false
---

[radon](https://github.com/radondb/radon) 工具作为 MySQL 的中间件对外提供服务, 其以 [jump consistent hash](https://arxiv.org/ftp/arxiv/papers/1406/1406.2294.pdf) 算法实现了扩展 MySQL 读写的目的. 业务所常用的 sql 语法都做了相应的支持, 比如 `DDL`, `SHOW`, `Full Text Search`, `JOIN` 以及聚合排序等, 详细 sql 支持见 [radon_sql_support](https://github.com/radondb/radon/blob/master/docs/radon_sql_support.md). 同时 radon 也提供了 [api](https://github.com/radondb/radon/blob/master/docs/api.md) 接口方便管理员进行配置状态的管理, 故障的诊断以及监控数据的收集.

下述的问题列表则主要介绍在使用 radon 的过程中可能碰到的疑问和问题, 一些问题 radon 开发者修复即可, 一些问题则需要在业务层调整做更多的支持. 更权威的则需要关注 [radon-issue](https://github.com/radondb/radon/issues) 列表以确定具体问题的解决方式. 后期碰到的问题也会在该列表中持续更新.

### 问题列表

* 关键字问题
* 权限放大问题
* 事务问题
* 压测问题
* 适用场景问题
* 列名问题
* 唯一性问题
* jump consistent hash 介绍
* 分区原理说明
* hash 函数问题
* 灵活性问题

## 关键字问题

下面的 keywords 条目限制了一部分 sql, 执行的 sql 需要把关键之反引起来才可以. 
```go
// github.com/xelabs/go-mysqlstack/sqlparser/token.go
62 var keywords = map[string]int{...
```
如下所示
```
mysql admin@[dbt:3308 db_test rw] > insert into user_test(user_id, app_id, status, descmsg, create_time) values(1223, 10021, 1, 'one insert test', now()); 
ERROR 1149 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use, syntax error at position 46 near 'status'

mysql admin@[dbt:3308 db_test rw] > insert into user_test(user_id, app_id, `status`, descmsg, create_time) values(1225, 10020, 1, 'two insert test', now()); 
Query OK, 1 row affected (0.00 sec)
```

## 权限放大问题

通过 api 接口创建的用户权限太大, 如下所示, 正式使用的时候希望限制权限, 接口可以增加 host 和 privileges 选项，默认应该仅开启增删改查的权限. 如果程序不做修改, 可以手工在后端的所有节点创建相同权限的普通用户.
```go
//ctl/v1/user.go
37 func createUserHandler(log *xlog.Log, proxy *proxy.Proxy, w rest.ResponseWriter, r *rest.Request) {
38         spanner := proxy.Spanner()
...
60         for _, db := range dbList {
61                 query := fmt.Sprintf("GRANT ALL ON %s.* TO '%s'@'%%' IDENTIFIED BY '%s'", db, p.User, p.Password)
62                 if _, err := spanner.ExecuteScatter(query); err != nil {
...
```

## 事务问题

未支持 `autocommit = 0` 当作开启一个事务, 同类的很多工具都有此问题, 详细见 [proxysql-issue1256](https://github.com/sysown/proxysql/issues/1256).


## 压测问题

通过 benchyou 创建2个表(32张子表), 单台机器 seq 查询 8w qps, 通过 radon 代理三台DB可以达到 11w 左右, 写扩展较好, 读扩展则受 radon 所在机器的性能, 如果为了提高读可通过 peer 方式创建多个 radon 节点, 应用程序可以通过 dns 或 haproxy 等方式连接.

## 适用场景问题

从大的方面来看, 只要数据在不同的节点, 就肯定面临下面的几个问题:
```
1. shard 只能按照一个维护拆分, 通过其它维度查询的时候必须要做全表扫描;
2. 如果表中包含多个唯一键, 则需要业务层做更多的保障;
3. 在有唯一性要求的业务中(比如用户名, 手机号等), 后端有一个节点出现故障, 业务层就需要降级, 因为不能保证唯一性;
```
可以通过缓存来缓解这几个问题, 但很难做到缓存与数据的一致性. 这几个问题就意味着一些单节点的接口请求性能要优于 shard 分区的方式, 所以一般对于用户中心这类业务, 应当尽量先按照功能进行拆分, 功能难以细分的时候再考虑水平切分. 另外对于一些单一的查询, 比如只按用户 id 做更新或查找的接口通过 shard 分区方式就能得到很好的扩展, 比如记录用户 token 和登录日志类的业务就很适合. radon 工具在后端有一个节点出现问题的时候则进入降级状态, 这时候不允许应用做查询或更新操作. 这种方式简洁明了, 不过对于单一接口的业务不够友好.

## 列名问题

插入的时候必须指定列名, 且包含 shardkey, 如下所示:
```sql
mysql admin@[dbt:3308 db_test] > insert into user values(1233, 'arster', now());
ERROR 1105 (HY000): unsupported: shardkey.column[user_id].missing
mysql admin@[dbt:3308 db_test] > insert into user(user_id, name, create_time) values(1233, 'arster', now());
Query OK, 1 row affected (0.00 sec)
```

## 唯一性问题

可以通过 radon 创建带多个唯一键的表, 不过不能保证所有的子表的唯一键的唯一性, 需要在业务曾对唯一需求做额外的处理.

## jump consistent hash 介绍

[jump consisten hash](https://arxiv.org/ftp/arxiv/papers/1406/1406.2294.pdf) 哈希算法适合在分 shard 的分布式系统中, 具备均匀分配, 快速计算, 低消耗等特性. 具体的算法为输入一个 64位的 key 和桶的数量, 最后输出桶的编号. 其设计目标包含以下两点:

```
1. 平衡性, 把对象均匀分布到所有桶中;
2. 单调性, 在桶的数量变化时, 仅需移动一些对象到新桶, 不需要做其它的移动;
```

不像割环法，jump consistent hash不需要对 key 做 hash，这是由于 jump consistent hash 使用内置的伪随机数生成器，来对每一次 key 做 hash, 如下所示, key 可以为整形或字符串类型, 如果有浮点类型的 key, 需要转成响应的整形表示形式:

```go
func Hash(key uint64, buckets int32) int32 {
	var b, j int64

	if buckets <= 0 {
		buckets = 1
	}

	for j < int64(buckets) {
		b = j
		key = key*2862933555777941757 + 1
		j = int64(float64(b+1) * (float64(int64(1)<<31) / float64((key>>33)+1)))
	}

	return int32(b)
}

func HashString(key string, buckets int32, h KeyHasher) int32 {
	h.Reset()
	_, err := io.WriteString(h, key)
	if err != nil {
		panic(err)
	}
	return Hash(h.Sum64(), buckets)
}
```

## 分区原理说明

从 `src/router/hash.go` 源文件中可以看到, radon 采用了 jump consistent hash 算法实现了 shard 操作. 对给定的 key 算出具体的桶编号. 
从 `src/router/compute.go` 和 `src/backend/scatter.go` 可以看出实际的 backends 仅和 配置文件 `backend.json` 中每个条目的 name 
字段关联, radon 通过 backend 的数量来计算每个节点所拥有的桶的范围, 每个 key 通过 jump consistent hash 算法得到桶的编号, 进而到对应的
backend 节点进行操作.

另外桶的数量可以通过以下参数进行调整:
```
"router": {
     "slots-readonly": xxx,    # 桶的数量
     "blocks-readonly": xxx    # 每个节点每个子表拥有的桶数
}
```

## hash 函数问题

在 key 为字符串的时候, 通过 `jump consistent hash` 的 HashString 方法中采用了 `jump.CRC64` 作为 KeyHasher 参数的值, 不过 `jump.CRC64` 
在并发环境中存在安全隐患, 需要改为官方建议的 `NewCRC64` 方法
```go
// src/router/hash.go
163 // GetIndex returns index based on sqlval.
164 func (h *Hash) GetIndex(sqlval *sqlparser.SQLVal) (int, error) {
	......
180         case sqlparser.StrVal:
181                 idx = int(jump.HashString(valStr, int32(h.slots), jump.CRC64))
    ......
```

更多见 [go-jump-consistent-hash-issue6](https://github.com/lithammer/go-jump-consistent-hash/issues/6)


## 故障恢复

从分区原理来看, 对可用性要求高的工程, radon 可以采用 vip 或 dns 的方式连接后端的每个 master. 对可以容忍中断一段时间的工程, radon 可以直接连接后端的每个 `master ip`, 在一个后端 master 节点出现故障的时候, 可以手动修改 `radon-meta` 目录中的 `backend.json` 元信息, 不过不能修改 name 字段, 最后重启 radon 进程即可, 如果是通过 peer 配置的多 radon 节点, 则稍微麻烦些, 不过处理的方式都一样.


## 灵活性问题

目前来看仅支持按 `jump consistent hash` 方式进行 shard 分区, 如果已有的工程是按照范围或者一致性 hash 割环方式分区, 需要单独修改 `src/router/hash.go` 中的
方法以适应已有的工程.

另外每个表的元信息可以做单独的修改, 比如已有的工程仅分了两个库, 每个库都有一个 user 表, 如果也是按照 jump consistent hash 方式进行的分区, 可以直接修改
radon 中表的元信息以适应操作:
```
# less db_test/user.json 
{
        "name": "user",
        "slots-readonly": 4096,
        "blocks-readonly": 2048,
        "shardtype": "HASH",
        "shardkey": "user_id",
        "partitions": [
                {
                        "table": "user",
                        "segment": "0-2048",
                        "backend": "db1"
                },
                {
                        "table": "user",
                        "segment": "2048-4096",
                        "backend": "db2"
                }
        ]
}
```
