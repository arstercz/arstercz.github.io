---
id: 491
title: 'Perl one line command &#8211; 计算'
date: 2015-03-02T21:00:47+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=491
permalink: '/perl-one-line-command-%e8%ae%a1%e7%ae%97/'
dsq_thread_id:
  - "3560539142"
dsq_needs_sync:
  - "1"
categories:
  - code
tags:
  - performance
  - perl
---
Perl one line command - 计算

本章使用 Perl 命令行进行一些计算方面的示例说明, 比如查找一行中最大/最小的元素, 统计, 移动和替换单词以及计算日期等. 这章里会用到 -a, -M, -F等命令行参数, 也会讲解一些特殊符及数据结构方面的信息.

<strong>1. 检查素数</strong>
<pre>
   perl -lne '(1x$_) !~ /^1?$|^(11+?)\1+$/ && print "$_ is prime number"' file
</pre>
先来看看素数的定义: 一个大于1的自然数，除了1和它本身外，不能整除以其他自然数的数称为素数, 否则是合数. 命令行首先将数字转换成一元数据(比如 4 表示为 1111, 5 表示为 11111, 等等), 再用 !~ 排除匹配的正则表达式里的两个条件, 如果都没有匹配, 则该数是素数; 再来看看正则表达式里面的内容, 首先 ^1?$ 表示 0 或 1, 满足一个大于 1 的自然数,  ^(11+?)\1+$ 决定了是否有2个或多个 11... 组成为该数, 如果是表示该数可以整除其他自然数. 举例如下, 5 的一元数据表示为 11111, (11+?) 首先匹配 11, 正则表达式成为 ^11(11)+$, 这里的 + 表示一个或多个 11, 但对于5来讲, 不会匹配上; 下面是 (11+?)匹配 111, 正则表达式成为 ^111(111)+$, 同样不会匹配 5, 综上 1x5 满足了不匹配两个正则的条件, 所以它是素数.

<!--more-->


<strong>2. 计算一行中各列数的和</strong>
<pre>
   echo "1 5 7" | perl -MList::Util=sum -alne 'print sum @F'
</pre>
同 <a href="http://zhechen.me/perl-one-line-command-%E4%BB%8B%E7%BB%8D/">http://zhechen.me/perl-one-line-command-%E4%BB%8B%E7%BB%8D/</a>提到的 -M 参数的示例, 这里使用 List::Util 模块的 sum 方法, 开始 -a 参数, 各列的数值被分割切保存到 数组 @F 中, 再通过 sum 方法计算出该行中所有列之和. 上述命令行的结果为 13. -a 分割默认使用空格, 可以通过 -F 参数指定分隔符, 比如以下示例:
<pre>
   echo "1:5:7" | perl -F/:/ -MList::Util=sum -alne 'print sum @F'
   echo "1:5:7" | perl -F: -MList::Util=sum -alne 'print sum @F'
</pre>

同样的, 如果我们需要计算所有行数的所有列之和, 将每行的数组 @F 保存到一个大数组里, 或者使用上下文环境累加每行的和, 再使用 END 即可满足条件:
<pre>
[root@cz scripts]# cat file 
1:5:7
2:4:6

[root@cz scripts]# perl -F: -MList::Util=sum -alne 'push @s, @F; END{print sum @s}' file 
25

[root@cz scripts]# perl -F: -MList::Util=sum -alne '$s += sum @F; END{print $s}' file 
25
</pre>

<strong>3. 打乱行中的列项</strong>
先来看下面的示例:
<pre>
[root@cz scripts]# echo a b c d | perl -MList::Util=shuffle -alne 'print shuffle @F'
cabd
</pre>
List::Util 模块的 shuffle 方法以随机顺序返回 @F 数组的元素列表, 我们使用 $, 特殊符来指定数组元素之间的分隔符, 如下所示:
<pre>
[root@cz scripts]# echo a b c d | perl -MList::Util=shuffle -alne '$, = ":" ;print shuffle @F'
b:c:d:a
</pre>
也可以用 join 函数替换 $, :
<pre>
[root@cz scripts]# echo a b c d | perl -MList::Util=shuffle -alne 'print join ":", shuffle @F'
b:d:c:a
</pre>
也可以将 shuffle @F 放到匿名函数中打印出来, 我们使用 @{[shuffle @F]}, [shuffle @F] 创建了一个匿名的数组引用, @{}则将它反解析出来:
<pre>
[root@cz scripts]# echo a b c d | perl -MList::Util=shuffle -alne 'print "@{[shuffle @F]}"'
d b c a
</pre>
<strong>4. 找到最小/最大的数值</strong>
同样我们也可以调用 List::Util 模块的 min, max 方法得到一行中最小/最大的数值, 比如:
<pre>
[root@cz scripts]# echo 5 7 -1 | perl -MList::Util=min -alne 'print min @F'
-1
</pre>

也可以找到文本中最小/最大的数值：
<pre>
[root@cz scripts]# cat file 
-9 2 7
-11 -90 0
4 8 19

