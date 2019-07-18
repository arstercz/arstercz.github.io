---
id: 1167
title: linux 系统 bad pmd 错误处理
date: 2019-05-08T10:30:15+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1167
permalink: '/linux-%e7%b3%bb%e7%bb%9f-bad-pmd-%e9%94%99%e8%af%af%e5%a4%84%e7%90%86/'
categories:
  - system
tags:
  - kernel
  - pmd
---
## 问题说明

近期一台主机报以下 `kernel` 警告信息:

```
May  4 22:19:52 cztest kernel: mm/memory.c:413: bad pmd ffff9f1b3127e710(80000010ba8008e7)
May  4 22:19:52 cztest telegraf: fatal error: s.freeindex > s.nelems
May  4 22:19:52 cztest telegraf: goroutine 33796712 [running]:
......
May  4 22:19:52 cztest kernel: ------------[ cut here ]------------
May  4 22:19:52 cztest kernel: WARNING: CPU: 16 PID: 1646 at mm/mmap.c:3042 exit_mmap+0x196/0x1a0
May  4 22:19:52 cztest kernel: Modules linked in: ts_bm xt_string binfmt_misc bonding ipt_REJECT nf_reject_ipv4 nf_conntrack_ipv4 nf_defrag_ipv4 xt_length xt_conntrack nf_conntrack iptable_filter dm_mirror dm_region_hash dm_log dm_mod skx_edac intel_powerclamp coretemp intel_rapl iosf_mbi kvm_intel kvm iTCO_wdt irqbypass iTCO_vendor_support crc32_pclmul ghash_clmulni_intel dcdbas aesni_intel lrw gf128mul glue_helper ablk_helper cryptd pcspkr sg mei_me mei i2c_i801 shpchp lpc_ich ipmi_si ipmi_devintf ipmi_msghandler nfit libnvdimm acpi_power_meter ip_tables xfs libcrc32c sd_mod crc_t10dif crct10dif_generic mgag200 drm_kms_helper syscopyarea sysfillrect sysimgblt fb_sys_fops ttm crct10dif_pclmul crct10dif_common crc32c_intel ahci igb drm libahci megaraid_sas ptp libata pps_core dca i2c_algo_bit i2c_core
May  4 22:19:52 cztest kernel: CPU: 16 PID: 1646 Comm: telegraf Kdump: loaded Not tainted 3.10.0-862.3.3.el7.x86_64 #1
May  4 22:19:52 cztest kernel: Hardware name: Dell Inc. PowerEdge R640/0W23H8, BIOS 1.4.5 03/30/2018
May  4 22:19:52 cztest kernel: Call Trace:
May  4 22:19:52 cztest kernel: [<ffffffff8fd0e78e>] dump_stack+0x19/0x1b
May  4 22:19:52 cztest kernel: [<ffffffff8f691998>] __warn+0xd8/0x100
May  4 22:19:52 cztest kernel: [<ffffffff8f691add>] warn_slowpath_null+0x1d/0x20
May  4 22:19:52 cztest kernel: [<ffffffff8f7ce536>] exit_mmap+0x196/0x1a0
May  4 22:19:52 cztest kernel: [<ffffffff8f95969a>] ? __get_user_8+0x1a/0x29
May  4 22:19:52 cztest kernel: [<ffffffff8f68e3b7>] mmput+0x67/0xf0
May  4 22:19:52 cztest kernel: [<ffffffff8f697a55>] do_exit+0x285/0xa40
May  4 22:19:52 cztest kernel: [<ffffffff8f70450f>] ? futex_wait+0x11f/0x280
May  4 22:19:52 cztest kernel: [<ffffffff8f6cbdcd>] ? ttwu_do_activate.constprop.93+0x5d/0x70
May  4 22:19:52 cztest kernel: [<ffffffff8f69828f>] do_group_exit+0x3f/0xa0
May  4 22:19:52 cztest kernel: [<ffffffff8f6a8b3e>] get_signal_to_deliver+0x1ce/0x5e0
May  4 22:19:52 cztest kernel: [<ffffffff8f62a527>] do_signal+0x57/0x6e0
May  4 22:19:52 cztest kernel: [<ffffffff8f7062c6>] ? do_futex+0x106/0x5a0
May  4 22:19:52 cztest kernel: [<ffffffff8f6a5dcb>] ? recalc_sigpending+0x1b/0x70
May  4 22:19:52 cztest kernel: [<ffffffff8f62ac22>] do_notify_resume+0x72/0xc0
May  4 22:19:52 cztest kernel: [<ffffffff8fd20b8f>] int_signal+0x12/0x17
May  4 22:19:52 cztest kernel: ---[ end trace 4cb1ecaa23122880 ]---
May  4 22:22:20 cztest kernel: BUG: Bad rss-counter state mm:ffff9f1b3aa28640 idx:1 val:512
```

