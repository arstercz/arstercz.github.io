---
layout: post
title: "二进制文件及 rpm 打包二三事"
tags: [binary rpm]
comments: true
---

近期通过 rpm 打包工具的时候注意到 rpm 文件大小比原始的二进制文件小很多. 大部分情况下这是因为工具包含 debug 符号表的原因, 不过在禁止 rpm 生成 debug package 后还会存在此类现象. 本文则主要记录 `rpm strip` 相关的几点事项.

### 当前工具结构

如下所示, 以 kvrocks 的工具 kvrocks2redis 为例, debug 相关的接近 410M:
```
size --format SysV kvrocks2redis
kvrocks2redis  :                         
section                   size       addr
.interp                     28    4195040
.note.gnu.build-id          36    4195068
.note.ABI-tag               32    4195104
.gnu.hash                  352    4195136
.dynsym                   8544    4195488
.dynstr                   3688    4204032
.gnu.version               712    4207720
.gnu.version_r             400    4208432
.rela.dyn                  600    4208832
.rela.plt                 8112    4209432
.init                       26    4218880
.plt                      5424    4218912
.text                 11325402    4224384
.fini                        9   15549788
.rodata                 752940   15552512
.eh_frame_hdr           226852   16305452
.eh_frame              1136328   16532304
.gcc_except_table       342545   17668632
.tdata                    2640   18016816
.tbss                    31632   18019456
.init_array               1432   18019456
.fini_array                  8   18020888
.data.rel.ro             37632   18020896
.dynamic                   544   18058528
.got                       176   18059072
.got.plt                  2728   18059264
.data                    11392   18062016
.bss                   2404384   18073408
.comment                   104          0
.debug_aranges          225936          0
.debug_info          257585038          0
.debug_abbrev          2862704          0
.debug_line           18885262          0
.debug_frame                96          0
.debug_str            35317122          0
.debug_loc            88205914          0
.debug_ranges         18617104          0
.debug_macro            218706          0
Total                438222584
```

### strip

strip 之后大小为 14M
```
➜  ls -hl kvrocks2redis 
-rwxr-xr-x 1 root root 420M Oct 29 21:21 kvrocks2redis
➜  strip --strip-unneeded kvrocks2redis 
➜  ls -hl kvrocks2redis                
-rwxr-xr-x 1 root root 14M Oct 31 12:35 kvrocks2redis
```

### 优缺点

对于很稳定的工具而言, 可以考虑进行 strip, 方便工具的分发部署. 如果工具不稳定, bug 及崩溃频率较多, 不建议 strip, 保留 debug 信息方便跟踪调试. 另外折中一点的方式是分发部署 strip 之后的工具, 崩溃调试时更换为 debug 版本.

## rpm 打包

spec 中可以选择任一方式禁止 strip:
```
# Turn off strip'ng of binaries
%global __strip /bin/true

或

%global __os_install_post %{nil}
```

另外也可以开启 `debug_package(默认开启)`, 这样 rpm 就会分别生成 `rpm` 及对应 `rpm debug` 两个包. 按需使用即可.
