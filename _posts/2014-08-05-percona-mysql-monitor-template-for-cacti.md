---
id: 288
title: Percona MySQL Monitor template for Cacti
date: 2014-08-05T12:26:11+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=288
permalink: /percona-mysql-monitor-template-for-cacti/
dsq_thread_id:
  - "3459875493"
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - MySQL
---
To collect Percona Mysql Variables, read more from  <a href="http://www.percona.com/doc/percona-monitoring-plugins/cacti/mysql-templates.html">http://www.percona.com/doc/percona-monitoring-plugins/cacti/mysql-templates.html</a> and Percona mysql installed dirs support-file/my-innodb-heavy-4G.cnf
<pre>1. InnoDB Adaptive hash Index</pre>
    This variable is enabled by default.The feature known as the adaptive hash index (AHI) lets InnoDB perform more like an in-memory database on systems with appropriate combinations of workload and ample memory for the buffer pool, without sacrificing any transactional features or reliability. 

   Links:<a href="http://dev.mysql.com/doc/refman/5.5/en/innodb-adaptive-hash.html">http://dev.mysql.com/doc/refman/5.5/en/innodb-adaptive-hash.html</a>

2. InnoDB maintains a storage area called the buffer pool for caching data and indexes in memory.It manages the pool as a list, using a variation of the least recently used (LRU) algorithm.

  <pre>InnoDB Buffer Pool Activity</pre>
    The InnoDB Buffer Pool Activity shows activity inside the buffer pool: pages created, read, and written. You can consider it roughly equivalent to the Handler graphs. If you see a sudden change in the graph, you should try to trace it to some change in your application.
<!--more-->


  <pre>InnoDB Buffer Pool Size</pre>
    Unlike MyISAM, uses a buffer pool to cache both indexes and  row data. The bigger you set this the less disk I/O is needed to  access data in tables. On a dedicated database server you may set this  parameter up to 80% of the machine physical memory size. Do not set it too large, though, because competition of the physical memory may cause paging in the operating system.  Note that on 32bit systems you might be limited to 2-3.5G of user level memory per process, so do not set it too high.

<pre>3. InnoDB Checkpoint Age
eg: show engine innodb status\G
---
LOG
---
Log sequence number 120483417682
Log flushed up to   120483389516
Last checkpoint at  120283867762
Max checkpoint age    434154333
Checkpoint age target 420587011
Modified age          199424973
Checkpoint age        199549920
0 pending log writes, 0 pending chkp writes
371933445 log i/o's done, 369.29 log i/o's/second
</pre>
   The InnoDB Checkpoint Age shows the InnoDB checkpoint age, which is the same thing as the number of uncheckpointed bytes, and thus the amount of log that will need to be scanned to perform recovery if there’s a crash. If the uncheckpointed bytes begin to approach the combined size of the InnoDB log files, your system might need larger log files. In addition, a lot of un-checkpointed data might indicate that you’ll have a long and painful recovery if there’s a crash. If you are writing a tremendous amount of data to the log files, and thus need large log files for performance, you might consider the enhancements in Percona Server

<pre>4. InnoDB Current Lock Waits</pre>
The InnoDB Current Lock Waits graph shows the total number of seconds that InnoDB transactions have been wait-ing for locks. This is related to the InnoDB Locked Transactions graph above, except that it’s the sum of the lock wait time. You might have only one transaction in LOCK WAIT status, but it might be waiting a very long time if innodb_lock_wait_timeout is set to a large value. So if you see a large value on this graph, you should investigate for LOCK WAIT transactions, just as described above.

