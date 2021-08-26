---
layout: post
title: "MySQL 命令无法输入中文问题处理"
tags: [mysql]
comments: true
---

近期通过 mysql 命令连接 mysql server 的时候, 出现了不能输入中文的现象, 如下所示, 在交互模式中输入 `SELECT '<汉字>'` 后, 出现以下情况:
```sql
mysql> SELECT '<>';
+----+
| <> |
+----+
| <> |
+----+
1 row in set (0.00 sec)
```
输入的所有中文都会被替换为空. 上述测试为官方的 `mysql-5.7.32` 版本. 

遍历官方 mysql 的 [changelog-5.7.34](https://docs.oracle.com/cd/E17952_01/mysql-5.7-relnotes-en/news-5-7-34.html) 发现了 oracle 官方的 `mysql-5.7.34` 和 `mysql-8.0.24` 分别修复了以下 bug
```
For builds compiled using the libedit library, if the mysql client was invoked 
with the --default-character-set=utf8 option, libedit rejected input of 
multibyte characters. (Bug #32329078, Bug #32583436, Bug #102806)
```

参考 [bug-102806](https://bugs.mysql.com/bug.php?id=102806), 出现和描述中类似的事情, mysql 命令行的交互模式不支持所有宽字符的输入. 早期也同样出现过类似的情况, 详见 [bug-76324](https://bugs.mysql.com/bug.php?id=76324).

## 不能输入中文会出现什么问题?

从测试来看, `该 bug 只影响通过 mysql 命令以交互模式连接 mysql server 的会话操作`. 如果线上有使用此 bug 的版本, 操作表的时候可能会出现丢失中文的问题.

以下方式不受影响:
```
1. 各程序通过相关驱动连接数据库;
2. mysql 命令以非交互模式操作, 比如 mysql -h ... -p.... < /tmp/t.sql
```

## 哪些版本受影响

该 bug 在 5.7.34 和 8.0.24 中修复, 见 [github-mysql-patch-117fb2](https://github.com/mysql/mysql-server/commit/117fb22aaddbf916f81fad1d7eab7995a4a28601). 从修复的补丁来看, bug 与 libedit 版本没有关系, 不管是 rpm, deb 还是官方的 build 版本都受此影响.

从我们的测试来看, 以下版本都会受到影响:
```
5.7.31 ~ 5.7.33
8.0.21 ~ 8.0.23
```

> **备注:** 其它发行版暂不明确, 大概率也会出同样的问题, 不过发行版通常比官方的慢一拍, 其低版本可能会提前修复该问题.


## 如何处理

线上的版本的选择可以集中在使用过的一些版本, 比如笔者常用的:
```
// percona 分支版本
percona-5.6.45
percona-5.7.28
percona-8.0.22

// 官方版本
mysql-5.6.29
mysql-5.7.28
mysql-8.0.19
```

如果线上已经使用了上述受影响的版本, 可以采用以下方式处理:

#### 临时处理

不方便升级的话, 可以先使用 5.7.30 以下或 5.7.34 及以上版本的 mysql client 命令;

#### 小版本升级

如果方便进行小版本升级, 建议升级到以下版本:
```
5.7.35
8.0.26
```
