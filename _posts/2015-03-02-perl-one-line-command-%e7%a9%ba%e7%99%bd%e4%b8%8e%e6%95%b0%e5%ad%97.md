---
id: 489
title: 'Perl one line command &#8211; 空白与数字'
date: 2015-03-02T20:57:14+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=489
permalink: '/perl-one-line-command-%e7%a9%ba%e7%99%bd%e4%b8%8e%e6%95%b0%e5%ad%97/'
dsq_thread_id:
  - "3560531674"
dsq_needs_sync:
  - "1"
categories:
  - code
tags:
  - performance
  - perl
---
Perl one line command - 空白与数字

<strong>一. 空白处理</strong>
本节说明 Perl 命令行对空白(空行, 制表符)的一些常见处理, 同样以一些示例来说明.

<strong>1. 多倍行距</strong>
使用特殊符 $\ 来完成多倍行距, $\ 特殊符相当于在每个 input 行后面额外增加了指定的 $\ 变量, 如果要将行距扩充两倍, 可以如下操作:
<pre>
perl -pe '$\ = "\n"' file
</pre>
在每行后面再增加一个换行符, 转换为如下代码:
<pre>
while(<>) {
   $\ = "\n";
   print $_ or die "-p failed: $!\n";
}
</pre>

<!--more-->


也可以使用 BEGIN 只对 $\ 做一次赋值:
<pre>
perl -pe 'BEGIN{ $\ = "\n" }' file
</pre> 
上面的示例等效于:
<pre>
perl -pe '$_ .= "\n"' file
perl -pe 's/$/\n/' file     # 每行结尾改为换行符
perl -nE 'say' file         # Perl 5.10 版的新特性, -E 为开启 Perl 5.10 版特性, say 类似 print, 但增加了换行操作.
</pre>

如果是多倍行距, 可以使用 "\n"xm(换行符重复m次), 如下3倍行距:
<pre>
perl -pe '$\ = "\n"x3' file
</pre>

<strong>2. 空行处理</strong>

<pre>
perl -pe '$_ .= "\n" unless /^$/' file
</pre>
unless 等同 if not, ^$表示匹配空行(^表示开始, $表示结束), 如果空行中存在制表符的话, ^$ 并不会匹配上, 这个示例等同下面:
<pre>
   perl -pe 'print if length' file
</pre>
如果不为空行(空行length应该为0)则打印, 如果存在制表符的行, print 还是会打印出来, 可以使用下面的代码:
<pre>
   perl -pe 'print if /\S/' file 
</pre>
\S正则匹配非空白字符(空格, 制表符, 新行, 回车等), 索引上述的两个示例并不会过滤制表符类的空行.也可以在每行之前增加一个空行:
<pre>
perl -pe 's/^/\n/' file
</pre>
我们将 -p 参数改为 -n 参数即可移除所有的空行, 因为 -p 本身就会打印出当前行内容:
<pre>
perl -ne '$_ .= "\n" unless /^$/' file
perl -ne 'print if /\S/' file
</pre>

<strong>3. 多个空白行改为一个空白行或指定行距</strong>
如下所示:
<pre>
perl -00 -pe '' file
perl -00pe0 file
</pre>
使用 perldoc perlrun 可以搜索到 -00, -0777所表示的意思, 00表示按照段落读取(slurp files in paragraph mode), 替代了原先的按行读取, 0777表示整个文本读取, -00指定了按照段落读取内容, 再输出来, 最后就实现了多个空行改为了一个空行. 这里的 -e '' 和 e0 表示什么都不做.
同样的, 使用下面的代码可以将一个行距扩充到多个:
<pre>
perl -00 -pe '$_ .= "\n"x3' file   # 每段落增加了3个换行符
</pre>

<strong>4. 单词之间的距离</strong>
<pre>
perl -pe 's/ /  /g' file
</pre>
将一个空格扩充到2个空格. 也可以移除单词之间的空格:
<pre>
perl -pe 's/ +//g' file
</pre>
 +(前面有个空格) 表示匹配一个或多个空格.如果有制表符,换行符等, 需要用 \s+ 来匹配:
<pre>
perl -pe 's/\s+//g' file
</pre>
也可以在每个字符之间插入一个空格:
<pre>
perl -lpe 's// /g' file
</pre>

<strong>二. 数字处理</strong>

本节说明 Perl 命令行对数字的处理.