<pre>5.eg: show engine stat\G (show engine innodb status\G)
--------
FILE I/O
--------
I/O thread 0 state: waiting for completed aio requests (insert buffer thread)
I/O thread 1 state: waiting for completed aio requests (log thread)
I/O thread 2 state: waiting for completed aio requests (read thread)
I/O thread 3 state: waiting for completed aio requests (read thread)
I/O thread 4 state: waiting for completed aio requests (read thread)
I/O thread 5 state: waiting for completed aio requests (read thread)
I/O thread 6 state: waiting for completed aio requests (write thread)
I/O thread 7 state: waiting for completed aio requests (write thread)
I/O thread 8 state: waiting for completed aio requests (write thread)
I/O thread 9 state: waiting for completed aio requests (write thread)
Pending normal aio reads: 0 [0, 0, 0, 0] , aio writes: 0 [0, 0, 0, 0] ,
 ibuf aio reads: 0, log i/o's: 0, sync i/o's: 0
Pending flushes (fsync) log: 0; buffer pool: 0
10183 OS file reads, 399868020 OS file writes, 5126216 OS fsyncs
0.00 reads/s, 0 avg bytes/read, 404.19 writes/s, 3.36 fsyncs/s

-------------------------------------
INSERT BUFFER AND ADAPTIVE HASH INDEX
-------------------------------------
Ibuf: size 1, free list len 0, seg size 2, 0 merges
merged operations:
 insert 0, delete mark 0, delete 0
discarded operations:
 insert 0, delete mark 0, delete 0
Hash table size 53124499, node heap has 6119 buffer(s)
593.89 hash searches/s, 78.14 non-hash searches/s
</pre>
  <pre>InnoDB I/O</pre>
    The InnoDB I/O Activity shows InnoDB’s I/O activity: file reads and writes, log writes, and fsync() calls. This might help diagnose the source of I/O activity on the system. Some of this can be influenced with InnoDB settings, especially innodb_flush_log_at_trx_commit.

  <pre>InnoDB Pending</pre>
    The InnoDB I/O Pending shows InnoDB’s pending synchronous and asynchronous I/O operations in various parts of the engine. Pending I/O is not ideal; ideally you’d like InnoDB’s background thread(s) to keep up with writes, and you’d like the buffer pool large enough that reads are not an issue. If you see a lot of pending I/O, you might need more RAM, a bigger buffer pool (or use O_DIRECT to avoid double-buffering), or a faster disk subsystem.

  <pre>InnoDB Insert Buffer</pre>
    The InnoDB Insert Buffer shows information about InnoDB’s insert buffer: inserts, merge operations, and merged records. This is not generally actionable, because the insert buffer is not user-configurable in standard MySQL. However, you can use it to diagnose certain kinds of performance problems, such as furious disk activity after you stop the server from processing queries, or during particular types of queries that force the insert buffer to be merged into the indexes. (The insert buffer is sort of a delayed way of updating non-unique secondary indexes.) If the insert buffer is causing problems, then Percona Server might help, because it has some configuration parameters for the buffer.

  <pre>InnoDB Insert Buffer Usage</pre>
    The InnoDB Insert Buffer Usage shows the total cells in the insert buffer, and the used and free cells. This is diagnostic only, as in the previous graph. You can use it to see the buffer usage, and thus correlate with server activity that might be hard to explain otherwise.

  <pre>InnoDB Internal Hash Memory Usage</pre>
    The InnoDB Internal Hash Memory Usage shows how much memory InnoDB uses for various internal hash structures: the adaptive hash index, page hash, dictionary cache, filesystem, locks, recovery system, and thread hash. This is available only in Percona Server, and these structures are generally not configurable. However, you might use it to diagnose some kinds of performance problems, such as much greater than expected memory usage. In standard InnoDB, the internal data dictionary tends to consume large amounts of memory when you have many tables, for example. Percona Server lets you control that with some features that are similar to MySQL’s table cache.

<pre>6. InnoDB Lock Structures</pre>
    The InnoDB Lock Structures graph shows how many lock structures InnoDB has internally. This should correlate roughly to the number of row locks transactions are currently holding, and might be useful to help diagnose increased lock contention. There is no hard rule about what’s a good or bad number of locks, but in case many transactions are waiting for locks, obviously fewer is better.

