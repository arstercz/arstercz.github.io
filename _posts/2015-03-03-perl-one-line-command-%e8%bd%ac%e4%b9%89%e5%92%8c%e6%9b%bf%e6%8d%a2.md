---
id: 503
title: 'Perl one line command &#8211; 转义和替换'
date: 2015-03-03T19:56:10+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=503
permalink: '/perl-one-line-command-%e8%bd%ac%e4%b9%89%e5%92%8c%e6%9b%bf%e6%8d%a2/'
dsq_thread_id:
  - "3563309348"
dsq_needs_sync:
  - "1"
categories:
  - code
  - performance
tags:
  - performance
  - perl
---
Perl one line command - 转义和替换

本章使用 Perl 命令行来更改, 转换, 替换文本内容, 同时会介绍 base64 的编解码, url 转义, HTMl转义等相关的信息.

<strong>1. ROT13 </strong>
详见 <a href=http://en.wikipedia.org/wiki/ROT13>http://en.wikipedia.org/wiki/ROT13</a>
ROT13（回转13位，rotateby13places，有时中间加了个减号称作ROT-13）是一种简易的置换暗码，比如 A 加密后为 N, B 为 M, a 为 n, b 为 m .它是一种在网路论坛用作隐藏八卦、妙句、谜题解答以及某些脏话的工具，目的是逃过版主或管理员的匆匆一瞥, 本身上ROT13是它自己逆反；也就是说，要还原ROT13，套用加密同样的算法即可得，故同样的操作可用再加密与解密. 我们使用 y/// 和 tr/// 操作符说明如下:
<pre>
perl -le '$string = "hello"; $string =~ y/A-Za-z/N-ZA-Mn-za-m/; print $string'
perl -le '$string = "hello"; $string =~ tr/A-Za-z/N-ZA-Mn-za-m/; print $string'
</pre>
<!--more-->


y 等同于 tr 操作符, tr/search/replace/ 表示转换 search 列表中的元素为 replace 列表中相同位置的元素, 比如 $string =~ tr/mn/op/ 表示将 $string 字符中的 m 转为 o, n 转为 p. 对于上述的示例, A-Za-z 中的每个字符被回转了13位. 再看 -i 参数的示例:
<pre>
# cat file 
how there are
list file
there are

# perl -pi.bak -e 'y/A-Za-z/N-ZA-Mn-za-m/' file

# cat file
ubj gurer ner
yvfg svyr
gurer ner
</pre>
-i 参数指定了 .bak 扩展, 在程序执行前, 会将 file 改为 file.bak 文件达到备份的目的, 再将生成的结果输出到 file, 通过 file.bak 和 file 文件状态的 Modify 信息可以确定 -i 参数的处理逻辑.

<strong>2. Base64</strong>
可以使用 MIME::Base64 模块的 encode_base64 和 decode_base64 方法对字符串进行编码和解码操作, 如下:
<pre>
# perl -MMIME::Base64 -e 'print encode_base64("hello")'
aGVsbG8=
# perl -MMIME::Base64 -e 'print decode_base64("aGVsbG8=")'
hello
</pre>
想要对整个文本文件进行编码, 可以使用前面章节提到的 -00(按段落读取内容) 和 -0777(整个文本读取) 参数.

<strong>3. 转义/反转义字符串</strong>
可以使用 URI::Escape 模块的 uri_escape 和 uri_unescape 方法对 uri 进行转义/反转义，如下:
<pre>
# perl -MURI::Escape -le 'print uri_escape("http://arstercz.com")'
http%3A%2F%2Farstercz.com
# perl -MURI::Escape -le 'print uri_unescape("http%3A%2F%2Farstercz.com")'
http://arstercz.com
</pre>

<strong>4. HTML编码</strong>
HTML编码可以将一些标签信息转换为 HTML 编码的形式, 比如 < 转换为 &lt; 等, 可以使用 HTML::Entities 模块的 encode_entities 和 decode_entities 方式实现:
<pre>
# perl -MHTML::Entities -le 'print encode_entities("<html>")'
&lt;html&gt;
# perl -MHTML::Entities -le 'print decode_entities("&lt;html&gt;")'
<html>
</pre>

