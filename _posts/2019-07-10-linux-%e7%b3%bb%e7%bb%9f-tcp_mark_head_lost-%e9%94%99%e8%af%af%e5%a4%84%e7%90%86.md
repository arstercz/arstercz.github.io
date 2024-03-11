---
id: 1200
title: linux 系统 tcp_mark_head_lost 错误处理
date: 2019-07-10T20:09:43+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1200
permalink: '/linux-%e7%b3%bb%e7%bb%9f-tcp_mark_head_lost-%e9%94%99%e8%af%af%e5%a4%84%e7%90%86/'
categories:
  - system
tags:
  - kernel
---
### 问题说明

近期一台主机报以下 kernel 信息:
```
Jul 8 10:47:42 cztest kernel: ------------[ cut here ]------------
Jul 8 10:47:42 cztest kernel: WARNING: at net/ipv4/tcp_input.c:2269 tcp_mark_head_lost+0x113/0x290()
Jul 8 10:47:42 cztest kernel: Modules linked in: iptable_filter ip_tables binfmt_misc cdc_ether usbnet mii xt_multiport dm_mirror dm_region_hash dm_log dm_mod intel_powerclamp coretemp intel_rapl iosf_mbi kvm_intel kvm irqbypass crc32_p
clmul ghash_clmulni_intel aesni_intel lrw gf128mul glue_helper ablk_helper cryptd ipmi_ssif ipmi_devintf ipmi_si mei_me pcspkr iTCO_wdt mxm_wmi iTCO_vendor_support dcdbas mei sg sb_edac edac_core ipmi_msghandler shpchp lpc_ich wmi acpi_p
ower_meter xfs libcrc32c sd_mod crc_t10dif crct10dif_generic mgag200 drm_kms_helper crct10dif_pclmul crct10dif_common syscopyarea crc32c_intel sysfillrect sysimgblt fb_sys_fops igb ttm ptp drm ahci pps_core libahci dca i2c_algo_bit libat
a megaraid_sas i2c_core fjes [last unloaded: ip_tables]
Jul 8 10:47:42 cztest kernel: CPU: 10 PID: 0 Comm: swapper/10 Tainted: G        W      ------------   3.10.0-514.16.1.el7.x86_64 #1
Jul 8 10:47:42 cztest kernel: Hardware name: Dell Inc. PowerEdge R630/02C2CP, BIOS 2.3.4 11/08/2016
Jul 8 10:47:42 cztest kernel: 0000000000000000 dd79fe633eacd853 ffff88103e743880 ffffffff81686ac3
Jul 8 10:47:42 cztest kernel: ffff88103e7438b8 ffffffff81085cb0 ffff8806d5c57800 ffff88010a4e6c80
Jul 8 10:47:42 cztest kernel: 0000000000000001 00000000f90e778c 0000000000000001 ffff88103e7438c8
Jul 8 10:47:42 cztest kernel: Call Trace:
Jul 8 10:47:42 cztest kernel: <IRQ>  [<ffffffff81686ac3>] dump_stack+0x19/0x1b
Jul 8 10:47:42 cztest kernel: [<ffffffff81085cb0>] warn_slowpath_common+0x70/0xb0
Jul 8 10:47:42 cztest kernel: [<ffffffff81085dfa>] warn_slowpath_null+0x1a/0x20
Jul 8 10:47:42 cztest kernel: [<ffffffff815c3663>] tcp_mark_head_lost+0x113/0x290
Jul 8 10:47:42 cztest kernel: [<ffffffff815c3f47>] tcp_update_scoreboard+0x67/0x80
Jul 8 10:47:42 cztest kernel: [<ffffffff815c964d>] tcp_fastretrans_alert+0x6dd/0xb50
Jul 8 10:47:42 cztest kernel: [<ffffffff815ca49d>] tcp_ack+0x8dd/0x12e0
Jul 8 10:47:42 cztest kernel: [<ffffffff815cb3a8>] tcp_rcv_established+0x118/0x760
Jul 8 10:47:42 cztest kernel: [<ffffffff815d5f8a>] tcp_v4_do_rcv+0x10a/0x340
Jul 8 10:47:42 cztest kernel: [<ffffffff812a84c6>] ? security_sock_rcv_skb+0x16/0x20
Jul 8 10:47:42 cztest kernel: [<ffffffff815d76d9>] tcp_v4_rcv+0x799/0x9a0
Jul 8 10:47:42 cztest kernel: [<ffffffffa0140036>] ? iptable_filter_hook+0x36/0x80 [iptable_filter]
Jul 8 10:47:42 cztest kernel: [<ffffffff815b1094>] ip_local_deliver_finish+0xb4/0x1f0
Jul 8 10:47:42 cztest kernel: [<ffffffff815b1379>] ip_local_deliver+0x59/0xd0
Jul 8 10:47:42 cztest kernel: [<ffffffff815b0fe0>] ? ip_rcv_finish+0x350/0x350
Jul 8 10:47:42 cztest kernel: [<ffffffff815b0d1a>] ip_rcv_finish+0x8a/0x350
Jul 8 10:47:42 cztest kernel: [<ffffffff815b16a6>] ip_rcv+0x2b6/0x410
Jul 8 10:47:42 cztest kernel: [<ffffffff815700d2>] __netif_receive_skb_core+0x582/0x800
Jul 8 10:47:42 cztest kernel: [<ffffffff815dc694>] ? tcp4_gro_receive+0x134/0x1b0
Jul 8 10:47:42 cztest kernel: [<ffffffff811dc861>] ? __slab_free+0x81/0x2f0
Jul 8 10:47:42 cztest kernel: [<ffffffff81570368>] __netif_receive_skb+0x18/0x60
Jul 8 10:47:42 cztest kernel: [<ffffffff815703f0>] netif_receive_skb_internal+0x40/0xc0
Jul 8 10:47:42 cztest kernel: [<ffffffff81571578>] napi_gro_receive+0xd8/0x130
Jul 8 10:47:42 cztest kernel: [<ffffffffa018b237>] igb_clean_rx_irq+0x387/0x700 [igb]
Jul 8 10:47:42 cztest kernel: [<ffffffff8155e862>] ? skb_release_data+0xf2/0x140
Jul 8 10:47:42 cztest kernel: [<ffffffffa018b933>] igb_poll+0x383/0x770 [igb]
Jul 8 10:47:42 cztest kernel: [<ffffffff815d3120>] ? tcp_write_timer_handler+0x200/0x200
Jul 8 10:47:42 cztest kernel: [<ffffffff81570c00>] net_rx_action+0x170/0x380
Jul 8 10:47:42 cztest kernel: [<ffffffff8108f63f>] __do_softirq+0xef/0x280
Jul 8 10:47:42 cztest kernel: [<ffffffff81698c1c>] call_softirq+0x1c/0x30
Jul 8 10:47:42 cztest kernel: [<ffffffff8102d365>] do_softirq+0x65/0xa0
Jul 8 10:47:42 cztest kernel: [<ffffffff8108f9d5>] irq_exit+0x115/0x120
Jul 8 10:47:42 cztest kernel: [<ffffffff816997b8>] do_IRQ+0x58/0xf0
Jul 8 10:47:42 cztest kernel: [<ffffffff8168e86d>] common_interrupt+0x6d/0x6d
Jul 8 10:47:42 cztest kernel: <EOI>  [<ffffffff81514a22>] ? cpuidle_enter_state+0x52/0xc0
Jul 8 10:47:42 cztest kernel: [<ffffffff81514b69>] cpuidle_idle_call+0xd9/0x210
Jul 8 10:47:42 cztest kernel: [<ffffffff810350ee>] arch_cpu_idle+0xe/0x30
Jul 8 10:47:42 cztest kernel: [<ffffffff810e82a5>] cpu_startup_entry+0x245/0x290
Jul 8 10:47:42 cztest kernel: [<ffffffff8104f07a>] start_secondary+0x1ba/0x230
Jul 8 10:47:42 cztest kernel: ---[ end trace 6bc65b0c591c1794 ]---
```