<pre>7. InnoDB Log
eg: show variables like '%innodb%'
| innodb_log_block_size                     | 512                    |
| innodb_log_buffer_size                    | 4194304                |
| innodb_log_file_size                      | 268435456              |

   $results['unflushed_log']
      = big_sub($results['log_bytes_written'], $results['log_bytes_flushed']);
</pre>
The InnoDB Log Activity shows InnoDB log activity: the log buffer size, bytes written, flushed, and unflushed. If transactions need to write to the log buffer and it’s either not big enough or is currently being flushed, they’ll stall.


<pre>8. InnoDB Memory Allocation
   
+---------------------------------------+-------------+
| Variable_name                         | Value       |
+---------------------------------------+-------------+
| innodb_additional_mem_pool_size       | 8388608     |
| innodb_buffer_pool_size               | 26843545600 |
+---------------------------------------+-------------+
</pre>
The InnoDB Memory Allocation graph shows InnoDB’s total memory allocation, and how much of that is in the additional pool (as opposed to the buffer pool). If a lot of memory is in the additional memory pool, you might suspect problems with the internal data dictionary cache; see above for more on this. Unfortunately, in standard InnoDB it’s a bit hard to know where the memory really goes.

<pre>9.
| Innodb_current_row_locks      | 0            |
| Innodb_row_lock_time          | 14           |
| Innodb_row_lock_time_avg      | 7            |
| Innodb_row_lock_time_max      | 8            |
| Innodb_row_lock_waits         | 2            |
| Innodb_rows_deleted           | 180388150    |
| Innodb_rows_inserted          | 230003654    |
| Innodb_rows_read              | 222202010382 |
| Innodb_rows_updated           | 750096       |
</pre>
  <pre>InnoDB Row Lock Time</pre>
    The InnoDB Row Lock Time shows the amount of time, in milliseconds, that InnoDB has waited to grant row locks. This comes from the Innodb_row_lock_time status variable.

  <pre>InnoDB Row Lock Waits</pre>
    The InnoDB Row Lock Waits shows the number of times that InnoDB has waited to grant row locks. This comes from the Innodb_row_lock_waits status variable.

  <pre>InnoDB Row Operations</pre>
    The InnoDB Row Operations shows row operations InnoDB has performed: reads, deletes, inserts, and updates. These should be roughly equivalent to Handler statistics, with the exception that they can show internal operations not reflected in the Handler statistics. These might include foreign key operations, for example.


<pre>10. eg: show engine status\G 
----------
SEMAPHORES
----------
OS WAIT ARRAY INFO: reservation count 2262226, signal count 197284039
Mutex spin waits 318818326, rounds 300667430, OS waits 883302
RW-shared spins 72317671, rounds 236072157, OS waits 882758
RW-excl spins 4777376, rounds 240638780, OS waits 371245
Spin rounds per wait: 0.94 mutex, 3.26 RW-shared, 50.37 RW-excl
</pre>
  <pre>InnoDB Semaphores</pre>

    The InnoDB Semaphores shows information on InnoDB semaphore activity: the number of spin rounds, spin waits, and OS waits. You might see these graphs spike during times of high concurrency or contention. These graphs basically indicate different types of activity involved in obtaining row locks or mutexes, which are causes of poor scaling in some cases.

<pre>11. InnoDB Tables In Use</pre>
    The InnoDB Tables In Use shows how many tables InnoDB has in use and how many are locked. If there are spikes in these graphs, you’ll probably also see spikes in LOCK WAIT and other signs of contention amongst queries InnoDB Transactions Active/Locked.

<pre>12. InnoDB Transactions