[root@cz scripts]# perl -MList::Util=min -alne 'push @M, @F; END{ print min @M}' file 
-90
[root@cz scripts]# perl -MList::Util=min -alne '$min = min($min || (), @F); END{ print $min}' file 
-90
</pre>
在 Perl 5.10 及之后的版本中, // 操作符类似逻辑操作符 ||, 只不过它会额外判断左边的是否已经定义过; 以 $min // () 为例说明, 如果 $min 已经定义过, 则返回 $min, 否则返回空列表(), 用 perldoc perlop看看手册页关于 // 的解释: "$a // $b" is similar to "defined($a) || $b" (except that it returns the value of $a rather than the value of "defined($a)") and is exactly equivalent to "defined($a) ? $a : $b"
所以下面的示例等效于上面的:
<pre>
[root@cz scripts]# perl -MList::Util=min -alne '$min = min($min // (), @F); END{ print $min}' file 
-90
</pre>
同理, 我们可以使用 max 方法得到最大的数值.

<strong>5. 替换每列值为其绝对值</strong>
可以使用 abs 函数得到数值的绝对值， 再通过 map 进行映射替换, 如下:
<pre>
[root@cz scripts]# perl -anle '$, = " "; print map { abs } @F' file 
9 2 7
11 90 0
4 8 19

[root@cz scripts]# perl -anle 'print "@{[map{ abs } @F]}"' file 
9 2 7
11 90 0
4 8 19
</pre>
同上述的示例一样， [map{ abs } @F] 构成匿名的数组引用, 再用 @{}反解析出来.

<strong>6. 统计行信息</strong>
使用上下文环境可以直接打印每行中的列数:
<pre>
perl -alne 'print scalar @F' file
</pre>
也可以将行内容追加到列数之后:
<pre>
perl -alne 'print scalar @F . " $_"' file
</pre>
通过 END 打印出文本中所有列的信息:
<pre>
perl -alne '$s += @F; END{ print $s }' file
</pre>
打印匹配行的所有列信息:
<pre>
perl -alne '$s += /there/ for @F; END{ print $s }' file

perl -alne '$s += grep /there/, @F; END{ print $s }' file
</pre>
grep 返回满足正则匹配的元素列表, 不过在标量环境中返回列表的数量;
下面的示例打印文本匹配正则的行数:
<pre>
perl -lne '/there/ && $s++; END{ print $s || 0 }' file
</pre>

<strong>7. 打印 PI 和 e</strong>
<pre>
[root@cz scripts]# perl -Mbignum=bpi -le 'print bpi(20)'
3.1415926535897932385
[root@cz scripts]# perl -Mbignum=PI -le 'print PI'
3.141592653589793238462643383279502884197
</pre>
bignum 模块提供 bpi 和 PI 两个方法打印 PI 值, bpi 输出精度为 n - 1, PI 输出精度为 39.
<pre>
[root@cz scripts]# perl -Mbignum=bexp -le 'print bexp(2,31)'
7.389056098930650227230427460575
</pre>
bexp(2,31) 等效于 e^2, 再输出 31 - 1 = 30 精度的浮点数.

<strong>8. 时间</strong>
打印 Unix 时间戳, time 函数返回从格林尼治时间(1970 01-01 00:00:00 UTC)到当前时间的秒数:
<pre>
[root@cz scripts]# perl -le 'print time'
1425286022
</pre>
可读格式获取格林尼治时间, gmtime 返回GMT时区信息:
<pre>
[root@z6 scripts]# perl -le 'print scalar gmtime'
Mon Mar  2 08:49:26 2015
</pre>
gmtime 和 localtime 都返回含有 9 个元素的列表:
<pre>
($second, [0]
 $minute, [1]
 $hour, [2]
 $month_day, [3]
 $month, [4]
 $year, [5]
 $week_day, [6]
 $year_day, [7]
 $is_daylight_saving [8]
)
</pre>
使用数组切片就可以打印出我们需要的信息, 比如打印 H:M:S
<pre>
[root@cz scripts]# perl -le 'print join ":", (localtime)[2,1,0]'
16:56:3
</pre>
打印昨天的时间：
<pre>
perl -MPOSIX -le '@now = localtime; $now[3] -= 1; print scalar localtime mktime @now'
</pre>
mktime @now 将9个元素的列表转换为纪元时间格式(epoch time, 即时间戳), 详见 perldoc POSIX,  再用 localtime重构日期格式, 最后使用 scalar 输出, 等同 print scalar localtime(mktime @now) 或  print ~~ localtime(mktime @now).
同理可以得到, 14个月, 9天07秒之前的时间:
<pre>
perl -MPOSIX -le '@now = localtime; $now[0] -= 7; $now[3] -= 9; $now[4] -= 14; print scalar localtime mktime @now'
</pre>

<strong>9. 计算阶乘</strong>
<pre>
perl -le '$f = 1; $f *= $_ for 1 .. 5; print $f'
</pre>
也可以使用 Math::BigInt 模块的 bfac 函数:
<pre>
perl -MMath::BigInt -le 'print Math::BigInt->new(5)->bfac()'
或
perl -MMath::BigInt -le 'print Math::BigInt->bfac(5)'
</pre>

