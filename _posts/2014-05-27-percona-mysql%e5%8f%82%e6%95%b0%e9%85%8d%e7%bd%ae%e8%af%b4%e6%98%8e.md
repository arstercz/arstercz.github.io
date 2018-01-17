---
id: 127
title: MySQL 管理规范
date: 2014-05-27T17:56:56+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=127
permalink: '/percona-mysql%e5%8f%82%e6%95%b0%e9%85%8d%e7%bd%ae%e8%af%b4%e6%98%8e/'
views:
  - "50"
tagline_text_field:
  - ""
dsq_thread_id:
  - "3483697366"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - MySQL
  - percona
---
<b>参数配置说明</b>

<b>1.概述</b>

本文档目的在于标准化线上MySQL数据库的安装和管理，以保证数据库环境的统一，便于DBA管理及维护。

笔者详细介绍Percona MySQL Server的参数信息, 从个人角度上看参数选项可以分为必选项和可选项(仅供参考), 对一些需要经常设置的变量建议放到cnf配置文件中(比如expire_logs_days,read_only等)。
 
目前为止,MySQL安装方式主要有:RPM/DEB, Binary, Source Code, Repository。 RPM/DEB方式安装简单、方便，在发布前已经经过了极为严格的测试, 稳定性和安全性都有所保证，升级方面只需考虑有重要bug、更新等高版本,没必要有更新就升级；Binary方式相对独立，不需要依赖过多的库文件等,在安装和升级方面很方便，另外也利于线上环境的批量部署,同样Binary方式在发布前也经过了严格的测试；Source Code安装方式适合有定制功能或更改参数默认信息的需求，一般没有特殊需求的业务可以不采用源码安装的方式；Repository为第三方厂商发布的仓库版本，比如percona yum/apt版本,该方式的优点等同RPM/DEB方式。

<b>2.安装之前</b>

软件获取: 采用第三方厂商percona XtraDB分支版本，见 <a href="www.percona.com">www.percona.com</a> , 5.1版本不再维护, 最新为5.1.73版本. 5.5 和 5.6 可以选用最新的版本.

安装条件: 鉴于不同RAID级别对数据库性能和安全方面的影响，线上环境应该统一采用RAID10级别，如果硬盘不够可降级为RAID1或RAID5级别(RAID0不安全)。

RAID卡型号选取带有Cache功能的卡，如DELL的H700或H710P。

磁盘调度算法:专用数据库采用deadline方式，非专用取默认cfg方式。

<b>3.必选项</b>

<pre>
[mysqld_safe] 
</pre>
mysqld_safe区域选项参数设置，线上强制以mysql safe方式启动MySQL Server,可在该区域设置log error等输出信息，但不做强制要求。

<pre>
syslog                              
</pre> 
将error信息输出到syslog(/var/log/message)中，设置该选项初衷在于利用LogAnalyzer工具监控错误信息起到及时告警的作用，缺点是对历史错误信息难以追踪。

<pre>
syslog-tag = XXXX                   
</pre> 
error信息输出到syslog时增加一个标签后缀，此选项在一台主机多实例环境下达到区分来源实例的目的。
<!--more-->
<pre>
[mysqld]                              
</pre> 
MySQL Server端启动选项

<pre>
server-id = XXXXXX 
</pre> 
 XXXX+(3<<16)   #保证server-id的唯一性即可，怎么唯一不做强制性要求，线上通过这样的计算方式  server-id = 端口号 + 内网ip地址的最后8位左移16位，举例来说  199914  = 3306+(3<<16), (3<<16)等效于00000011 0000 0000 0000 0000转为十进制为196608

<pre>
port      = 3306                    
</pre> 
Server 监听端口

<pre>
datadir = /web/mysql/node3306/data            
</pre> 
数据目录（不做其它参数设置，则共享表空间，undo日志，binlog日志，新建的实例等都存放到该目录下）。

<pre>
pid-file = /web/mysql/node3306/data/mysql.pid 
</pre> 
pid文件保存路径，mysql.pid文件保存MySQL Server启动时的进程ID，正常关闭数据库，pid文件消失。如果非正常关闭，pid文件依旧存在，MySQL在启动的时候检查pid文件，存在则报错，否则正常启动，可手动删除pid文件避免该问题。