------------
TRANSACTIONS
------------
Trx id counter B45C670
Purge done for trx's n:o < B45286D undo n:o < 0
History list length 2254
LIST OF TRANSACTIONS FOR EACH SESSION:
---TRANSACTION 0, not started
MySQL thread id 141039, OS thread handle 0x7fc11a5c8700, query id 188725216 localhost root
show engine innodb status
---TRANSACTION B45C66F, not started
MySQL thread id 10736, OS thread handle 0x7fc7bc05b700, query id 188725215 172.30.0.119 173_log
</pre>
The InnoDB Transactions shows information about transactions within InnoDB.
    Total transactions ever created is the internal transaction counter.
    The length of the history list shows how old the oldest unpurged transaction is. If this grows large, you might have transactions that are staying open a very long time. This means InnoDB can’t purge old row versions. It will get bloated and slow as a result. Commit your transactions as quickly as you can. The example graph is slightly outdated; a newer version of the templates has moved some of the items to the Ac-tive/Locked graph instead.

This template shows InnoDB transaction counts:
    An active transaction is a transaction that’s currently open. It’s possible for transactions to be in “not started” status, which reallymeans that this connection toMySQL doesn’t actually have a transaction open. A transaction is active between BEGIN and COMMIT. It’s also active whilst a query is running, although it might commit immediately due to auto-commit, if applicable. This graph really just shows how much transactional activity is happening on the database.

    A locked transaction is in LOCK WAIT status. This usually means it’s waiting for a row lock, but in some cases could be a table lock or an auto-increment lock. If you start to see lock waits, you need to check SHOW INNODB STATUS and search for the string “LOCK WAIT” to examine what’s waiting. Lock waits can come from several sources, including too much contention on busy tables, queries accessing data through scans on different indexes, or bad query patterns such as SELECT .. FOR UPDATE.

    The current transactions are all transactions, no matter what status (ACTIVE, LOCK WAIT, not started, etc).

    The number of read views open shows how many transactions have a consistent snapshot of the database's contents, which is achieved by MVCC.

<pre>13. MyISAM Indexes</pre>
    The MyISAM Indexes shows information about how many logical and physical reads and writes took place to MyISAM indexes. Probably the most important one is the physical reads. The ratio between logical and physical reads is not very useful to monitor. Instead, you should look at the absolute number of physical reads per second, and compare it to what your disks are capable of. (RRDTool normalizes everything to units of seconds, so this graph’s MyISAM Key Cache absolute value is the number you need.)

<pre>14. Mysql Key Cache</pre>
    The MyISAM Key Cache shows the size of the key buffer, how much of it is used, and how much is unflushed. Memory that isn’t used might not really be allocated; the key buffer isn’t allocated to its full size.

<pre>15. Mysql Binary/Relay Logs</pre>
    The MySQL Binary/Relay logs shows information about the space used by the server binary and relay logs. The variations in the sizes are when the logs are purged, probably due to expire_logs_days being set. If this suddenly grows large, look for problems in purging, which might be caused by a configuration change, or by someone manually deleting a file and causing the automatic purge to stop working.

<pre>16. Mysql Command Counter</pre>
    The MySQL Command Counters shows counters for various MySQL commands. These are derived from the Com_ counters from SHOW STATUS. If there is a change in the graph, it indicates that something changed in the application.

<pre>17. Mysql Connections</pre>
    The MySQL Connections graph shows information about the connection parameters and counters inside MySQL: connections permitted, connections used, connections aborted, clients aborted, current connections, and connections created. Probably the most interesting are the aborted clients and connections, which might indicate a malfunction-ing application that disconnects ungracefully, an idle connection timing out, network problems, bad authentication attempts, or similar.

<pre>18. Mysql Files and Tables</pre>
    The MySQL Files and Tables graph shows status of MySQL’s table cache and file handles: the size of the cache, and how many open files and tables there are. This graph is not likely to contain much information in the normal course of events.

