---
id: 948
title: 使用 transfer 共享文件
date: 2017-12-22T18:40:13+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=948
permalink: '/%e4%bd%bf%e7%94%a8-transfer-%e5%85%b1%e4%ba%ab%e6%96%87%e4%bb%b6/'
categories:
  - code
  - system
tags:
  - transfer
---
## 简单说明

[transfer](https://github.com/arstercz/transfer) 工具可以很方便的让大家以命令行的方式共享文件, 其参考了工具 [transfer.sh](https://github.com/dutchcoders/transfer.sh), 不过去掉了很多不太常用的功能, 另外我们给 `transfer` 工具增加了以下特性:
```
1. http basic auth to verifid users;
2. transfer read configure file to revify user;
3. add timestamp to the upload file;
4. use http delete method to delete file;
```

transfer 默认使用 http 的 basicauth 方式验证用户, 如果共享的文件比较敏感可以在 transfer 前面加个 https 做反向代理. 当然最好还是只在局域网环境中使用. 

## 适用场景

transfer 默认会随机生成一个子目录来保存用户上传的文件, 在文件数量特别多的情况下, transfer 就相当于将这些数量众多的文件放到了很多子目录中, 另外输出日志中也打印了子目录和文件的 url 地址, 方面大家的追踪. 从这点看 transfer 比较适合不同节点的文件统一存储以及进行批量分析处理.