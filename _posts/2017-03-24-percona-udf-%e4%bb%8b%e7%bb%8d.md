---
id: 795
title: percona UDF 介绍
date: 2017-03-24T18:25:15+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=795
permalink: '/percona-udf-%e4%bb%8b%e7%bb%8d/'
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - code
  - database
  - percona
tags:
  - fnv
  - murmur
  - percona
  - udf
---
<h2>简介</h2>

在较新的 percona 分之版本中, 其提供了三个自定义的哈希函数, 分别为 fnv_64, fnv1a_64 和 murmur_hash, 这三个函数可以提供更快速度和更小碰撞率的哈希计算, 从这点看可以用来替换 md5, crc32 等函数, 而且由于速度快、碰撞率小的特性, 这些函数也可以作为一致性哈希函数来使用.  如何安装这三个函数详见 <a href="https://www.percona.com/doc/percona-server/5.7/management/udf_percona_toolkit.html">udf_percona_toolkit</a>.

<h2>函数介绍</h2>

大致了解这三个函数后, 再来简单说明这三个函数的相关实现.

<h3>fnv 哈希算法</h3>

FNV哈希算法最早在1991年提出, 是 Fowler-Noll-Vo 的简写，其以三位发明人Glenn Fowler，Landon Curt Noll，Phong Vo的名字来命名的. 另外现今很多流行的中间件或分布式工具都有该函数的申请, 比如 <a href="https://github.com/twitter/twemproxy">twemproxy</a> 等工具.

FNV能快速hash大量数据并保持较小的冲突率，它的高度分散使它适用于hash一些非常相近的字符串，比如URL，hostname，文件名，text，IP地址等. 现有的版本有 FNV-1 和 FNV-1a, FNV-0 已经废弃, FNV-1 和 FNV-1a 两个函数生成的 hash 值有以下两个限制(FNV offset basis 为无符号整数):

<pre><code>无符号整型;
hash 值的位数为 2^n (32, 64, 128, 256, 512, 1024 等)
</code></pre>

FNV-1 函数伪代码:

<pre><code>   hash = FNV_offset_basis
   for each byte_of_data to be hashed
        hash = hash × FNV_prime
        hash = hash XOR byte_of_data
   return hash
</code></pre>

FNV-1a函数伪代码:

<pre><code>   hash = FNV_offset_basis
   for each byte_of_data to be hashed
        hash = hash XOR byte_of_data
        hash = hash × FNV_prime
   return hash
</code></pre>

变量说明:

<pre><code>FNV_offset_basis: 初始的哈希值;
FNV_prime: FNV用于散列的质数;
byte_of_data: 8位数据（即一个字节）;
for each: 指定值的每个字节;
</code></pre>

FNV_prime 的取值:

<pre><code>32 bit FNV_prime = 2^24 + 2^8 + 0x93 = 16777619
64 bit FNV_prime = 2^40 + 2^8 + 0xb3 = 1099511628211
128 bit FNV_prime = 2^88 + 2^8 + 0x3b = 309485009821345068724781371
256 bit FNV_prime = 2^168 + 2^8 + 0x63 =374144419156711147060143317175368453031918731002211
512 bit FNV_prime = 2^344 + 2^8 + 0x57 = 35835915874844867368919076489095108449946327955754392558399825615420669938882575126094039892345713852759
1024 bit FNV_prime = 2^680 + 2^8 + 0x8d = 
5016456510113118655434598811035278955030765345404790744303017523831112055108147451509157692220295382716162651878526895249385292291816524375083746691371804094271873160484737966720260389217684476157468082573
</code></pre>

offset_basis 的取值:

<pre><code>32 bit offset_basis = 2166136261
64 bit offset_basis = 14695981039346656037
128 bit offset_basis = 144066263297769815596495629667062367629
256 bit offset_basis = 100029257958052580907070968620625704837092796014241193945225284501741471925557
512 bit offset_basis = 9659303129496669498009435400716310466090418745672637896108374329434462657994582932197716438449813051892206539805784495328239340083876191928701583869517785
1024 bit offset_basis = 14197795064947621068722070641403218320880622795441933960878474914617582723252296
732303717722150864096521202355549365628174669108571814760471015076148029755969804077320157692458563003215304957150157403644460363550505412711285966361610267868082893823963790439336411086884584107735010676915
</code></pre>

我们以 fnv1a 函数的代码实现为例, 详见: <a href="https://github.com/percona/percona-server/blob/1e2f003a5bd48763c27e37542d97cd8f59d98eaa/plugin/percona-udf/fnv1a_udf.cc">fnv1a_udf.cc</a> :