该主机环境如下:
```
      System | Dell Inc.; PowerEdge R640;
    Platform | Linux
      Kernel | Centos7-3.10.0-862.3.3
Total Memory | 128G
```

## 处理说明

Linux 通过多级页表完成虚拟地址到实际物理地址的转换, 以实现支持更大的内存. `2.6.11` 内核版本之后包含以下四种级别:
```
PGD: 全局页目录(Page Global Directory)
PUD: 上级页目录(Page Upper Directory)
PMD: 中间页目录(Page Middle Directory)
PTE: 页表(PTE)
```
![four-level-pt.png]({{ site.baseurl }}/images/articles/201905/four-level-pt.png) 

如上图所示,每个运行的进程都有一个指向 `PGD` 的指针, `PGD` 的每个条目指向一个 `PUD`, `PUD` 的每个条目指向一个 `PMD`, `PMD` 的每个条目指向一个 `PTE`, `PTE` 的每个条目指向一个页面的物理首地址. 内核遍历每个级别, 如果有条目无效则打印出对应的  `bad p{g,u,m}d`  消息.这类错误没有恢复的话, 应用程序在访问其虚拟地址就会出错, 对应的程序也会被内核杀掉. 正如上述错误提示的, `telegraf` 进程异常退出. 

从 `mm/mmap.c` 中的代码可以看出, 出现上述错误是处于释放页表的过程中出现的, 如下所示, 上述的错误意味着其中的一个 `PMD` 出现了错误:
```
# source/arch/x86/include/asm/pgtable_64.h
#define pmd_ERROR(e)                                    \
        pr_err("%s:%d: bad pmd %p(%016lx)\n",           \
               __FILE__, __LINE__, &(e), pmd_val(e))


# source/mm/memory.c
void pmd_clear_bad(pmd_t *pmd)
{
        pmd_ERROR(*pmd);
        pmd_clear(pmd);
}

static inline int pmd_none_or_clear_bad(pmd_t *pmd)
{
        if (pmd_none(*pmd))
                return 1;
        if (unlikely(pmd_bad(*pmd))) {
                pmd_clear_bad(pmd);
                return 1;
        }
        return 0;
}

free_pgtables -> free_pgd_range -> free_pud_range -> free_pmd_range -> free_pte_range

# source/mm/mmap.c
/* Release all mmaps. */
void exit_mmap(struct mm_struct *mm)
{
...
        free_pgtables(&tlb, vma, FIRST_USER_ADDRESS, USER_PGTABLES_CEILING);
        tlb_finish_mmu(&tlb, 0, -1);
```


### 解决方式

参考 [rehat-41282](https://access.redhat.com/solutions/41282) 提供的方式, 我们使用 `memtest86+` 来检查 `RAM` 是否存在内存问题. 如果检查正常则继续使用该主机运行服务, 后续继续保留观察. 如果有错误则根据错误提示更换对应的物理内存. 如果不方便测试就需要多观察报错的主机, 查看是否有 `edac` 或 `mcelog` 相关的错误, 报错相关的进程都会被系统杀掉.

`memtest86+` 的使用参考 [redhat-15693](https://access.redhat.com/solutions/15693):
```
# yum install memtest86+

# memtest-setup 

# grub2-mkconfig -o /boot/grub2/grub.cfg

  After reboot, the GRUB menu will list memtest. Select this item and it will start testing the memory.

  memtest86+ may not always find all memory problems. It is possible that the system memory can have a fault that memtest86+ does not detect.
```
如下所示, `memtest86+` 会进行多组测试, 持续时间会比较长(目测需要4个小时), 可通过 `ESC` 键取消测试:
![memtest]({{ site.baseurl }}/images/articles/201905/memtest.png)

## 参考

[redhat-41282](https://access.redhat.com/solutions/41282)
[redhat-15693](https://access.redhat.com/solutions/15693)
[lwn-117749](https://lwn.net/Articles/117749/)
[kernel-understand006](https://www.kernel.org/doc/gorman/html/understand/understand006.html)
