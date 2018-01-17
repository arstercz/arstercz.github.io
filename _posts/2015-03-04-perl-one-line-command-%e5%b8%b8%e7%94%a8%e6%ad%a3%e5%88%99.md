---
id: 511
title: 'Perl one line command &#8211; 常用正则'
date: 2015-03-04T15:10:35+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=511
permalink: '/perl-one-line-command-%e5%b8%b8%e7%94%a8%e6%ad%a3%e5%88%99/'
dsq_thread_id:
  - "3565681241"
dsq_needs_sync:
  - "1"
categories:
  - code
  - performance
tags:
  - performance
  - perl
---
Perl one line command - 常用正则

本章说明一些常用的正则表达式, 比如匹配 IP 地址, HTTP 头信息, email 地址等.
<strong>1. 匹配 IPv4 地址</strong>
IP 地址格式 xxx.xxx.xxx.xxx, 使用 \d 来匹配数字，通用的做法如下:
<pre>
/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
</pre>
{1,3}表示匹配最少一个, 最多3个数字，这个表达式没有检查地址的有效性(不能大于255)，所以也能匹配出无效的地址，但是对于有效的地址都能匹配出来; 我们可以发现前三部分是一样的, 可以改成:
<pre>
/^(\d{1,3}\.){3}\d{1,3}$/
</pre>
<!--more-->


{3}表示匹配3次. 
如果要检查地址的有效性, IPv4的范围是 0.0.0.0 ~ 255.255.255.255, 每字节可以是 1,2,3 位整数, 如果是 1 位的时候可以使用 [0-9] 来匹配 0 ~ 9, 如果是 2 位可以使用[0-9][0-9] 来匹配 10~99, 如果是 3 位 , 则需要匹配 100 ~ 255 之间的数, 可以使用 1[0-9][0-9] 匹配 100 ~ 199 之间的数, 2[0-4][0-9] 匹配 200 ~ 249 之间的数, 25[0-5] 匹配 250 ~ 255 之间的数.可以使用 | 或操作将这些正则连接起来, 整个表达式如下:
<pre>
/^([0-9]|[0-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$/
</pre>
所以整体上匹配一个有效的 IP 地址的代码如下:
<pre>
$ip_re = qr/[0-9]|[0-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]/;

if ( $ip =~ /^$ip_re\.$ip_re\.$ip_re\.$ip_re$/ ) {
   print "$ip\n";
}
</pre>

qr 表示引用正则相关的表达式: Regexp-like quote.

<strong>2. 匹配邮件地址</strong>
一个正常邮件的的形式如下 1234mnop@qq.com, 可以使用以下表达式匹配:
<pre>
/\S+@\S+\.\S+/
</pre>
\S排除了出现空白字符的可能, 既匹配了 @ 符号, 也匹配了 . 符号, 至少看起来满足这个条件的都是正常的邮件, 也可以使用 Email::Valid 模块进行检查, 不过需要额外安装:
<pre>
perl -MEmail::Valid -ne 'print Email::Valid->address("1234mnop@qq.com") ? "valid email" : "invalid email"' file
</pre>
? : 为 3 元操作符, address 为真则打印 valid email, 否则打印 invalid email.

<strong>3. 检查数字</strong>
如何检查数字的有效性, 先来看看有效的数字有哪些:
<pre>
23                          # 整数
23.1                        # 小数
+23, -23, +23.1, -23.1      # 正负数
1,000                       # 整数
</pre>
如果再算上复数, 十六进制, 八进制等就更复杂了, 如果是简单的匹配:
<pre>
/^\d+$/               # 匹配多个数字
/^[+-]?\d+$/          # 正负数, ? 表示可选, 匹配 0 个或 1 个
/^[+-]?\d+\.?\d*$/    # 小数
</pre>
上面的表达式并没有匹配类似 1,234,456 或 .3 的数字. 可以使用 Regexp::Common 模块来实现匹配:
<pre>
perl -MRegexp::Common -ne 'print if /$RE{num}{real}/' file
</pre>
如果要匹配十六进制和八进制, 可以使用以下正则:
<pre>
/^0x[0-9a-f]+/i
/^0[0-7]+/
</pre>
i 表示忽略大小写.

<strong>4. 检查出现两次的单词</strong>
<pre>
/(words).*\1/
</pre>
() 用来捕获里面的内容, 并赋值到 1 里, \1 是对 1 的解引用, 表示捕获到的内容. 整个表达式匹配 words.*words

<strong>5. 整数加1</strong>
<pre>
$sth =~ s/(\d+)/$1+1/ge
</pre>
g 为全局匹配, e 表示可以执行代码, ()捕获的内容放到 $1 中, 最有使用 $1+1 替换匹配的整数.

<strong>6. 匹配 HTTP 头信息</strong>
用 curl 来请求 weibo 的信息, 如下
<pre>
# curl -I http://www.weibo.com/
HTTP/1.1 302 Moved Temporarily
Server: WeiBo
Date: Wed, 04 Mar 2015 06:26:32 GMT
Content-Type: text/html
Connection: close
Expires: Mon, 26 Jul 1997 05:00:00 GMT
Last-Modified: Wed, 04 Mar 2015 06:26:32 GMT
......
</pre>
匹配各个字段都比较容易, 将捕获的内容放到特殊变量 $1 中, 比如:
<pre>
date: Wed, 04 Mar 2015 06:29:33 GMT
</pre>

<strong>7. 匹配可打印的 ascii 码字符</strong>
<a href="http://zh.wikipedia.org/wiki/ASCII">http://zh.wikipedia.org/wiki/ASCII</a>
详见维基百科, 除去控制字符, 剩下的为可显示字符, 可以看到可显示字符的范围是 空格 到 符号 ~, 对应16进制的 0x20 ~ 0x7e, 了解这些之后, 就可以明白下面表达式的意思:
<pre>
/[ -~]/
</pre>
表示匹配空格到符号 ~ 之间的字符, 如果不匹配可打印字符, 使用 ^ 反向即可:
<pre>
/[^ -~]/
</pre>

<strong>8. 替换标签信息</strong>
如果要将 <b> 或 </b> 替换为 <p> 或 </p>, 可以使用以下表达式:
<pre>
$str =~ s#<(/)?b>#<$1p>#g
</pre>
(/)? 表示匹配并捕获 0 或 1 次, 并赋值给 $1 变量, g表示全局替换.

<strong>9. 提取匹配的内容</strong>
如下表达式:
<pre>
@match = $str =~ /regex/g;
@match = ($str =~ /regex/g);
</pre>
$str =~ /regex/g 匹配所有相关的内容, 返回一个列表, 可以通过数组保存匹配到的内容, 如下所示匹配所有的整数:
<pre>
# perl  -le '$, = " "; $str = "hell 253, yes 50"; @match = ($str =~ /\d+/g); print @match'
253 50
</pre>
也可以匹配键值对, 比如字符串"key1=v1; key2=v2,v21; key3=v3,vs3":
<pre>
# echo "key1=v1; key2=v2,v21; key3=v3,vs3" | perl -lne '@vals = $_ =~ /[^=]+=([^;]+)/g; print "@vals"'
v1 v2,v21 v3,vs3
</pre>
表达式首先匹配 [^=]+ 即不是 = 的字符串, 再匹配 = , 再匹配 [^;]+ 即非 ; 的字符串, 再将结果存到数组中.

文章参考: PERL ONE-LINERS Copyrught @ 2014 by Peteris Krumins ISBN-10: 1-59327-520-X