<strong>10. 计算最大公约数和最小公倍数</strong>
先用辗转相除法计算两个数的最大公约数:
<pre>
perl -le '$n = 20; $m = 35; ($m, $n) = ($n, $m%$n) while $n; print $m'
</pre>
按照欧几里得算法的定理: gcd(a,b) = gcd(b,a mod b) (a>b 且a mod b 不为0), 上面的命令行在 $n 不为 0 时循环执行, 最后得到最大公约数 5.
再计算最小公倍数: 最小公倍数=两数的乘积/最大公约（因）数
<pre>
perl -le '$a = $n = 20; $b = $m = 35; ($m, $n) = ($n, $m%$n) while $n; print $a*$b/$m'
</pre>
得到最小公倍数 140.
使用 Math::BigInt 模块的 bgcd 和 blcm 计算最大公约数和最小公倍数:
<pre>
[root@cz scripts]# perl -MMath::BigInt=bgcd -le 'print bgcd(20,35)'
5
[root@cz scripts]# perl -MMath::BigInt=blcm -le 'print blcm(20,35)'
140
</pre>

<strong>11. 生成两数之间的随机数</strong>
先来生成10个处于 [5,15)之间的随机数:
<pre>
perl -le 'print join ",", map{ int(rand(15 - 5)+5) } 1 .. 10'
</pre>
int(rand(10)) 生成 0 ~ 9 之间的数字， 再加上5, 就可以生成 5 <= n < 15 之间的数字. 同理可以生成 x 个处于 [m,n)之间的数;
<pre>
perl -le 'print join ",", map{ int(rand($n - $m)+$m) } 1 .. $x'
</pre>

<strong>12. IP 地址转换</strong>
(1) IP 地址转为整数:
<pre>
# perl -le '$i = 3; $u += ($_ << (8*$i--)) for "127.0.0.1" =~ /(\d+)/g; print $u'
2130706433
</pre>
"127.0.0.1" =~ /(\d+)/g 生成匿名数组, 包括元素 127, 0, 0, 1. ip地址分为4组, 每组8位, 通过 $_ << (8*$i--) 可以得到每组的转换值, 最后再求和就是 IP 地址转换后的整数. 另外因为每组8位, 可以将每组转换为2个16进制的数, 再通过 hex 函数得到十进制整数:
<pre>
# perl -le '$ip="127.0.0.253"; $ip =~ s/(\d+)(?:\.|$)/sprintf("%02x", $1)/ge; print hex $ip'
2130706685
# perl -le '$ip="127.0.0.253"; $ip =~ s/(\d+)\.?/sprintf("%02x", $1)/ge; print hex $ip'
2130706685
</pre>
第一行中的(?:\.|$) 表示值匹配不捕获, 这里可以匹配 127. 或最后一组数字 253, 但是只捕获 127 或 253, 通过 sprintf 转换后得到16进制 7f0000fd， 最后通过 hex 转为 10 进制.
同 <a href="http://zhechen.me/perl-one-line-command-%E4%BB%8B%E7%BB%8D/">http://zhechen.me/perl-one-line-command-%E4%BB%8B%E7%BB%8D/</a>中介绍的 unpack 函数, 对应 pack 函数, N 表示32位网络地址形式的无符号整形, 详见 perldoc pack.
<pre>
# perl -le 'print unpack("N", 127.0.0.253)'
2130706685
</pre>
上面的 127.0.0.253 是以版本字符(version string)表示的字符串, 是由特定序列值组成的字串值,比较特殊, 如果 IP 地址是以字符串的形式出现，需要先将其转为字节类型, 可以使用 Socket 模块的 inet_aton 函数:
<pre>
# perl -MSocket -le 'print unpack("N", inet_aton("127.0.0.253"))'
2130706685
# perl -le 'print unpack("N", "127.0.0.253")'  # 转换错误
825374510
</pre>
(2) 整数转换为 IP 地址
先使用 Socket 模块的 inet_ntoa转换:
<pre>
# perl -MSocket -le 'print inet_ntoa(pack("N", 2130706685))'
127.0.0.253
</pre>
这里先用 pack 将值改为字节顺序存储, 再通过 inet_ntoa 转换为 ip 地址. 也可以用位移的方式,如下:
<pre>
# perl -le '$ip = 2130706685; print join ".", map{ (($ip>>8*($_))&0xFF) } reverse 0 .. 3'
127.0.0.253
</pre> 
reverse 0 .. 3 反转列表为 3 .. 0, map函数中, 第一次循环, $ip >> 24 后为 01111111，和 0xFF(二进制 11111111 ) 进行与操作后结果为 01111111(十进制127)，第二次 $ip >> 16 后为 0111111100000000, 和 0xFF 进行与操作后结果为 00000000(十进制0), 后面以此类推, 最后得到 127.0.0.253

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X