<pre>19. Mysql Handlers
+----------------------------+-------+
| Variable_name              | Value |
+----------------------------+-------+
| Handler_commit             | 0     |
| Handler_delete             | 0     |
| Handler_discover           | 0     |
| Handler_prepare            | 0     |
| Handler_read_first         | 0     |
| Handler_read_key           | 0     |
| Handler_read_last          | 0     |
| Handler_read_next          | 0     |
| Handler_read_prev          | 0     |
| Handler_read_rnd           | 0     |
| Handler_read_rnd_next      | 419   |
| Handler_rollback           | 0     |
| Handler_savepoint          | 0     |
| Handler_savepoint_rollback | 0     |
| Handler_update             | 0     |
| Handler_write              | 397   |
+----------------------------+-------+
</pre>
    The MySQL Handlers shows the various Handler counters, which record how many operations MySQL has done through the storage engine API. Changes in indexing will probably show up clearly here: a query that used to do a table scan but now has a good index to use will cause different Handler calls to be used, for example. If you see sudden changes, it probably correlates with schema changes or a different mixture of queries. 

<pre>20. Mysql Network Traffic</pre>
    Mysql Network Traffic shows network traffic to and from the MySQL Server. 

<pre>21. Mysql Processlist</pre>
    The MySQL Processlist shows the number (count) of queries from SHOW PROCESSLIST in given statuses. Some of the statuses are lumped together into the “other” category. This is a “scoreboard” type of graph. In most cases, you should see mostly Other, or a few of the statuses like “Sending data”. Queries in Locked status are the hallmark of a lot of MyISAM table locking. Any mixture of statuses is possible, and you should investigate sudden and systemic changes.

<pre>22. 
| Qcache_free_blocks             | 0         |
| Qcache_free_memory             | 0         |
| Qcache_hits                    | 0         |
| Qcache_inserts                 | 0         |
| Qcache_lowmem_prunes           | 0         |
| Qcache_not_cached              | 0         |
| Qcache_queries_in_cache        | 0         |
| Qcache_total_blocks            | 0         |
</pre>
 <pre> Mysql Query Cache</pre>
    The MySQL Query Cache graph shows information about the query cache inside MySQL: the number of queries in the cache, inserted, queries not cached, queries pruned due to low memory, and cache hits.

  <pre>Mysql Query Cache Memory</pre>
    The MySQL Query Cache Memory shows information on the query cache’s memory usage: total size, free memory, total blocks and free blocks. Blocks are not of a uniform size, despite the name.

<pre>23.
         debug('Getting query time histogram');
         $i = 0;
         $result = run_query(
            "SELECT `count`, total * 1000000 AS total "
               . "FROM INFORMATION_SCHEMA.QUERY_RESPONSE_TIME "
               . "WHERE `time` <> 'TOO LONG'",
            $conn);
</pre>
  <pre>Mysql Query Response Time</pre>
    The MySQL Query Response Time (Microseconds) displays a histogram of the query response time distribution available in Percona Server. Because the time units are user-configurable, exact unit labels are not displayed; rather, the graph simply shows the values. There are 14 time units by default in Percona Server, so there are 13 entries on the graph (the 14th is non-numeric, so we omit it).    

  <pre>Mysql Query Time Histogram</pre>
    The MySQL Query Time Histogram (Count) displays a histogram of the query response time distribution avail-able in Percona Server. Because the time units are user-configurable, exact unit labels are not displayed; rather, the graph simply shows the values. There are 14 time units by default in Percona Server, so there are 13 entries on the graph (the 14th is non-numeric, so we omit it).

<pre>24. Mysql Select Types
| Select_full_join       | 0     |
| Select_full_range_join | 0     |
| Select_range           | 0     |
| Select_range_check     | 0     |
| Select_scan            | 27    |
+------------------------+-------+
</pre>
    The MySQL Select Types graph shows information on how many of each type of select the MySQL server has performed: full join, full range join, range, range check, and scan. Like the Handler graphs, these show different types of execution plans, so any changes should be investigated. You should strive to have zero Select_full_join queries!

