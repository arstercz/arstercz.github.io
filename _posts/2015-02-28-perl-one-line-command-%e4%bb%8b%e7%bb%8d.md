---
id: 485
title: 'Perl one line command &#8211; 介绍'
date: 2015-02-28T18:50:23+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=485
permalink: '/perl-one-line-command-%e4%bb%8b%e7%bb%8d/'
dsq_thread_id:
  - "3555543601"
dsq_needs_sync:
  - "1"
categories:
  - code
tags:
  - performance
  - perl
---
<strong>Perl one line command - 介绍</strong>

Perl 命令行程序既轻巧又便捷, 它特指单行代码的 Perl 程序, 处理一些事情会特别方便, 比如: 更改文本行的空白符, 行数统计, 转换文本, 删除和打印指定行以及日志分析等.

熟悉命令行操作后可以节省我们大量的时间成本, 当然了解 Perl 的基本语法和一些特殊符是学习 perl 命令行的基础. Perl 在 5.8 和 5.10 版本对命令行的支持都很好.

先来介绍下常用的参数：
<pre>
   -a 参数在和 -n 或 -p 参数使用时, 启用自动分割模式, 将结果保存到数组@F(等同 @F = split $_ )
   -e 参数允许 Perl 代码以命令行的方式执行.
   -n 参数相当于在代码外围增加了while(<>)处理.
   -p 参数等同-n参数, 不过会打印出行内容.
   -i 参数保证文件 file 在编辑之前被替换掉, 如果我们提供了扩展名, 则会对文件 file 做一个以扩展名结尾的备份文件.
   -M 参数保证在执行程序之前，加载指定的模块.
   -l 参数自动chomp每行内容(去掉每行结尾的换行符)同时在打印输出的时候又加上换行符到结尾.
</pre>

<!--more-->



我们以一些常用的示例开始说明:
<pre>
   perl -pi -e 's/from/to/g' file
</pre>
该命令会替换文件file中所有的from为to, 如果要在windows中执行，将上述的 ' 换位 " 即可.

因此很容易理解以下示例,先生成 file.bak 备份, 再进行替换操作:
<pre>
   perl -pi.bak -e 's/from/tp/g' file
</pre>

如果有多个文件, 则依次进行处理:
<pre>
   perl -pi.bak -e 's/from/to/g' file1 file2 file3
</pre>

在这里, 我们可以使用正则来只处理匹配到的行:
<pre>
   perl -pi.bak -e 's/from/tp/g if /there/' file
</pre>

将上面的命令行, 还原为 Perl 程序, 类似如下:
<pre>
   while(<>) {
       if($_ =~ /there/) {
           $_ =~ s/from/to/g;
       }
       print $_;
   }
</pre>

这里的正则可以是任何表达式, 比如我们只处理包含数字的行, 可以使用 \d 匹配数字:
<pre>
   perl -pi -e 's/from/to/g if /\d/' file
</pre>

同样我们也可以统计文本中相同行的信息, 打印超过一次的行:
<pre>
   perl -ne 'print if $a{$_}++' file
</pre>
这条命令使用了哈希 %a, 统计了一行内容出现的次数, 哈希的 key 为行的内容, 值为出现的次数; 在处理一行记录时, 如果 $a{$_} 为 0, 表示还没有处理过该行内容, 则忽略打印, 同时初始化 $a{$_} 赋值为 1; 如果 $a{$_} 大于 0, 则表示已经处理过该行, 这时满足 if 条件, 则打印出该行内容. 

$_ 表示当前行的内容. 

也可以使用 $. 打印行号, $. 变量维护着当前行号的信息, 只需要将其和 $_ 一起打印即可:
<pre>
   perl -ne 'print "$. $_"' file

   perl -pe '$_ = "$. $_"' file
</pre>
上面两个示例等效, 因为 -p 等同 -n, 同时也进行打印操作.结合上述统计文件相同行的示例, 只打印超过一次的行及行号:
<pre>
   perl -ne 'print "$. $_" if $a{$_}++'
</pre>

再来处理空白行, 如下示例:
<pre>
   perl -lne 'print if length' file
</pre>
如果不为空行则打印, 上述等同于 perl -ne 'print unless /^$/' file, 不过和下面示例有点不同:
<pre>
   perl -ne 'print if /\S/'
</pre>
\S正则匹配非空白字符(空格, 制表符, 新行, 回车等), 索引上述的两个示例并不会过滤制表符类的空行.

另一个例子我们采用 List::Util 模块( <a href="http://www.cpan.org">http://www.cpan.org</a> )来打印每行中最大的数值，List::Util 是 Perl 的内置模块, 不需要额外的安装，以下

示例打印每行中最大的数值:
<pre>
   perl -MList::Util=max -alne 'print max @F' file
</pre>
-M 导入了 List::Util 模块, =max 导入了 List::Util 模块中的 max 方法, -a 开启了分割模式, 将结果存到 @F 数组中, -l 确保每次打印产生换行.

下面是一个随机生成8位字母组成的口令信息:
<pre>
   perl -le 'print map{ ("a".."z")[rand 26] } 1..8'
</pre>
"a".."z" 生成字母从 a 到 z 的字母列表, 然后随机的选择 8 次.

我们可能也想知道一个 ip 地址对应的十进制整数:
<pre>
   perl -le 'print unpack("N", 127.0.0.1)'
</pre>
unpack 对应 pack 函数, N 表示32位网络地址形式的无符号整形, 详见 `perldoc -f pack`.

如果要进行计算该怎么做?  -n 已经表示了 while(<>), 笨一点的方法可以将while放到代码里面, 比如以下:
<pre>
   perl -e '$sum = 0; while(<>){ @f = split; $sum += $f[0]; } print $sum'
</pre>
但是结合 -a 和 -n 选项则很容易处理:
<pre>
   perl -lane '$sum += $F[0]; END{print $sum}'
</pre>
END确保在程序即将结束时, 打印出总和.
再来看看统计iptables中通过iptables 规则的包的总量, 第一列显示了每条规则通过的包数, 我们只需要进行统计计算即可:
<pre>
   iptables -nvxL | perl -lane '$pkt += $F[0]; END{print $pkt}'
</pre>

最后介绍一点perldoc相关的信息, perldoc perlrun命令会显示如何执行 Perl 及命令行参数使用相关的文档信息, 这在我们忘记一些参数的时候非常有用; perldoc perlvar显示所有变量相关的文档信息, 一些记不住的特殊符总在这里能找到; perldoc perlop 显示了所有操作符相关的信息，应有尽有; perldoc perlfunc 显示所有函数的文档信息, 可以算得上函数大全了.

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X