---
id: 1150
title: linux 系统 xfs_vm_releasepage 警告问题处理
date: 2019-03-27T12:21:15+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1150
permalink: '/centos-7-xfs_vm_releasepage-%e8%ad%a6%e5%91%8a%e9%97%ae%e9%a2%98%e5%a4%84%e7%90%86/'
categories:
  - bugs-report
  - system
tags:
  - kernel
  - xfs
---
<h2>问题说明</h2>

最近的几台机器在同一天的不同时段都出现以下警告信息:

<pre><code>Mar 26 20:55:03 host1 kernel: WARNING: at fs/xfs/xfs_aops.c:1045 xfs_vm_releasepage+0xcb/0x100 [xfs]()
Mar 26 20:55:03 host1 kernel: Modules linked in: nf_conntrack_ipv4 nf_defrag_ipv4 xt_conntrack nf_conntrack iptable_filter ip_tables ebtable_filter ebtables ip6table_
filter ip6_tables devlink bridge stp llc xt_multiport sunrpc dm_mirror dm_region_hash dm_log dm_mod intel_powerclamp coretemp intel_rapl iosf_mbi kvm_intel kvm irqbypa
ss crc32_pclmul ghash_clmulni_intel aesni_intel lrw gf128mul glue_helper ablk_helper cryptd iTCO_wdt iTCO_vendor_support dcdbas ipmi_devintf ipmi_si sg pcspkr ipmi_msg
handler shpchp i2c_i801 lpc_ich nfit libnvdimm acpi_power_meter kgwttm(OE) xfs libcrc32c sd_mod crc_t10dif crct10dif_generic crct10dif_pclmul crct10dif_common crc32c_i
ntel mgag200 drm_kms_helper igb syscopyarea sysfillrect sysimgblt ptp fb_sys_fops ttm pps_core dca ahci drm i2c_algo_bit libahci megaraid_sas i2c_core libata
Mar 26 20:55:03 host1 kernel: fjes [last unloaded: nf_defrag_ipv4]
Mar 26 20:55:03 host1 kernel: CPU: 10 PID: 224 Comm: kswapd0 Tainted: G           OE  ------------   3.10.0-514.21.2.el7.x86_64 #1
Mar 26 20:55:03 host1 kernel: Hardware name: Dell Inc. PowerEdge R640/0W23H8, BIOS 1.3.7 02/08/2018
Mar 26 20:55:03 host1 kernel: 0000000000000000 00000000e02a0d05 ffff88103c7ebaa0 ffffffff81687073
Mar 26 20:55:03 host1 kernel: ffff88103c7ebad8 ffffffff81085cb0 ffffea0000687620 ffffea0000687600
Mar 26 20:55:03 host1 kernel: ffff88004a71daf8 ffff88103c7ebda0 ffffea0000687600 ffff88103c7ebae8
Mar 26 20:55:03 host1 kernel: Call Trace:
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81687073&gt;] dump_stack+0x19/0x1b
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81085cb0&gt;] warn_slowpath_common+0x70/0xb0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81085dfa&gt;] warn_slowpath_null+0x1a/0x20
Mar 26 20:55:03 host1 kernel: [&lt;ffffffffa038bfdb&gt;] xfs_vm_releasepage+0xcb/0x100 [xfs]
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81180b22&gt;] try_to_release_page+0x32/0x50
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81196ad6&gt;] shrink_active_list+0x3d6/0x3e0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81196ed1&gt;] shrink_lruvec+0x3f1/0x770
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff811972c6&gt;] shrink_zone+0x76/0x1a0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff8119857c&gt;] balance_pgdat+0x48c/0x5e0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81198843&gt;] kswapd+0x173/0x450
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff810b1b20&gt;] ? wake_up_atomic_t+0x30/0x30
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff811986d0&gt;] ? balance_pgdat+0x5e0/0x5e0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff810b0a4f&gt;] kthread+0xcf/0xe0
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff810b0980&gt;] ? kthread_create_on_node+0x140/0x140
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff81697698&gt;] ret_from_fork+0x58/0x90
Mar 26 20:55:03 host1 kernel: [&lt;ffffffff810b0980&gt;] ? kthread_create_on_node+0x140/0x140
Mar 26 20:55:03 host1 kernel: ---[ end trace 24823c5c7a1ea2be ]---
</code></pre>

这几台机器的 <code>kernel</code> 及应用程序等崩溃信息由 abrtd 服务接管, 可以通过 <code>abrt-cli</code> 查看概要信息:

<pre><code># abrt-cli list --since 1547518209
id 2181dce8f72761585cb6a904dbff1806c1315c27
reason:         WARNING: at fs/xfs/xfs_aops.c:1045 xfs_vm_releasepage+0xcb/0x100 [xfs]()
time:           Sat 23 Mar 2019 08:30:45 PM CST
cmdline:        BOOT_IMAGE=/boot/vmlinuz-3.10.0-514.16.1.el7.x86_64 root=/dev/sda1 ro crashkernel=auto net.ifnames=0 biosdevname=0
package:        kernel
uid:            0 (root)
count:          1
Directory:      /var/spool/abrt/oops-2019-03-23-20:30:45-163925-0
</code></pre>

内核版本如下:

<pre><code>Centos7
Linux host1 3.10.0-514.21.2.el7.x86_64
</code></pre>

<h2>分析处理</h2>

<h3>红帽知识库</h3>

