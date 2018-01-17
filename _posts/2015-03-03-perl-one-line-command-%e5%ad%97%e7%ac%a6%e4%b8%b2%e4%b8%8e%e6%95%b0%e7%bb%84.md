---
id: 500
title: 'Perl one line command &#8211; 字符串与数组'
date: 2015-03-03T15:19:29+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=500
permalink: '/perl-one-line-command-%e5%ad%97%e7%ac%a6%e4%b8%b2%e4%b8%8e%e6%95%b0%e7%bb%84/'
dsq_thread_id:
  - "3562804565"
dsq_needs_sync:
  - "1"
categories:
  - code
  - performance
tags:
  - performance
  - perl
---
Perl one line command - 字符串与数组

本章使用 Perl 命令行说明如何创建字符串和数组, 包括生成密码, 创建指定长度字符串, 查找字符串中的数值等, 也会介绍一些特殊变量比如 $, 和 @ARGV 等, 同样以示例说明.

<strong>1. 生成并打印字符</strong>
<pre>
# perl -le 'print a..z'
abcdefghijklmnopqrstuvwxyz
</pre>
在 Perl 中 .. 是范围操作符， 在列表环境中, 上述命令表示打印从 a 到 z 的字母, 也可以使用 $, 和 join 来指定字母之间的分隔符:
<pre>
# perl -le  'print join ", ",(a..z)'
a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
# perl -le  '$, = ", ";print (a..z)'
a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
</pre>

<!--more-->



不过对于下面示例, 在生成 z 之后, 会继续生成 aa, ab 直到 zz, 也可以指定 aa .. zz 生成 aa 到 zz 之间的字符:
<pre>
perl -le  'print join ", ",(a..zz)'
perl -le  'print join ", ",(aa..zz)'
</pre>
避免 strict 模块引起的问题, 字符用双引号引起来是更稳妥的做法, 比如:
<pre>
# perl -le 'print "a".."z"'
abcdefghijklmnopqrstuvwxyz
</pre>

<strong>2. 十六进制</strong>
<pre>
# perl -le 'print join ", ",(0..9, "a".."f")'
0, 1, 2, 3, 4, 5, 6, 7, 8, 9, a, b, c, d, e, f
</pre>
(0..9, "a".."f") 组成了一个大列表， 包含 0 到 f 字符, 对应了十六进制的字符, 如果要将 10 进制转为 16 进制， 可以如下操作:
<pre>
# perl -le '$num = 255; @hex = (0..9, "a".."f"); while($num) { $s = $hex[($num % 16)] . $s; $num = int $num/16 } print $s'
ff
</pre>
$num % 16 的结果作为 @hex 数组的下标, 得到对应的十六进制字符, 如果用 printf 函数, 则更方便:
<pre>
# perl -le 'printf("%x\n", 255)'
ff
</pre>
使用 hex 函数可以很方便的将十六进制转为十进制:
<pre>
# perl -le '$num = "ff", print hex($num)'
255
</pre>

<strong>3. 生成指定长字符串</strong>
先回到 介绍 一章中, 之前有写过生成 8 位随机的字母密码串, 如下:
<pre>
perl -le 'print map { ("a".."z")[rand 26] }1..8'
</pre>
("a".."z")[rand 26] 会执行 8 次, rand 26 随机生成 0 ~ 25之间的数字, 作为 ("a".."z")列表的下表, 最后打印出来 8 位长度的字符串.
类似的, 我们可以使用 x 操作符重复执行多少字, 比如生成 50 个 a: 
<pre>
# perl -le 'print "a"x50'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
</pre>
"a"x50 属于字符拼接, 并不是列表环境, 不用使用 $, 等特殊符指定分隔符. 当然 -l 参数增加了换行, 如果要严格输出指定的长度, 需要去掉 -l 参数.

<strong>4. 数组</strong>

可以使用 split 函数分割字符串, 返回需要的数组, 比如以下:
<pre>
perl -le '@month = split " ", "Jan Feb Mar Apr ... Dec"'
</pre>
数组下表 0 ~ 11 分别对应月份.也可以使用 qw/STRING/ 生成数组:
<pre>
pelr -le '@month = qw/Jan Feb Mar Apr ... Dec/'
</pre>

<strong>5. 命令行参数</strong>
<pre>
# perl -le 'print "(", (join ",", @ARGV,),")"' v1 v2 v3
(v1,v2,v3)
</pre>
@ARGV 包含所有的参数信息, $ARGV[0] 对应 v1, $ARGV[1] 对应 v2 , 基于这个特性, 可以生成一些 sql, 比如:
<pre>
# perl -le 'print "insert into t values(" . (join ",", @ARGV) .");"' v1 v2 v3
insert into t values(v1,v2,v3);
</pre>

<strong>6. ascii码值和字符串</strong>
使用 ord 函数可以得到字符对应的 ascii 码值, 如下所示, 将字符串分为单个字符后使用 ord 进行转换:
<pre>
# perl -le 'print join ", ", map { ord } split //, "hello"'
104, 101, 108, 108, 111
</pre>
也可以使用 unpack 进行转换, 如下:
<pre>
# perl -le 'print join ", ", unpack("C*", "hello")'
104, 101, 108, 108, 111
</pre>
C 表示 unsigned character, * 表示"hello"中的所有字符. 使用 sprintf 函数转为16进制:
<pre>
# perl -le 'print join ", ", map{ sprintf "0x%x", ord $_ } split //, "hello"'
0x68, 0x65, 0x6c, 0x6c, 0x6f
</pre>

根据上面的示例, 可以进行 ascii 码值转为字符串, 比如使用 unpack 对应的 pack 函数:
<pre>
# perl -le 'print pack("C*", (104, 101, 108, 108, 111))'
hello
</pre>
也可以使用 chr 函数:
<pre>
# perl -le 'print join "", map chr, (104, 101, 108, 108, 111)'
hello
</pre>
map chr, (104, 101, 108, 108, 111) 等同 map { chr } (104, 101, 108, 108, 111)

<strong>7. 生成基数组成的数组</strong>
<pre>
# perl -le '$, = ", "; print @odd = grep { $_ % 2 == 1 } 1..100'
# perl -le '$, = ", "; print @odd = grep { $_ & 1 } 1..100'
</pre>
两条命令等效, 都使用 grep 函数过滤满足条件的元素, 前者使用取模余 1 的方法, 后者采用按位与的方法, 奇数的二进制最后一位肯定为 1， 则 $_ 为奇数时, $_ & 1 条件为真.

<strong>8. 计算字符串长度</strong>
<pre>
# perl -le 'print length "hello"'
5
</pre>
使用 length 函数返回字符串的长度.

<strong>9. 数组元素个数</strong>
可以使用数组下标和标量环境的方式得到数组元素的个数:
<pre>
# perl -le '@array = ("a".."z"); print scalar @array'
26
# perl -le '@array = ("a".."z"); print $#array + 1'
26
</pre>

$#array 表示数组 array 最后一个元素的下标.

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X