<strong>5. 大小写转换</strong>
先来将文本内容全转为大写，使用 uc 函数或将 \U加到每行的开头:
<pre>
# cat file
ubj gurer ner
yvfg svyr
gurer ner

[root@z6 scripts]# perl -nle 'print uc' file
UBJ GURER NER
YVFG SVYR
GURER NER

# perl -le 'print "\Uhello"'
HELLO
</pre>
小写转换可以使用 lc 函数或将 \L加到每行的开头, 如果只让每行开头的字母大写, 可以先将整行都转为小写, 再转第一个字符为大写:
<pre>
# perl -le 'print ucfirst lc "hello World"'
Hello world
# perl -le 'print "\u\Lhello World"'
Hello world
</pre>

使用 y/// 或 tr/// 操作符可以将字符串中的大小写互换, 比如:
<pre>
# perl -le '$string = "Hello World"; $string =~ y/A-Za-z/a-zA-Z/; print $string'
hELLO wORLD
</pre>
使用正则匹配让每个单词的首字母大写:
<pre>
# perl -le '$string = "hello world"; $string =~ s/(\w+)/\u$1/g; print $string'
Hello World
# perl -le '$string = "hello world"; $string =~ s/(\w+)/ucfirst $1/ge; print $string'
Hello World
</pre>

<strong>6. 去除空白符</strong>
去除每行开头的空格或制表符:
<pre>
# perl -ple 's/^[ \t]+//' file
# perl -ple 's/^(?: |\t)+//' file
# perl -ple 's/^\s+//' file
</pre>
[ \t] 和 (?: |\t) 等效, ^表示每行开头, 表示空格或制表符, \s 则可以匹配所有的空白符, 包括 tab, 水平制表符等.
同理, 可以去除每行末尾的空格或制表符:
<pre>
# perl -ple 's/[ \t]+$//' file
# perl -ple 's/(?: |\t)+$//' file
# perl -ple 's/\s+$//' file
</pre>
符号 $ 表示每行结尾.

<strong>7. 换行</strong>
从 UNIX 换行改为 Windows 换行:
<pre>
perl -pe 's|\012|\015\012|' file
perl -pe 's|\n|\r\n|' file
</pre>
由于平台的关系，CR(\015) 对应 \r, LF(\012) 对应 \n, Linux 到 Windows 的转换通常用第二种命令, 不过第一种方式更通用些. Windows 到 Unix 刚好相反, 从 CRLF 到 LF 转换.
Mac 系统中通过 \015(CR) 作为换行符, 如果从 Unix 转到 Mac, 可以使用:
<pre>
perl -pe 's|\012|\015|' file
</pre>

<strong>8. 内容替换</strong>
<pre>
perl -pe 's/foo/bar/' file     # 替换每行中第一个匹配的 foo 为 bar
perl -pe 's/foo/bar/g' file    # 替换每行中的 foo 为 bar
perl -pe 's/foo/bar/ if /baz/' # 该行匹配 baz, 则替换 foo 为 bar
perl -pe '/baz/ && s/foo/bar/' # 同上
</pre>

如果要按照段落反转文件的内容, 使用 -00 按照段落读取, 再通过 reverse 反转：
<pre>
perl -00 -e 'print reverse <>' file
</pre>
符号 <> 表示从标准输入读取内容.
上面的 reverse 反转列表中的元素, 在标量环境中, $_ 包含了整行的内容, 如果进行反转, reverse 会将整行内容当做一个元素反转, 反转后第一个字符就到最后一个, 第二个到倒数第二个,一次类推, 不管 reverse 在标量还是列表环境中, 都返回列表值, 所以如果要反转一行的内容并打印出来需要在标量环境中打印:
<pre>
perl -lne 'print scalar reverse $_' file
</pre>
符号 $_ 可以忽略, 根据这个示例我们也可以将行中的每列数据进行反转:
<pre>
perl -alne 'print "@{[reverse @F]}"' file
perl -alne '$" = " "; print "@{[reverse @F]}"' file
perl -alne '$, = " "; print reverse @F' file
</pre>
上面三条命令等效. $" 类似 $, 只不过 $" 适用于数组或数组切片, 默认为空格, $, 则是 print 操作的输出分隔符, 默认为 undef,  所以第一条和第二条命令是一样的.

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X