参考红帽知识库文档, xfs 的这类警告信息在 xfs 模块遍历代码路径的时候会打印该信息, 不影响主机使用. 可升级内核到 <code>kernel-3.10.0-693.el7</code> 版本避免该警告信息, 详细参见: <a href="https://access.redhat.com/solutions/2893711">redhat-access-2893711</a>

<pre><code>Root Cause:

The messages were informational and they do not affect the system in a negative manner. They are seen because the XFS module is traversing through XFS code path.
</code></pre>

<h3>代码分析</h3>

红帽知识库中并未提到内存回收的相关信息, 不过从堆栈信息来看, 像是因为内核回收内存而引起的, 查看对应时间点的内存使用情况如下所示:

<pre><code>04:30:01 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact   kbdirty
......
08:40:01 PM    513940 130976220     99.61       876 104616380  28610584     21.76  92439660  34840920       524
08:50:01 PM    479896 131010264     99.64       876 104666496  28557292     21.72  92513872  34804240       400
09:00:01 PM    455948 131034212     99.65       876 104675712  28588852     21.74  92418724  34926132       572
09:10:01 PM    556980 130933180     99.58       876 104610352  28552656     21.71  94287212  32983892       900

# sysctl vm.min_free_kbytes
vm.min_free_kbytes = 90112
</code></pre>

20:50 到 21:00 之间的可用内存并没有增加, 这意味着系统可能没有做内存回收操作, 我们按照 kernel 日志的堆栈信息来看函数的调用关系:

<pre><code>shrink_active_list -&gt; try_to_release_page -&gt; xfs_vm_releasepage

//source/mm/filemap.c
3225 int try_to_release_page(struct page *page, gfp_t gfp_mask)
3226 {
3227     struct address_space * const mapping = page-&gt;mapping;
......
3233     if (mapping &amp;&amp; mapping-&gt;a_ops-&gt;releasepage)
3234         return mapping-&gt;a_ops-&gt;releasepage(page, gfp_mask);    xfs_vm_releasepage
3235     return try_to_free_buffers(page);
3236 }

//source/fs/xfs/xfs_aops.c
1034 STATIC int
1035 xfs_vm_releasepage(
1036     struct page     *page,
1037     gfp_t           gfp_mask)
1038 {
1039     int         delalloc, unwritten;
1040 
1041     trace_xfs_releasepage(page-&gt;mapping-&gt;host, page, 0, 0);
1042 
1043     xfs_count_page_state(page, &amp;delalloc, &amp;unwritten);
1044 
1045     if (WARN_ON_ONCE(delalloc))
1046         return 0;
1047     if (WARN_ON_ONCE(unwritten))
1048         return 0;
1049 
1050     return try_to_free_buffers(page);
1051 }
......
1827 const struct address_space_operations xfs_address_space_operations = {
1833     .releasepage        = xfs_vm_releasepage,
</code></pre>

对应 <code>kernel</code> 日志 <code>kernel: WARNING: at fs/xfs/xfs_aops.c:1045</code> 即可看出源文件 <code>source/fs/xfs/xfs_aops.c</code> 的 1045 行打印出了该堆栈信息, 实际上并没有执行 <code>try_to_free_buffers</code> 就已经返回:

<pre><code>1045     if (WARN_ON_ONCE(delalloc))
1046         return 0;
</code></pre>

<code>WARN_ON_ONCE</code> 则相对简单, 在源文件 <code>source/include/asm-generic/bug.h</code>  即可找到:

<pre><code>73 #define __WARN()        warn_slowpath_null(__FILE__, __LINE__)

85 #define WARN_ON(condition) ({                       \
...
88         __WARN();                       \

136 #define WARN_ON_ONCE(condition) ({              \
....
140     if (unlikely(__ret_warn_once))              \
141         if (WARN_ON(!__warned))             \
</code></pre>

<code>__WARN</code> 函数则调用了堆栈信息里的 <code>warn_slowpath_null</code> 函数, 进而调用 <code>warn_slowpath_common</code> 函数打印了堆栈信息:

<pre><code>//source/kernel/panic.c
517 void warn_slowpath_null(const char *file, int line)
518 {
519     warn_slowpath_common(file, line, __builtin_return_address(0),
520                  TAINT_WARN, NULL);
521 }

463 static void warn_slowpath_common(const char *file, int line, void *caller,
464                  unsigned taint, struct slowpath_args *args)
465 {
466     disable_trace_on_warning();
467 
468     printk(KERN_WARNING "------------[ cut here ]------------\n");
469     printk(KERN_WARNING "WARNING: at %s:%d %pS()\n", file, line, caller);
470 
471     if (args)
472         vprintk(args-&gt;fmt, args-&gt;args);
......
485     print_modules();
486     dump_stack();
487     print_oops_end_marker();
</code></pre>

我们大致可以看出这个堆栈信息只是警告, 和红帽知识库中描述的一致, 并不影响主机的使用.

<h2>总结说明</h2>

从上面源文件的函数来看, 只要 <code>kswapd</code> 内存回收的时候调用了 <code>xfs_vm_releasepage</code> 就有可能打印堆栈信息, 如果打印堆栈则不会执行 <code>try_to_free_buffers</code> 操作, 所以查看内存使用的时候可用内存并没有增加. 如果不希望出现堆栈信息可以开启 <code>disable_trace_on_warning</code> 函数对应的 <code>kernel.traceoff_on_warning</code> 内核参数关闭堆栈提示, 不过关闭后其他的内核信息也就不会再打印, 所以从这方面来看只有升级内核版本才会避免出现这个信息.