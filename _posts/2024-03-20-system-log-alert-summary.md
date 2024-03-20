---
layout: post
title: "系统日志报警汇总"
tags: [syslog system]
comments: true
---

本文汇总了 Linux 系统 syslog 和物理机硬件日志相关的报警说明, 以便于系统问题的发现和诊断.

## syslog 日志 

syslog 消息报警策略参考以下规则:
```
(
  (msg:xfs 
    OR msg:hang 
    OR msg:timeout 
    OR msg:error 
    OR msg:"Call Trace" 
    OR msg:"hung_task_timeout_sec" 
    OR msg:"waitingfor controller reset" 
    OR msg:"Out of memory" 
    OR msg:Kill 
    OR msg:segfault  
    OR msg:MCE 
    OR msg:threshold 
    OR msg:Uhhuh 
    OR msg:"soft lockup" 
    OR msg:"blocked for"
  ) AND msg:kernel )

  OR msg:"Too many" 
  OR msg:"SIGTERM"
  OR (pri:0 OR pri:1 OR (pri:2 AND NOT msg:"limit notification")) 
  OR (
        (msg:"kernel edac" AND msg:memory)
       OR (msg:"kernel mce" AND NOT msg:banks) 
       OR (msg:"kernel sbridge")
     ) 
  OR ((msg: "kernel: megasas"  OR  msg: "kernel: megaraid_sas")) 
  OR (pri:4 AND (msg:kernel) AND (msg:ffffffff)
)
```

上述关键字主要集中在以下几点:
```
kernel 相关:    包括异常重启信息, 文件系统卡顿信息, OOM 信息, 软锁信息以及 MCE 内存信息;
非 kernel 相关: 包含异常信号信息, 资源限制信息, raid 卡相关信息;
```

## 物理机硬件日志