<pre>25. Mysql Sorts
+-------------------+-------+
| Variable_name     | Value |
+-------------------+-------+
| Sort_merge_passes | 0     |
| Sort_range        | 0     |
| Sort_rows         | 0     |
| Sort_scan         | 0     |
+-------------------+-------+
</pre>
    The MySQL Sorts shows information about MySQL sort operations: rows sorted, merge passes, and number of sorts triggered by range and scan queries. It is easy to over-analyze this data. It is not useful as a way to determine whether the server configuration needs to be changed.

<pre>26. Mysql Table Locks
| Table_locks_immediate                    | 188676134 |
| Table_locks_waited                       | 35        |
</pre>
    The MySQL Table Locks shows information about table-level lock operations inside MySQL: locks waited, locks granted without waiting, and slow queries. Locks that have to wait are generally caused by MyISAM tables. Even InnoDB tables will cause locks to be acquired, but they will generally be released right away and no waiting will occur.

<pre>27. Mysql Temporary
+-------------------------+-------+
| Variable_name           | Value |
+-------------------------+-------+
| Created_tmp_disk_tables | 0     |
| Created_tmp_files       | 2042  |
| Created_tmp_tables      | 29    |
+-------------------------+-------+
</pre>
    The MySQL Temporary Objects shows information about temporary objects created by the MySQL server: temporary tables, temporary files, and temporary tables created on disk instead of in memory. Like sort data, this is easy to over-analyze. The most serious one is the temp tables created on disk. Dealing with these is complex, but is covered well in the book High Performance MySQL.

<pre>28.Mysql Threads
| Threads_cached                           | 51      |
| Threads_connected                        | 2       |
| Threads_created                          | 53      |
</pre>


<pre>29. Mysql Transaction Handler
        $results['innodb_transactions'] = make_bigint(
            $row[3], (isset($row[4]) ? $row[4] : null));
         $txn_seen = TRUE;

    MySQL Transaction Handler shows the transactional operations that took place at the MySQL server level.
</pre>

-- Additional Options
   <strong>Read More : Percona mysql installed dirs support-file/my-innodb-heavy-4G.cnf</strong>

<pre>Back_log</pre>
    back_log is the number of connections the operating system can keep in the listen queue, before the MySQL connection manager thread has processed them. The back_log  value indicates how many requests can be stacked during this short time before MySQL momentarily stops answering new requests. In other words, this value is the size of the listen queue for incoming TCP/IP connections. If you have a very high connection rate and experience "connection refused" errors, you might need to increase  this value. Check your OS documentation for the maximum value of this parameter. Attempting to set back_log higher than your operating system limit will have no effect.

<pre>Skip-networking</pre>
    Don't listen on a TCP/IP port at all. This can be a security enhancement, if all processes that need to connect to mysqld run on the same host.  All interaction with mysqld must be made via Unix sockets or named pipes. Note that using this option without enabling named pipes on Windows (via the "enable-named-pipe" option) will render mysqld useless!

<pre>Table_open_cache</pre>
    The number of open tables for all threads. Increasing this value increases the number of file descriptors that mysqld requires. Therefore you have to make sure to set the amount of open files allowed to at least 4096 in the variable "open-files-limit" in section [mysqld_safe].

<pre>Binlog_cache_size</pre>
    The size of the cache to hold the SQL statements for the binary log during a transaction. If you often use big, multi-statement transactions you can increase this value to get more performance. All statements from transactions are buffered in the binary log cache and are being written to the binary log at once after the COMMIT.  If the transaction is larger than this value, temporary file on disk is use instead.  This buffer is allocated per connection on first update.

<pre>Max_heap_table_size</pre>
    Maximum allowed size for a single HEAP (in memory) table. This option is a protection against the accidential creation of a very large HEAP table which could otherwise use up all memory resources.

<pre>Read_rnd_buffer_size</pre>
    When reading rows in sorted order after a sort, the rows are read through this buffer to avoid disk seeks. You can improve ORDER BY performance a lot, if set this to a high value. Allocated per thread, when needed.

