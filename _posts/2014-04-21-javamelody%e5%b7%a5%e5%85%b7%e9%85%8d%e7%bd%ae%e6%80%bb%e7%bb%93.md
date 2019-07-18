---
id: 116
title: javamelody工具配置总结
date: 2014-04-21T00:20:52+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=116
permalink: '/javamelody%e5%b7%a5%e5%85%b7%e9%85%8d%e7%bd%ae%e6%80%bb%e7%bb%93/'
views:
  - "57"
dsq_thread_id:
  - "3487016514"
dsq_needs_sync:
  - "1"
categories:
  - monit
tags:
  - java
  - javamelody
---
参考链接：
<a href="http://code.google.com/p/javamelody/wiki/UserGuide">http://code.google.com/p/javamelody/wiki/UserGuide</a>      (包括开发手册)
<a href="http://www.caucho.com/resin-3.1/doc/resin-security.xtp">http://www.caucho.com/resin-3.1/doc/resin-security.xtp</a>  (用户登录配置)

<!--more-->
 
最近测试安装监控工具javamelody对java服务的应用进行监控，做一下配置方面的总结.


1、userguide手册下，拷贝需要的jar,war文件到项目的WEB-INFO/lib目录,net目录亦需要拷贝到项目的WEB-INFO目录下;
    注意一些项目需要更新依赖的几个jar包文件；比如logback-classic-1.0.1.jar 和logback-core-1.0.1.jar;
    编辑WEN-INFO下的web.xml文件，增加相关的监控属性;
    重启项目;

    访问链接: <a href="http://mydomain/monitoring">http://mydomain/monitoring</a>(需要绑定hosts文件)

    监控出来的条目很详细，可参考链接查看：<a href="https://code.google.com/p/javamelody/">https://code.google.com/p/javamelody/</a>

    比之于JMX（<a href="http://docs.oracle.com/javase/1.5.0/docs/guide/management/agent.html">http://docs.oracle.com/javase/1.5.0/docs/guide/management/agent.html</a>）监控，javamelody配置更方便，安全，因为JMX的配置产生了许多不稳定的因素，比如需要开启应用的远程监控端口，修改一些应用启动的系统属性；javamelody则只增加几个文件,修改web.xml信息.

2、http://mydomain/monitoring默认均可以访问,可通过如下方法限制其他用户访问：

    (1)web前端增加对monitoring的访问过滤
    (2)通过增加authenticator属性可限制仅登录用户可以访问.如下：
        可参考 <a href="http://code.google.com/p/javamelody/wiki/UserGuide">http://code.google.com/p/javamelody/wiki/UserGuide</a>  16节Security  对web.xml配置进行配置

   新增加 resin-web.xml增加用户口令信息 
![resin_web](images/articles/201405/resin_web.jpg)

 

还可以在/web/resin/conf/resin.passport.com.conf文件中增加authenticator属性信息,可参考链接：<a href="http://www.caucho.com/resin-3.1/doc/resin-security.xtp#authenticator">http://www.caucho.com/resin-3.1/doc/resin-security.xtp#authenticator</a>

再新增password.xml文件到WEB-INFO目录下，重启应用即可;
![password.xml](images/articles/201405/password.jpg)

第一种方式简单方便，但不全面可靠，第二种方式尽管可靠，但每个待监控的项目都需要相关的配置，作业量很大;