硬件通常可以使用远控日志来做监控分析, 服务器厂商在远控日志方面通常有很详细的说明(比如 [DELL-LifeCycle-Log](https://www.dell.com/support/manuals/zh-cn/dell-opnmang-sw-v8.1/eemi_13g_v1.2-v1/introduction?guid=guid-8f22a1a9-ac01-43d1-a9d2-390ca6708d5e&lang=en-us)), 一般都会包含日志消息的分类, 级别等. 以 DELL 服务器为例, 下述为简单的消息示例:
```
日志序列,信息ID, 信息ID, 分类, AgentID, 事件级别, 事件时间, 事件消息, FQDD(Fully Qualified Device Descriptor)
1562181,TMP0120,System,SEL,Warning,2024-03-20 11:22:23,The system inlet temperature is greater than the upper warning threshold.,System.Embedded.1
```

> 备注: 分类一般包含 System, System Health, Storage, Audit, Configuration 等, AgentId 等同消息组件的来源, 一般包含 SEL(传感器), iDRAC, RACLOG 等.

常见的信息ID 参考以下, 可以按不通的信息ID 来调整报警策略:

> 更多见: [DELL-LifeCycle-Log](https://www.dell.com/support/manuals/zh-cn/dell-opnmang-sw-v8.1/eemi_13g_v1.2-v1/introduction?guid=guid-8f22a1a9-ac01-43d1-a9d2-390ca6708d5e&lang=en-us)

| 级别 | 信息ID | 消息说明 |
| :- | :- | :- |
|Information|BAT1027|The battery successfully completed a charge cycle|
|Information|PDR10|This message is generated after a rebuild starts on a physical disk.|
|Information|PDR54|This message is generated after a disk media error is corrected on a physical disk.|
|Information|SYS1003|System is performing a CPU reset because of system power off, power on or a warm reset like CTRL-ALT-DEL.|
|Wranning|BAT0000|System settings may be preserved if input power is not removed from the power supplies.|
|Wranning|BAT1033|The controller cannot communicate with the battery. Either the battery was removed, or the contact point between the controller and the battery is degraded.|
|Wranning|CPU0012|Correctable Machine Check Exception detected on CPU arg1.|
|Wranning|FAN0000|The fan is not performing optimally. The fan may be installed improperly or may be failing.|
|Wranning|HWC8607|The data communication with the device NIC in Slot 2 running on the port 1 is lost.|
|Wranning|JCP042|Job XXXX failed because Unable to complete the job because of an error during iDRAC firmware update|
|Wranning|MEM0701|The memory may not be operational. This an early indicator of a possible future uncorrectable error.|
|Wranning|NIC100|The network link is down. Either the network cable is not connected or the network device is not working.|
|Wranning|PDR16|The physical disk is predicted to fail. Many physical disks contain Self Monitoring Analysis and Reporting Technology (SMART). When enabled, SMART monitors the disk health based on indications such as the number of write operations that were performed on the disk.|
|Wranning|PDR5|A physical disk has been removed from the disk group. This alert can also be caused by loose or defective cables or by problems with the enclosure.|
|Wranning|PDR50|The global hot spare is not large enough to protect all virtual disks that reside on the controller.|
|Wranning|TMP0118|Ambient air temperature is too cool.|
|Wranning|TMP0120|Ambient air temperature is too warm.|
|Wranning|VDR8|This message occurs when a physical disk in the disk group was removed or when a physical disk included in a redundant virtual disk fails. Because the virtual disk is redundant (uses mirrored or parity information) and only one physical disk has failed, the virtual disk can be rebuilt.|
|Critical|BAT0021|The xxxx battery has reached the end of its usable life or has failed|
|Critical|HWC2003|The cable may be necessary for proper operation. System functionality may be degraded.|
|Critical|PDR1001|The controller detected a failure on the disk and has taken the disk offline.|
|Critical|PDR1016|The controller detected that the drive was removed.|
|Critical|FAN0001|The fan is not performing optimally. The fan may be installed improperly or may be failing.|
|Critical|PDR3|The RAID Controller may not be able to read/write data to the physical disk drive indicated in the message. This may be due to a failure with the physical disk drive or because the physical disk drive was removed from the system.|
|Critical|PSU0003|The power supply is installed correctly but an input source is not connected or is not functional.|
|Critical|MEM0001|The memory has encountered a uncorrectable error. System performance may be degraded. The operating system and/or applications may fail as a result.|
|Critical|MEM0702|The memory may not be operational. This an early indicator of a possible future uncorrectable error.|
|Critical|UEFI0079|One or more Uncorrectable Memory errors occurred in the previous boot.|
|Critical|VDR34|Background initialization of a virtual disk failed.|
|Critical|VDR7|One or more physical disks included in the virtual disk have failed. If the virtual disk is non-redundant (does not use mirrored or parity data), then the failure of a single physical disk can cause the virtual disk to fail. If the virtual disk is redundant, then more physical disks have failed than you can rebuild using mirrored or parity information.|
|Critical|VDR8|This message occurs when a physical disk in the disk group was removed or when a physical disk included in a redundant virtual disk fails. Because the virtual disk is redundant (uses mirrored or parity information) and only one physical disk has failed, the virtual disk can be rebuilt.|
|Critical|VLT0204|System hardware detected an over voltage or under voltage condition. If multiple voltage exceptions occur consecutively the system may power down in failsafe mode.|

## 其它说明

除了日志报警, 也可以考虑更多的辅助功能, 比如以下列出的几点:
```
1. 日志汇总到 ELK 方便查看;
2. 基于 ELK 做一些主机日志的检查, 尽量覆盖可能没有配置 syslog, 或者 syslog hang 等的情况;
3. 日志可能延迟(系统修改时间或日志接收端阻塞), 报警策略可以基于日志接收时间调整, 而不使用日志产生时间.
```

另外基于日志, 也可以做更多的异常分析, 比如系统意外重启等情况, 可以参考以下说明:

[redhat-206873](https://access.redhat.com/articles/206873)  
[troubleshoot-unexpected-server-shutdown](https://upcloud.com/community/tutorials/troubleshoot-unexpected-server-shutdown/)  

