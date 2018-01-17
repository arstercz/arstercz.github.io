---
id: 28
title: H3C S5120-52P SI系列交换机软件升级
date: 2014-04-10T23:46:50+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=28
permalink: /h3c_switch_upgrade/
views:
  - "55"
dsq_thread_id:
  - "3475462647"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - network
tags:
  - H3C
  - network
  - switch
---
<b>软件获取:</b>
http://www.h3c.com.cn/Service/Software_Download/Switches/Catalog/H3C_S5120/H3C_S5120-SI[E500]/
帐号密码需要联系h3c技术客服获取,暂用(应该是临时的用户)


<b>升级前：1505P09</b>
<pre>
H3C Comware Platform Software
Comware Software, Version 5.20, Release 1505P09
Copyright (c) 2004-2012 Hangzhou H3C Tech. Co., Ltd. All rights reserved.
H3C S5120-52P-SI uptime is 0 week, 0 day, 0 hour, 20 minutes

H3C S5120-52P-SI
128M    bytes DRAM
128M    bytes Nand Flash Memory
Config Register points to Nand Flash

Hardware Version is REV.A
CPLD Version is 002
Bootrom Version is 155
[SubSlot 0] 48GE+4SFP Hardware Version is REV.A
</pre>
<!--more-->

<b>传文件：</b>
<pre>
<dxt-k09-s3-bak>tftp 10.0.21.5 get S5120SI_E-CMW520-R1513P81.bin     #最新版

<dxt-k09-s3-bak>dir
Directory of flash:/

   0     -rw-  14595896  Mar 27 2014 18:10:30   s5120si_e-cmw520-r1513p81.bin
   1     -rw-       151  May 01 2000 05:07:28   system.xml
   2     -rw-      5002  May 01 2000 05:07:29   startup.cfg
   3     -rw-  13491152  Jun 19 2012 15:30:06   s5120si_e-cmw520-r1505p09.bin
   4     drw-         -  Apr 26 2000 12:00:07   logfile
</pre>


<b>升级:</b>
<pre>
<dxt-k09-s3-bak>bootrom update file flash:/s5120si_e-cmw520-r1513p81.bin slot 1 to 1 
  This command will update bootrom file on the specified board(s), Continue? [Y/N]:y
  Now updating bootrom, please wait...
  BootRom file updating finished!
</pre>

<b>重启:</b>
<pre>
<dxt-k09-s3-bak>reboot
 Start to check configuration with next startup configuration file, please wait.........DONE!
 This command will reboot the device. Current configuration will be lost, save current configuration? [Y/N]:y
Please input the file name(*.cfg)[flash:/startup.cfg]
(To leave the existing filename unchanged, press the enter key):
flash:/startup.cfg exists, overwrite? [Y/N]:y
 Validating file. Please wait....
 Saved the current configuration to mainboard device successfully.
 Configuration is saved to device successfully.
 This command will reboot the device. Continue? [Y/N]:y
#Mar 27 18:13:54:569 2014 dxt-k09-s3-bak DEVM/1/REBOOT: 
 Reboot device by command. 

%Mar 27 18:13:54:672 2014 dxt-k09-s3-bak DEVM/5/SYSTEM_REBOOT: System is rebooting now.
Starting......
Press Ctrl+D to access BASIC BOOT MENU
Press Ctrl+T to start memory test

********************************************************************************
*                                                                              *
*                    H3C S5120-52P-SI BOOTROM, Version 169                     *
*                                                                              *
********************************************************************************
Copyright (c) 2004-2013 Hangzhou H3C Technologies Co., Ltd.

Creation Date       : Oct 12 2013
CPU L1 Cache        : 32KB
CPU Clock Speed     : 333MHz
Memory Size         : 128MB
Flash Size          : 128MB
CPLD Version        : 002
PCB Version         : Ver.A
Mac Address         : 80F62EF75EBA


Press Ctrl-B to enter Extended Boot menu...0
Starting to get the main application file--flash:/s5120si_e-cmw520-r1513p81.bin!
................................................................................
...............................
The main application file is self-decompressing.................................
................................................................................
....................................................................Done!
System is starting...
User interface aux0 is available.
</pre>


<b>升级后版本: 1513P81</b>
<pre>
<dxt-k09-s3-bak>display version 
H3C Comware Platform Software
Comware Software, Version 5.20, Release 1513P81
Copyright (c) 2004-2013 Hangzhou H3C Tech. Co., Ltd. All rights reserved.
H3C S5120-52P-SI uptime is 0 week, 0 day, 0 hour, 1 minute

H3C S5120-52P-SI
128M    bytes DRAM
128M    bytes Nand Flash Memory
Config Register points to Nand Flash

Hardware Version is REV.A
CPLD Version is 002
Bootrom Version is 169
[SubSlot 0] 48GE+4SFP Hardware Version is REV.A
</pre>


<b>配置不变。</b>