<strong>1. 行号</strong>
使用 $. 特殊符表示行号, $_ 表示当前行内容:
<pre>
perl -pe '$_ = "$. $_"' file
perl -ne 'print "$. $_"' file
</pre>

排除空行的行号:
<pre>
perl -pe '$_ = ++$x." $_" if /./' file   #打印空行, 但不显示行号
perl -pe '$_ = ++$x." $_" if /\S/' file  #打印空行, 但不显示行号
perl -ne 'print ++$x." $_" if /./' file  #不打印空行
perl -ne 'print ++$x." $_" if /\S/'file  #不打印空行
</pre>
记录所有行号, 但是不打印空行:
<pre>
perl -pe '$_ = "$. $_" if /./' file
perl -pe '$_ = "$. $_" if /\S/' file
</pre>
只生成匹配规则的行号, 但是也打印没有匹配的行:
<pre>
# perl -pe '$_ = ++$x." $_" if /there/' file
1 how there are
list file
2 there are
</pre>
只生成匹配规则的行号, 但是不打印没有匹配的行:
<pre>
# perl -ne 'print  ++$x." $_" if /there/' file
1 how there are
2 there are
</pre>
生成所有行的行号, 但是只打印匹配规则的行:
<pre>
# perl -pe '$_ = "$.  $_" if /there/' file
1  how there are
list file
3  there are
</pre>

<strong>2. 输出格式</strong>
<pre>
# perl -ne 'printf "%-5d %s", $., $_' file
1     how there are
2     list file
3     there are

# perl -ne 'printf "%5d %s", $., $_' file
    1 how there are
    2 list file
    3 there are

# perl -ne 'printf "%05d %s", $., $_' file
00001 how there are
00002 list file
00003 there are
</pre>
使用 printf 函数格式化输出.

<strong>3. 打印文本的总行数(类似 wc -l)</strong>
<pre>
# perl -lne 'END{ print $. }' file
3
</pre>
下面示例等同上面的代码:
<pre>
perl -le 'print $n = () = <>' file
perl -le 'print $n = (() = <>)' file
perl -le 'print scalar(@fo = <>)' file
</pre>
这里没有使用 -p 或 -n, <> 表示 file 的文件句柄(所有内容), () = <> 表示将内容放到列表环境中(每个元素为一行内容), 再将 () = <> 复制给 $n, 这时候为标量上下文, $n 的值为列表元素的数量, 所以最后打印出文本的行数.  scalar(@fo = <>) 同理.下面的则稍有点不同:
<pre>
perl -nle ' }{ print $.' file
</pre>
这个表达式看起来很奇怪, 这里用到了 -n (等同在代码周围增加了while(<>){ }) 参数, 上面的代码等同以下:
<pre>
while(<>) {
} {
  print $.
}
</pre>
所以也打印出了最后一行的行号.

<strong>4. 统计非空行</strong>
<pre>
perl -le 'print scalar(grep { /./ } <>)' file
perl -le 'print ~~(grep { /./ } <>)' file
perl -le 'print ~~grep { /./ } <>' file
</pre>
上述三条命令等效, ~~ 即表示标量环境,

<strong>5. 统计空行</strong>
<pre>
perl -lne '$x++ if /^$/; END{print $x+0}' file
</pre>
$x+0 避免未匹配到而引起的未初始化错误, 如果要忽略制表符等, 正则里面应该是 \S. 也可以使用 grep 打印空行数:
<pre>
perl -le 'print scalar(grep {/^$/}<>)' file
perl -le 'print ~~grep{/^$/}<>' file
</pre>

<strong>6. 统计匹配规则的行数(grep -c)</strong>
<pre>
perl -lne '$x++ if /there/; END{print $x+0}' file
</pre>

<strong>7. 单词计数</strong>
文本所有单词计数:
<pre>
# perl -pe 's/(\w+)/++$i.".$1"/ge' file
1.how 2.there 3.are
4.list 5.file
6.there 7.are
</pre>
s///中的e选项可以使得替换之前先执行代码, (\w)为匹配并捕获单词, 捕获后放到 $1 变量中, $i 则在每次匹配之前自增 1.下面为计数每行的单词:
<pre>
# perl -pe '$i = 0; s/(\w+)/++$i.".$1"/ge' file
1.how 2.there 3.are
1.list 2.file
1.there 2.are
</pre>
每次循环初始化 $i 的值即可. 下面为替换每个单词为其计数的值:
<pre>
# perl -pe 's/(\w+)/++$i/ge' file
1 2 3
4 5
6 7
</pre>

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X