<pre>
socket = /web/mysql/node3306/data/s3306       
</pre> 
socket文件路径位置，指定socket名为s3306，socket应用于本地的连接，远程无效。

<pre>
back_log = xxx                      
</pre> 
指定MySQL 所能拥有的未处理请求的数量，该参数限制了在一段时间内存在大量请求的情况下，请求队列中能够接受请求的数量xxx，多余的请求则停止响应或丢弃。该值不要超过内核参数 /proc/sys/net/ipv4/tcp_max_syn_backlog。

<pre>
max_connections    = 1000           
</pre> 
Server端同时可处理的最大连接数，一个线程算一个连接(一个process)，根据线上环境一般实例都在300以内，考虑高峰、扩容等因素可设置到1000.线程连接超过指定值则出现 ERROR: Can't create a new thread,可通过临时增加进程limit缓解：echo -n "Max processes=SOFT_LIMIT:HARD_LIMIT" > /proc/`pidof mysqld`/limits, 出现too many connections错误的时候可临时使用 gdb -p $(cat path/mysql.pid) -ex "set max_connections=5000" -batch增加max_connections的变量值,但是在并发特别大的时候可能会引起Server的Crash。

<pre>
max_user_connections = xxx
</pre>
指定每个用户能够同时连接的最大值，默认为0，不受限制，和max_connections一起使用，可以尽量避免出现too many connections错误.
<pre>
max_connect_errors = 100000         
</pre> 
客户端连接请求被中断的次数超过max_connect_errors值的话，MySQL Server则阻塞该客户端的后续连接，直到管理员可通过flush hosts命令。

<pre>
thread_cache_size  = 64             
</pre> 
MySQL Server可以缓存以再次使用的thread数量，该参数对性能提升很有帮助，减少创建新线程的开销，可以参考官方手册查看详细信息。

<pre>
table_open_cache   = 1000           
</pre> 
从5.1.3开始引入该参数，表示所有线程能够打开表的数量，不要被cache锁迷惑。该参数和max_connections相关，有利于提高并发性能。

<pre>
skip-name-resolve                   
</pre> 
参数指定Server端 在检查 client连接的时候不要解析host name,只使用ip 地址。

<pre>
max_allowed_packet = 4M             
</pre> 
指定允许通过最大大小的包数据，如果有大的BLOB,string等，确保值合适，中文网平台4M即可，如果超过4M，协议会对包进行分组传送。该参数在client, master, slave的设置需保持一致,如果slave的值大于master,可能会出现无限报错，重试，relay log损坏等问题。

<pre>
user      = mysql                   
</pre> 
以mysql用户启动mysqld服务，不要使用root用户启动
<pre>
read_only = 1                       
</pre> 
开启read only,确保slave不会被应用帐户更新数据，master也配置保持配置的一致性，启动master后，可手工禁止read only。
<pre>
skip-external-locking               
</pre> 
跳过外部锁，external locking是系统级别锁的一种应用，针对于MyISAM表，目的在于减少锁争用，但是容易引起死锁，所以禁掉external lock为好。
<pre>
character-set-server = utf8         
</pre> 
指定Server端编码为utf8。
<pre>
collation-server = utf8_general_ci  
</pre> 
编码的排序规则制定为utf8_general_ci，这也是默认排序规则。
<pre>
tmpdir = /dev/shm                   
</pre> 
临时目录指定到 /dev/shm 临时文件系统中，glibc 2.2 版本及以上会因为 POSIX 共享内存的需要期望将临时文件系统(tmpfs) 挂载到 /dev/shm(默认值), 默认为系统内存的一半大小, 可以重新 remount /dev/shm 的大小: mount -o remount,size=32G,noatime /dev/shm ; 也可以编辑 /etc/fstab 将大小写到文件里使得重启系统也能生效: tmpfs   /tmp         tmpfs   nodev,nosuid,size=2G          0  0
             
<pre>
slow_query_log = 1                  
</pre> 
启用慢查询记录
<pre>
long_query_time = 1                 
</pre> 
记录超过1s的查询语句，没有精确到毫秒级别。
<pre>
slow_query_log_file = slow-query.log
</pre> 
未指定路径则保存在datadir目录中。