主机环境如下:
```
      System | Dell Inc.; PowerEdge R620;
    Platform | Linux
      Kernel | Centos 3.10.0-514.16.1.el7.x86_64
Total Memory | 64G
```

### 处理说明

堆栈的打印过程类似于 [xfs 告警处理]{{ site.baseurl }}/centos-7-xfs_vm_releasepage-%e8%ad%a6%e5%91%8a%e9%97%ae%e9%a2%98%e5%a4%84%e7%90%86/) , 大致的过程为内核开启 `sack`, `fack` 功能后, 网络传输过程中需要的快速重传和选择性重传会通过 `tcp_input.c` 文件的 `tcp_mark_head_lost` 函数进行处理, 其主要标记传输过程中丢失的报文的数量, 如下所示, 系统报的 kernel 堆栈信息由 `tcp_mark_head_lost` 函数中的 `tcp_verify_left_out` 函数调用触发:

```
// source/include/net/tcp.h 

#define tcp_verify_left_out(tp) WARN_ON(tcp_left_out(tp) > tp->packets_out)

static inline unsigned int tcp_left_out(const struct tcp_sock *tp)
{
        return tp->sacked_out + tp->lost_out;
}

// source/include/asm-generic/bug.h 

#define __WARN()        warn_slowpath_null(__FILE__, __LINE__)

#ifndef WARN_ON
#define WARN_ON(condition) ({                                           \
                __WARN();                                               \
})
#endif



// source/net/ipv4/tcp_input.c

/* Detect loss in event "A" above by marking head of queue up as lost.
 * For FACK or non-SACK(Reno) senders, the first "packets" number of segments
 * are considered lost. For RFC3517 SACK, a segment is considered lost if it
 * has at least tp->reordering SACKed seqments above it; "packets" refers to
 * the maximum SACKed segments to pass before reaching this limit.
 */
static void tcp_mark_head_lost(struct sock *sk, int packets, int mark_head)
{
        struct tcp_sock *tp = tcp_sk(sk);
        ....
        tcp_verify_left_out(tp);  // trigger dump_stack
}

...
static void tcp_update_scoreboard(struct sock *sk, int fast_rexmit)
{
        struct tcp_sock *tp = tcp_sk(sk);

        if (tcp_is_reno(tp)) {
                tcp_mark_head_lost(sk, 1, 1);
        } else if (tcp_is_fack(tp)) {
                int lost = tp->fackets_out - tp->reordering;
                if (lost <= 0)
                        lost = 1;
                tcp_mark_head_lost(sk, lost, 0);
        } else {
                int sacked_upto = tp->sacked_out - tp->reordering;
                if (sacked_upto >= 0)
                        tcp_mark_head_lost(sk, sacked_upto, 0);
                else if (fast_rexmit)
                        tcp_mark_head_lost(sk, 1, 1);
        }
}
```

