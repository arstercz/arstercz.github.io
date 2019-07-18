---
id: 47
title: How does innobackupex works
date: 2013-11-11T00:40:04+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=47
permalink: /how-innobackupex-works/
views:
  - "25"
dsq_thread_id:
  - "3465104270"
categories:
  - database
  - performance
tags:
  - innobackup
  - MySQL
  - performance
  - xtrabackup
---
## innobackupex工作流程

innobackupex封装了xtrabackup(InnoDB备份)工具，大致的备份流程如下:
```
|创建备份目录|  ---> |xtrabackup备份InnoDB| --> |全局锁| --> |备份非InnoDB表| --> |释放锁|
```
在 `xtrabackup` 备份 `InnoDB` 过程中，InnoDB 相关变化如下显示:

![备份过程](images/articles/201405/xtrabackup_1.jpg)
上述部分为拷贝文件阶段，文件的变化及拷贝文件工作流程见下图:
![拷文件流程](images/articles/201405/xtrabackup_2.jpg)
在备份InnoDB的过程中，记录的变更保存于xtrabackup_logfile文件，所以在prepare(--apply-log)的时候，重放该部分数据到表空间即可，如下:
![重放过程](images/articles/201405/xtrabackup_3.jpg)
以上就完成了在拷贝文件完成后的那个时间点的全量备份;

### FAQ:

xtrabackup备份开始时，suspend到底有什么作用?
```
130716 12:14:08  innobackupex: Starting ibbackup with command: xtrabackup_55  --defaults-file="/web/mysql/node3306/my.node.cnf"  --defaults-group="mysqld" --backup --suspend-at-end --target-dir=/web/xtrabackup/backups/node3306/2013-07-16_12-14-08 --tmpdir=/dev/shm
innobackupex: Waiting for ibbackup (pid=16924) to suspend
innobackupex: Suspend file '/web/xtrabackup/backups/node3306/2013-07-16_12-14-08/xtrabackup_suspended_2'
```
如下备份信息，为什么要有一个`suspend`的过程,从`innobackupex`代码来看,`suspend`起到了进程同步的作用,即先用xtrabackup备份Innodb，通过suspend作用来检测`xtrabackup`是否备份正常,是则全局锁,备份其他引擎文件,否则`Die`失败;
```
sub backup {
    my $orig_datadir = get_option(\%config, $option_defaults_group, 'datadir');

    # check that we can connect to the database. This done by
    # connecting, issuing a query, and closing the connection.
    mysql_open();
    mysql_close();

    # start ibbackup as a child process
    start_ibbackup();                        -----   开始innodb备份

    # wait for ibbackup to suspend itself
    if (!$option_remote_host) {
        wait_for_ibbackup_suspend();         -----   等待innodb备份成功,否则Die失败,成功则进行到下一步其他引擎的备份;
    }

    # connect to database
    mysql_open();

    if ($option_safe_slave_backup) {
      wait_for_safe_slave();
    }

    # flush tables with read lock
    if (!$option_no_lock) {
        # make a prep copy before locking tables, if using rsync
        backup_files(1);

        # flush tables with read lock
        mysql_lockall();
    }
    ....
}
......
sub wait_for_ibbackup_suspend {
    print STDERR "$prefix Waiting for ibbackup (pid=$ibbackup_pid) to suspend\n";
    print STDERR "$prefix Suspend file '$suspend_file'\n\n";
    for (;;) {
        sleep 2;
        last if -e $suspend_file;           -----检测是否存在suspend文件, 是则跳到最后一次循环;

        # check that ibbackup child process is still alive
        if ($ibbackup_pid == waitpid($ibbackup_pid, &WNOHANG)) {    ---- waitpid检测start_ibbackup()是否完成,异常则Die失败退出;
            $ibbackup_pid = '';
            Die "ibbackup child process has died";
        }
    }
    $now = current_time();
    open XTRABACKUP_PID, "> $option_tmpdir/$xtrabackup_pid_file";
    print XTRABACKUP_PID $ibbackup_pid;
    close XTRABACKUP_PID;
    print STDERR "\n$now  $prefix Continuing after ibbackup has suspended\n";
}

sub resume_ibbackup {
    print STDERR "$prefix Resuming ibbackup\n\n";         
    unlink $suspend_file || Die "Failed to delete '$suspend_file': $!";                -----删除suspend在repare这步;

    # wait for ibbackup to finish
    waitpid($ibbackup_pid, 0);
    unlink "$option_tmpdir/$xtrabackup_pid_file"; 
    $ibbackup_pid = '';
    return $CHILD_ERROR >> 8;
}
```