<pre>
log-bin     = mysql-bin.log         
</pre> 
指定mysql-bin.为序列化二进制日志的基准名，如mysql-bin.000001，不要使用hostname等差异化的名字，命名规则都保持统一。
<pre>
sync_binlog = 1                     
</pre> 
该参数控制写入操作刷新到二进制日志的频率: 默认为0，表示由操作系统决定什么时候刷新到binlog,这种情况是最快的，也是最危险的；线上环境统一指定为1，是最安全的，系统崩溃只丢失一条记录，但也是最慢的(除非磁盘具有电池备份缓存特性(BBU))。
<pre>
relay-log   = relay-bin.log         
</pre> 
指定relay-bin为relay log的基准名，不要使用hostname等信息命名。
<pre>
log-slave-updates                  
</pre> 
线上所有实例统一开启relay log选项，以达到master, slave可以互相切换的目地。
<pre>
replicate-same-server-id = 0        
</pre> 
布尔类型，在Slave Server中生效，值为0 可以避免server-id一样而引起的循环复制。

<pre>
innodb_buffer_pool_size  = xxxxM    
</pre> 
该选项控制缓存innodb数据信息、索引数据信息的大小，buffer pool是弥补 磁盘和cpu之间处理速度 的一种有效方式，理论上buffer pool越大，数据库性能越小，不过由于内存等因素的限制，难以做到全部缓存。专用数据库系统主机中可以设置物理内存的50%~70%；一主机多实例的环境中，预留20%的物理内存供系统使用，剩余空间按照实例数量酌情分配。
<pre>
innodb_log_file_size     = 128M     
</pre> 
innodb log file文件存储redo log等信息，设置过大，崩溃后的恢复时间越长，设置过小，会引起磁盘的频繁操作
<pre>
innodb_log_buffer_size   = 4M       
</pre> 
该参数控制InnoDB的事务日志所使用的缓冲区，为了提高性能，也是先将信息写入 Innofb Log Buffer 中，当满足 innodb_flush_log_trx_commit 参数所设置的相应条件（或者日志缓冲区写满）之后，会将日志写到文件（或者同步到磁盘）中，默认1M，线上统一为4M(不超过max_allowed_packet大小)。
<pre>
innodb_flush_log_at_trx_commit = 2  
</pre> 
该参数控制日志缓冲刷新到磁盘上的方式， 0：每秒刷新一次，事务提交不做操作；1：每提交一个事务，刷新一次；2：每提交一个事务，写到文件，但不对文件做磁盘刷新操作。0方式效率最高，但最不安全，1方式最安全，但性能最差，2方式相对安全(只要主机不崩溃就可以恢复，因为数据还在内存中)，效率也高(接近0方式)。线上数据库统一设置为2方式。
<pre>
innodb_flush_method    =  O_DIRECT 
</pre> 
该方式控制怎么打开表文件和刷新数据到磁盘上，O_DIRECT方式：以 direct I/O 打开数据文件，调用fsync()系统函数刷新数据文件和日志文件；O_DSYNC方式：以O_SYNC 方式打开表并刷新日志文件，调用fsync()系统函数刷新数据文件；UNIX/LINUX系统中fsync()系统函数效率很高(比较而言，但是没有确切的结论见flushing files to disk with the Unix fsync() call (which InnoDB uses by default) and other similar methods is surprisingly slow.)，从这点来看O_DSYNC方式在更新方面更快些，但手册上没有明确证明，视情况而定。线上实例统一设置为O_DIRECT方式；另外O_DIRECT开启，并启用InnoDB可以禁用系统的缓存,减缓内存浪费; 使用该方式配置的时候, 如果应用存在 `create temporary table .. `等语句, 则需要注意以下报错信息`[Warning] InnoDB: Failed to set O_DIRECT on file /dev/shm/#sql3ed_642_0.ibd: CREATE: Invalid argument, continuing anyway. O_DIRECT is known to result in 'Invalid argument' on Linux on tmpfs, see MySQL Bug#26662.`  percona 版本不会引起进程重新启动, 而是以其他方式打开文件, 比如使用percona 5.6.29版本测试, 对其 `strace -p ‘pidof mysqld‘ -f` 之后的结果如下:
<pre>
392 [pid 21726] open("/dev/shm/#sql3ed_646_0.ibd", O_RDWR|O_CREAT|O_EXCL, 0660) = 104
393 [pid 21726] fcntl(104, F_SETFL, O_RDONLY|O_DIRECT) = -1 EINVAL (Invalid argument)
394 [pid 21726] fcntl(104, F_SETLK, {type=F_WRLCK, whence=SEEK_SET, start=0, len=0}) = 0
......
......
402 [pid 21726] open("/dev/shm/#sql3ed_646_0.ibd", O_RDWR) = 104
403 [pid 21726] fcntl(104, F_SETFL, O_RDONLY|O_DIRECT) = -1 EINVAL (Invalid argument)
404 [pid 21726] fcntl(104, F_SETLK, {type=F_WRLCK, whence=SEEK_SET, start=0, len=0}) = 0
</pre> 
换言之不影响程序的数据查询. 如果想忽略掉错误, 可以将改参数设置为 O_DRYNC(修改需重启进程) 或将 tmpdir 参数设置为非 tmpfs 的目录.
<pre>
innodb_file_per_table  = 1          
</pre> 
启用该选项，控制每个表拥有一个数据文件(ibd)，默认为0，所有的表数据都会写到共享表空间(ibdata1)，对大库而言很难管理，线上统一强制开启。
<pre>
default-storage-engine = innodb     
</pre> 
设置默认存储引擎为innodb，线上统一为该配置，innodb表在性能和数据安全方面有很好的保证，崩溃恢复机制不可缺少，线上环境新建的实例或表建议启用该选项，另外default的设定还有一个好处：5.1版本中以MyISAM引擎为默认，如果没有安装（或启用）innodb插件，则不能创建innodb表（显示声明引擎会采用默认的MyISAM替换），这点有悖于应用的初衷；指定了default选项且Server没有启用InnoDB特性，在服务启动的时候就会报错退出，而不是可以启动。