<pre>Ft_min_word_len</pre>
    Minimum word length to be indexed by the full text search index. You might wish to decrease it if you need to search for shorter words. Note that you need to rebuild your FULLTEXT index, after you have modified this value.

<pre>Thread_stack</pre>
    Thread stack size to use. This amount of memory is always reserved at connection time. MySQL itself usually needs no more than 64K of memory, while if you use your own stack hungry UDF functions or your OS requires more stack for some operations, you might need to set this to a higher value.

<pre>Log_slave_updates</pre>
    If you're using replication with chained slaves (A->B->C), you need to enable this option on server B. It enables logging of updates done by the slave thread into the slave's binary log.

<pre>Log</pre>
    Enable the full query log. Every query (even ones with incorrect syntax) that the server receives will be logged. This is useful for debugging, it is usually. disabled in production use.

<pre>Log_warnings</pre>
    Print warnings to the error log file.  If you have any problem with MySQL you should enable logging of warnings and examine the error log for possible.explanations. 

<pre>Read_only</pre>
    Make the slave read-only. Only users with the SUPER privilege and the replication slave thread will be able to modify data on it. You can use this to ensure that no applications will accidently modify data on the slave instead of the master.

<pre>Bulk_insert_buffer_size</pre>
    MyISAM uses special tree-like cache to make bulk inserts (that is, INSERT ... SELECT, INSERT ... VALUES (...), (...), ..., and LOAD DATA INFILE) faster. This variable limits the size of the cache tree in bytes per thread. Setting it to 0 will disable this optimisation.  Do not set it larger than "key_buffer_size" for optimal performance. This buffer is allocated when a bulk insert is detected.

<pre>Myisam_repair_threads</pre>
    If a table has more than one index, MyISAM can use more than one thread to repair them by sorting in parallel. This makes sense if you have multiple CPUs and plenty of memory.

<pre>Myisam_recover</pre>
    Automatically check and repair not properly closed MyISAM tables.

<pre>Innodb_additional_mem_pool_size</pre>
    Additional memory pool that is used by InnoDB to store metadata information.  If InnoDB requires more memory for this purpose it will start to allocate it from the OS. As this is fast enough on most recent operating systems, you normally do not need to change this value. SHOW INNODB STATUS will display the current amount used.

<pre>Innodb_write_io_threads  and innodb_read_io_threads</pre>
    Number of IO threads to use for async IO operations. This value is hardcoded to 8 on Unix, but on Windows disk I/O may benefit from a larger number.

<pre>Innodb_force_recovery</pre>
    If you run into InnoDB tablespace corruption, setting this to a nonzero value will likely help you to dump your tables. Start from value 1 and increase it until you're able to dump the table successfully.

<pre>Innodb_thread_concurrency</pre>
    Number of threads allowed inside the InnoDB kernel. The optimal value depends highly on the application, hardware as well as the OS scheduler properties. A too high value may lead to thread thrashing.

<pre>Innodb_flush_log_at_trx_commit</pre>
    If set to 1, InnoDB will flush (fsync) the transaction logs to the disk at each commit, which offers full ACID behavior. If you are willing to compromise this safety, and you are running small transactions, you may set this to 0 or 2 to reduce disk I/O to the logs. Value 0 means that the log is only written to the log file and the log file flushed to disk approximately once per second. Value 2 means the log is written to the log file at each commit, but the log file is only flushed to disk approximately once per second.

<pre>Innodb_log_files_in_group</pre>
    Total number of files in the log group. A value of 2-3 is usually good enough.

<pre>Innodb_max_dirty_pages_pct</pre>
    Maximum allowed percentage of dirty pages in the InnoDB buffer pool. If it is reached, InnoDB will start flushing them out agressively to not run out of clean pages at all. This is a soft limit, not guaranteed to be held.

<pre>Open-files-limit</pre>
    Increase the amount of open files allowed per process. Warning: Make sure you have set the global system limit high enough! The high value is required for a large number of opened tables.