<pre><code>#define FNV1A_64_INIT 0xcbf29ce484222325ULL
#define HASH_NULL_DEFAULT 0x0a0b0c0d
#define FNV_64_PRIME 0x100000001b3ULL

</code></pre>

这里的初始值(offset_basis) 和 prime 值刚好对应上述介绍的 64位值信息.

<h3>murmur 哈希函数</h3>

murmur 是一种非加密型哈希函数，由 Austin Appleby 于 2008 年发明. 该函数适用于一般的哈希检索操作, 与其它流行的哈希函数相比，对于规律性较强的key，MurmurHash的随机分布特征表现更良好. 详见: <a href="https://en.wikipedia.org/wiki/MurmurHash">murmurhash</a>, 目前被作为一致性哈希函数被广泛使用, hadoop, cassandra, lucene, redis 等这些工具都有该函数的支持.

现有的版本有 MurmurHash3, MurmurHash2. percona udf 则实现了 MurmurHash2 函数, 支持64位, 但是存在以下限制, 详见<a href="https://github.com/percona/percona-server/blob/1e2f003a5bd48763c27e37542d97cd8f59d98eaa/plugin/percona-udf/murmur_udf.cc">murmur_udf.cc</a>:

<pre><code>This code makes a few assumptions about how your machine behaves -
  1. We can read a 4-byte value from any address without crashing
  2. sizeof(int) == 4

And it has a few limitations:
  1. It will not work incrementally.
  2. It will not produce the same results on little-endian and big-endian machines.
</code></pre>

这里的 incrementally 即是分步的意思, 比如这样的场景, 有一个大的数据包, 可以分开计算哈希值, 最后再拼到一起, 详见: <a href="https://www.nsnam.org/docs/manual/html/hash-functions.html#incremental-hashing">incremental-hashing</a>

后面一个限制为网络字节序的问题, 大端和小端机器混用的场景下可能会引起计算的哈希值不同.

<h2>如何使用</h2>

三个自定义函数 fnv_64, fnv1a_64 和 murmur_hash 都有一个相同的问题, 函数本身返回无符号整型, 但是 mysql 自定义函数必须是有符号的整型<a href="https://dev.mysql.com/doc/refman/5.6/en/create-function-udf.html">create-function-udf</a>，所以如果单独使用函数则整个结果就会转换为有符号整型, 我们以 <a href="https://github.com/percona/percona-server/blob/1e2f003a5bd48763c27e37542d97cd8f59d98eaa/plugin/percona-udf/murmur_udf.cc">murmur_udf.cc</a> 代码注释为例说明:

<pre><code>This file implements a 64-bit FNV-1a hash UDF (user-defined function) for
MySQL.  The function accepts any number of arguments and returns a 64-bit
unsigned integer.  MySQL actually interprets the result as a signed integer,
but you should ignore that.  I chose not to return the number as a
hexadecimal string because using an integer makes it possible to use it
efficiently with BIT_XOR().
</code></pre>

举例如下, 单独运行被转为有符号整型负数, 不过代码注释中同样给了解决的方法, 使用 CAST 函数转为无符号整型即可.

<pre><code> mysql&gt; SELECT MURMUR_HASH(12346);
+----------------------+
| MURMUR_HASH(12346)   |
+----------------------+
| -5394085343816506324 |
+----------------------+
1 row in set (0.00 sec)


#Here's a way to reduce an entire table to a single order-independent hash:

 mysql&gt; SELECT BIT_XOR(CAST(MURMUR_HASH(12346) AS UNSIGNED));
+-----------------------------------------------+
| BIT_XOR(CAST(MURMUR_HASH(12346) AS UNSIGNED)) |
+-----------------------------------------------+
|                          13052658729893045292 |
+-----------------------------------------------+
1 row in set (0.01 sec)
</code></pre>

其它两个 fnv 函数可以参考同样的方式处理.

<h2>总结</h2>

三个函数都能以较快的速度, 较小的碰撞率来计算哈希值, 可以作为 md5, crc32 等函数的替代; murmur_hash 函数可以作为一致性哈希函数用于分布式业务中, 也可以用于分库分表等业务逻辑中, 以减少数据量增长带来的应用架构和数据迁移方面的成本, 详见:  <a href="http://www.allthingsdistributed.com/2007/10/amazons_dynamo.html">amazon dynamo</a>