以下参数为percona分支版本：
<pre>
userstat_running                = 1 
</pre> 
5.5.21以上版本改名 userstat ，用来控制是否开启统计信息的搜集(information_schema.USER_STATISTICS表)，即统计用户在实例中的使用情况，如连过过少次，读了多少数据，执行命令包括那些等，建议开启，但会增加一点统计上的开销。
<pre>
innodb_overwrite_relay_log_info = 1 
</pre> 
5.5版本以上改名innodb_recovery_update_relay_log。复制是一个异步的过程，slave上进行复制的position信息(relay log中)总是落后于master，如果在更新该position之前发生崩溃，已经提交的事务在崩溃恢复过程中会再执行一次。该选项记录了复制了相关位置信息，加了一层保护作用，确保主从尽量一致，建议开启，线上全部开启。
<pre>
innodb_lazy_drop_table          = 1 
</pre> 
5.5.30~5.5.32，该特性废弃，其余版本存在。当开启innodb_file_per_table选项后，在一个有很大buffer pool的Server中删除一个表需要花费很长的时间，即便这个表是空的，因为innodb需要在buffer pool中扫描和表相关的page信息，然后清除；启用该选项innodb扫描到相关page信息后只是做个deleted标记(mark)，然后由server的后台线程慢慢清理，启用该选项，删除表时，能降低对Server的影响。
<pre>
innodb_pass_corrupt_table       = 0 
</pre> 
5.5.10以上版本改名innodb_corrupt_table_action [assert, warn, salvage]。系统一旦检测到存在坏的表空间，除了drop table操作，其它访问操作被禁止.当开启了innodb_file_per_table(设置为1)选项后，innodb尝试做一些修复操作，同时检测损坏的page，修复不了则锁住user table，禁止访问(即影响所有与损坏表相关的database操作，包括user信息)，线上该参数统一配置为0，不做锁表操作，只返回错误。5.5版本设为warn,只返回错误，其它两个值和5.1版本设置为1情况类似。
<pre>
log_slow_verbosity          = full  
</pre> 
该选项用来指定哪些信息需要记录到slow log文件中，包括查询语句时间精度，innodb status信息等，线上统一用full表示全部。

