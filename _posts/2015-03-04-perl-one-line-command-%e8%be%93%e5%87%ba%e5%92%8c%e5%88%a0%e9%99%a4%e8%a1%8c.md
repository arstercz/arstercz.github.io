---
id: 509
title: 'Perl one line command &#8211; 输出和删除行'
date: 2015-03-04T15:03:23+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=509
permalink: '/perl-one-line-command-%e8%be%93%e5%87%ba%e5%92%8c%e5%88%a0%e9%99%a4%e8%a1%8c/'
dsq_thread_id:
  - "3565674342"
dsq_needs_sync:
  - "1"
categories:
  - code
  - performance
tags:
  - performance
  - perl
---
Perl one line command - 输出和删除行

本章介绍使用 Perl 命令行输出和删除指定的行内容, 比如 输出/删除 指定的行, 重复的行, 匹配的行等. 输出和删除操作是相对的( -i 参数 ), 明白了如何输出, 删除也就尽在掌握.

<strong>1. 输出文本 n 行内容</strong>
```
perl -ne 'print ; exit' file
perl -i -ne 'print ; exit' file
```
<!--more-->


print 省去了 $_ 变量, 打印第一行后通过 exit 退出, 这条命令实现了打印文本的第一行信息, 等同 head -1 file, 第二条命令等同第一条, 但是通过 -i 参数实现了删除其它行操作, 最后的 file 只保留第一行内容; 如果要在删除之前进行备份, 可以给 -i 指定扩展名, 如  .bak 等. 后续的示例不在说明删除操作, 只列举输出操作.
如果要打印文本的前 10 行内容, 可以通过行号实现, 下面几条命令等效:
```
perl -ne 'print if $. <= 10' file
perl -ne '$. <= 10 && print' file
perl -ne 'print if 1..10' file
perl -ne 'print; exit if $. == 10' file
```
第三条命令中, 使用了 .. 范围操作符, 在标量环境中返回布尔值, 这种操作相当于双重的判断(flip-flop), 类似于 sed, awk 中的行范围分隔符(,) , 1..10 为真时, 打印行内容, 为 false 则不打印.
如果需要打印最后一行内容, 比起上面的示例则要麻烦一些, 因为不清楚哪一行才是结尾, 所以只能不停的读取, 直到最后一行; 或者使用 eof 函数判断文件的结尾:
```
perl -ne '$last = $_; END{print $last}' file
perl -ne 'print if eof' file
```
基于上述示例, 再来打印最后的十行内容, 类似 tail -n 10 file:
```
perl -ne 'push @a, $_; @a = @a[@a-10 .. $#a] if @a>10; END{ print @a }' file
perl -ne 'push @a, $_; shift @a if @a > 10; END{ print @a }' file
```
第一条命令使用数组切片的方式取得最后的十行内容, $#a 表示数组 @a 最后一个元素的下标, @a-10 在标量环境中表示数组 @a 的元素数量减去 10, 总体上表示取数组 @a 后十个元素, 再重新赋值给数组 @a, 如果数组元素数量小于 10, 则不用做处理. 第二条命令换了一种方法, 每次判断元素数量大于 10 的时候就删除数组中的第一个元素.

<strong>2. 打印匹配/非匹配行</strong>
还是通过正则实现：
```
perl -ne '/there/ && print' file
perl -ne 'print if /there/' file
```
如果打印非匹配行, 可以使用以下:
```
perl -ne '!/there/ && print' file
perl -ne 'print if !/there/' file
perl -ne 'print unless /there/' file
perl -ne '/there/ || print' file
```
最后一条命令的 || 操作符表示逻辑或, 为假时则执行 print 操作.

<strong>3. 打印匹配行的前/后一行</strong>
如果需要保存匹配行的前一行, 需要有一个变量保存前一行的内容, 下一行匹配的时候则输出:
```
# cat file
novel
film
group
# perl -ne '/film/ && $pren && print $pren; $pren = $_' file
novel
```
在最开始的时候 $pren 未定义, 则不执行 print, 同时将第一行内容赋值给 $pren, 下一次循环的时候, 如果正则匹配上则 /there/ && $pren 条件为真, 执行 print, 这时候的 $pren 为上一行的内容; 如果正则为假, 则不执行, 同时将第二行内容赋值给 $pren, 以此类推. 该命令等同 grep -B 'there' file, 不过 grep 也输出了匹配行.
如果要打印匹配的后一行, 启用一个布尔变量标识即可:
```
# perl -ne 'if($p) { print; $p = 0} $p++ if /film/' file
group
# perl -ne '$p && print; $p = /film/' file
```
如果当前行匹配, $p 变量这时候为真, 下一次循环的时候则执行打印操作, 同时重置 $p 变量为下次匹配做准备.
打印既匹配 AAA 也匹配 BBB 的行:
```
perl -ne '/AAA/ && /BBB/ && print' file
```
如果不匹配 AAA 也不匹配 BBB, 可以使用以下:
```
perl -ne '!/AAA/ && !/BBB/ && print' file
```
如果要按顺序匹配 AAA 和 BBB, 并且 BBB 在 AAA 之后, .* 表示0或多个字符:
```
perl -ne '/AAA.*BBB/ && print' file
```

<strong>4. 行长度</strong>
```
perl -ne 'print if length >= 80' file
perl -ne 'print if length <= 80' file
```
打印长度大于/小于 80 的行.

<strong>5. 打印指定行号</strong>
```
perl -ne 'print if $. == 10; exit' file    # 打印第 10 行
perl -ne 'print if $. != 10' file          # 忽略第 10 行
perl -ne 'print if $. >= 10 && $. <= 20'   
perl -ne 'print if 10..20'
```
3, 4 条命令等效, 都打印 10 ~ 20 行.
如果要匹配两个正则之间的行, 也可以使用 .. 操作符, 匹配 /there1/ 的时候条件为真, 直到匹配 /there2/, 类似于上面的 10..20, 如下:
```
perl -ne 'print if /there1/../there2/' file
```
打印只含字母的行, 可以使用 [[:alpha:]] 来匹配, [[:alpha:]]+ 表示一个或多个字母:
```
perl -ne 'print if /^[[:alpha:]]+$/' file
```

<strong>6. 打印最长/最短行</strong>
```
perl -ne '$p = $_ if length($_) > length($p); END{ print $p} ' file
perl -ne '$p = $_; $p = $_ if length($_) < length($p);END{ print $p }' file
```
第一条命令打印最长行, 第二条命令打印最短行, 最短行中的 $p 变量需要初始化, 否则 $length($_) < $length($p) 永远为假.

<strong>7. 打印重复或唯一行</strong>
可以使用哈希来实现该功能, 哈希的键为行内容, 值为出现的次数, 如下:
```
perl -ne 'print if ++$a{$_} > 1' file
perl -ne 'print if ++$a{$_} == 2' file
perl -ne 'print unless $a{$_}++' file
```
第一条命令会重复打印, 第二条命令只将重复的行打印一次; 第三条命令是相对的, 当行出现多次的时候, $a{$_} 为 1, 则不执行 print.


文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X