从 [redhat-536483](https://access.redhat.com/solutions/536483) 中描述的来看, 这种错误信息一般是 `tcp bug` 引起的, 在内核使用已经释放的 `tcp socket buffer` 链表的时候就可能触发:
```
Root Cause
A use after free issue related to the TCP kernel socket buffer linked list. Thus it is a bug in the TCP kernel code. Although the bug is in TCP kernel code, but it could get triggered in multiple ways. It could get triggered due to NFS, or due to even an application(say java process).
```

### 处理方式

#### 升级 kernel

如下所示, redhat 在 `3.10.0-520` 版本可能修复了 `tcp_*` 相关函数的 `use after free` 相关的 bug, 可以尝试升级处理该问题:
**centos 7.x changelog**
```
* Thu Nov 03 2016 Rafael Aquini <aquini@redhat.com> [3.10.0-520.el7]
- [net] tcp: fix use after free in tcp_xmit_retransmit_queue() (Mateusz Guzik) [1379531] {CVE-2016-6828}
```

#### 关闭 fack/sack 功能

从红帽知识库的文档来看, `tcp_mark_head_lost` 函数主要用来标记快速重传和选择确认的过程中丢失的报文数量, 所以或许可以临时关闭 `fack/sack` 参数避免该问题的出现:
```
sysctl -w net.ipv4.tcp_fack=0
sysctl -w net.ipv4.tcp_sack=0
```

可以优先尝试第二种方式, 如果还有问题再考虑升级 kernel 版本.

### 参考

[redhat-536483](https://access.redhat.com/solutions/536483)  
[bug-1367091](https://bugzilla.redhat.com/show_bug.cgi?id=1367091)  
[cve-2016-6828](https://access.redhat.com/security/cve/cve-2016-6828)  
[kernel-commit](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=bb1fceca22492109be12640d49f5ea5a544c6bb4)  