<pre>
innodb_auto_lru_dump = 16
</pre>
5.5.10更名为innodb_buffer_pool_restore_at_startup，值范围: 0-UINT_MAX32,单位秒; 该参数实现自动dump/restore buffer pool功能， 能够极大减少InnoDB重启后buffer pool预热的时间，在主机不宕掉的情况下,buffer pool还存在于系统的memory中,该参数遍历并保存buffer pool中page的标识信息, MySQL重新启动的时候会读取dump的文件信息加载到相应的page位置。详细测试见: <a href=http://www.mysqlperformanceblog.com/2010/01/20/xtradb-feature-save-restore-buffer-pool/>http://www.mysqlperformanceblog.com/2010/01/20/xtradb-feature-save-restore-buffer-pool/</a>

<b>4.可选项</b>

<pre>
!include ~/.my.cnf                    
</pre> 
从MySQL 5.0.4版本开始，可以使用!include命令指定其它的选项文件(my.node.cnf或my.cnf俗称为MySQL选项文件)，即my.node.cnf文件包含 ~./.my.cnf文件中的选项(家目录下的./my/cnf文件)，线上在该文件中指定用户密码，特别注意.my.cnf文件的读写权限。
<pre>
[mysql]                                #mysql客户端命令区域选项
 prompt = 'mysql \u@[\h:\p \d] > '     #提示符格式， 'mysql 用户@[用户host:port database]'
 default-character-set = utf8          #客户端连接默认设置字符集为utf8，目前线上业务都保持为utf8编码
[mysqladmin]                           #mysqladmin区域
default-character-set = utf8         
 [mysqlcheck]                          #mysqlcheck区域选项，设置check表相关参数，该命令默认进行锁表操作
default-character-set = utf8          
[mysqldump]                            #mysqldump区域选项，设置默认字符集为utf8
 default-character-set = utf8
[mysqlimport]                          #数据导入时的字符集设置
 default-character-set = utf8
[mysqlshow]                            #显示数据库，表，列信息时的字符集
 default-character-set = utf8
[client]                               #设置所有所有客户端命令、工具连接数据库实例时的默认端口，socket参数；
 port = XXXX
 socket = /web/mysql/node3306/data/sXXXX
</pre>


<pre>
sort_buffer_size = 2M                 
</pre> 
排序操作分配的缓存大小，Sort_merge_passes量比较大的话可以酌情增加值大小，默认256K。

<pre>
read_buffer_size = 2M                 
</pre> 
线程做一些顺序扫描的时候，该参数很有用，但适用于MyISAM引擎的表，不做强制性要求，默认128K。

<pre>
join_buffer_size = 2M                 
</pre> 
连接查询时，分配的buffer size,增加该值大小，有利于join效率，中文网平台很少使用join查询，默认128K。

<pre>
read_rnd_buffer_size = 4M             
</pre> 
对MyISAM表很有用，在做排序或索引排序相关的操作时，增加该参数值可以减少硬盘的查询操作，默认256K。


<pre>
expire_logs_days        = 7           
</pre> 
二进制日志过期天数，不做强制性要求，但是线上出现过因为binlog日志太多而导致硬盘使用紧张的案例，一般建议开启，可设置为7天（根据业务需求设定）。

<pre>
binlog_format
</pre>
二进制日志格式，为动态变量，默认statement格式。该选项有三种方式statement,row,mixed。statement按照更新的sql语句记录到二进制日志中；mixed混合型，除了不安全函数(uuid,sysdate等)，更新结果集不确定采用row格式以避免出现主从不一次的情况外，其余语句采用statement格式；row详细记录每行记录的变化。row格式在主从结构中很安全，但是binlog更新很频繁，会吃掉很多磁盘资源，中文网平台不适合该种方式；mixed格式更有效，可以保证主从的一致性，更新量也不大，应用环境如果对数据一致性要求比较高，可以采用该种方式；statement简单，方便但是最不安全，数据的一致性需要开发人员避免不安全函数或不一致结果集的sql出现，需要投入相当多的人力。该选项不做强制，线上统一以statement格式存储Binlog日志。

