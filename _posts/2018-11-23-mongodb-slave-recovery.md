---
layout: post
title: 简单记录 mongodb 主从模式的恢复过程
tags: [mongodb, slave]
coments: false
---

## 简单记录 mongodb 主从模式的恢复过程

mongodb 中 `repSet` 集群模式提供了很好的高可用架构, 不过很多情况下, 比如异地原因等我们还是会采用主从模式进行服务, 主从模式主要依靠 `oplog` 来进行数据的传输, 在做恢复或者新增加一个 slave 的时候就主要通过 `oplog` 进行进行增量同步. 下面则简单记录一个主从恢复的过程.

### 备份 mongodb 数据

```
mongodump  --host=master_host --port=master_port --oplog  --numParallelCollections=4 --out /data/mongo_data
```

### 在 slave 中恢复数据

在创建空的 mongodb 实例后, 可以恢复备份的 mongodb 数据:
```
mongorestore --host=slave_host --port=slave_port  --oplogReplay /data/mongo_data
```

通过 `bsondump` 找出 oplog 中最新的时间戳条目:

```
bsondump /data/mongo_data/oplog.bson | tail -n 1
{"ts":{"$timestamp":{"t":1542823142,"i":1}}....
```

保存最新的同步信息:
```
use local
db.sources.insert({ "host" : "master_host:master_port", "source" : "main", "syncedTo" : Timestamp(1542823142,1) })
```

重新启动新作的 slave 实例, 起来后 slave 就从备份的时间点开始同步增量数据:
```
./stop-mongo
./start --slave --source master_host:master_port --autoresync
```


> **备注**: 没有 `db.sources.insert` 操作, 重启 slave 后, 则从启动时的时间而不是备份的最后一个时间开始同步新增数据.