<pre>
key_buffer_size         = N(M|G)      
</pre> 
该参数主要针对于MyISAM引擎，不做强制要求，但是每更新一次变量会清空当前变量的大小，重新缓存，MyISAM表较多的实例中谨慎修改，系统默认为8M。MySQL中对于MyISAM引擎表，只缓存索引文件，不缓存数据文件，如果实例中MyISAM表很多，可尽量保证key_buffer_size大小接近实例中所有MYI文件大小之和，但不超过4G(此限制存在于32位主机中)。

<pre>
wait_timeout            = xxx         
</pre> 
Server 关闭非交互连接之前等待的秒数，默认28800s, 该值设置过小可能使resin应用类的长连接失效，设置过大可能会使process资源紧张，中文网平台保持默认即可，其它平台可设置小点3600或7200。

<pre>
sysdate-is-now          = 1           
</pre> 
启用sydata-is-now功能，启用后，sysdate相关的函数当作now()函数处理，以确保主从数据的一致性(sysdate在Replication中为不安全函数，每次返回函数开始执行时的时间)。如果应用端该函数很多，可以启用该功能，不在乎主从上的一致性，可以忽略。


<pre>
skip-slave-start                      
</pre> 
该参数指定在slave server重启的时候，跳过slave 连接的自动完成，即需要手工启动slave信息。该参数可选，不启用该选项，slave重启的时候，如果出现问题可可能会导致主从关系错乱。


<pre>
innodb_status_file      = 1           
</pre> 
不做强制性要求，启用该选项会使SHOW ENGINE INNODB STATUS的输出信息以一定周期频率写道DATADIR/innodb_status.<pid>文件中。

<pre>
innodb_data_file_path
</pre>
不做强制性要求，默认为ibdata1:10M:autoextend。开启innodb_file_per_table选项后，ibdata共享表空间主要存储数据字典，回滚段等信息，线上增长不会太大。如果线上实例存在频繁的事务回滚等操作可以适当调大该参数信息。

<pre>
innodb_additional_mem_pool_size = xxx 
</pre> 
不做强制性要求，默认1M，该选项主要用来存储数据字典，内部结构等信息，实例中表越多，需要的空间越大。buffer pool不够用时，该选项会从系统内存中获取空间，并发出error信息。

<pre>
innodb_log_files_in_group             
</pre> 
多少个log file为一组，默认为2，采用轮询方式。

<pre>
 relay_log_purge
</pre>
改选项控制slave  sql_thread线程执行完重放完sql语句后是否清除relay log文件，默认开启该选项。不做强制性要求，关闭该选项在系统崩溃的时候，数据恢复则多了一层保障。

<pre>
thread_handling
</pre>
percona 5.5版本引入的参数，同max_connetions,默认为one-thread-per-connection，线程越多对服务的性能影响越大，thread_handling = pool-of-threads为动态调整线程池，对OLTP应用在性能上有很好的保障作用。该参数不做强制性要求。线上统一采用默认值
http://www.percona.com/doc/percona-server/5.5/performance/threadpool.html

<pre>
slave_skip_errors = 1062
</pre>
1062(Duplicate key error), slave_skip_errors忽略指定选项的错误代码， 线上统一制定为1062, 避免Duplicate error中断sql_thread线程，该参数不支持动态更改，每次做更改需要重启Server.

<pre>
query_cache_strip_comments
</pre>
使Server 在检查query cache hit的时候忽略 commnet信息;举例说明如下:
/*first query*/ select name from users where users.name like ’Bob%’;
/*retry search*/ select name from users where users.name like ’Bob%’;
默认情况下,这两条语句被认为不同，server端会分别执行并缓存它们,如果该选项开启，Server会忽略commnet信息,这两条语句就是相同的语句,执行和缓存值进行一次,减少开销；
<pre>
flush_time
</pre> 
如果设置为非0值， 每隔指定的时间(seconds)对所有表进行一次closed操作以便释放一些资源并且同步未刷新到磁盘的数据到磁盘; percona默认为0， Oracle <= 5.6.5默认为1800s, >=5.6.6默认为0s;