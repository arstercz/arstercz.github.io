---
id: 62
title: Enable multiport for mysql cacti template of the percona monitor plugin
date: 2014-02-11T01:05:55+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=62
permalink: /enable-multiport-for-mysql-cacti-template-of-the-percona-monitor-plugin/
views:
  - "33"
dsq_thread_id:
  - "3465399948"
dsq_needs_sync:
  - "1"
categories:
  - code
  - database
  - monit
tags:
  - cacti
  - muti port
---
Modified cacti.tables records to archive the goal that percona plugin for mysql can monitor more than one instance with diffrenet port.All changes are based on 'Data Input Methods' and 'Data template'. The flow we also used to create custom template is :
<pre>
 'sctipts'  --> 'Data Input Methods' --> 'Data Template' --> 'Graph Template'
</pre>

Vaiables connect to mysql are writed on 'ss_get_mysql_stats.php' file, which can be find in '<cacti_path>/scripts/', the port will be fixed if 'Data Input Methods' enable allow nulls, for instance:
 <font color=red>https://your_monit_site/cacti/data_input.php?action=field_edit&id=266&data_input_id=40</font>
<!--more-->
disable it, then note the section 'Custom data' which in 'Data Template' should be checked (means you can specify any usable port number), eg:
 <font color=red>https://your_monit_site/cacti/data_templates.php?action=template_edit&id=52</font>

1. Change ss_get_mysql_stats.php file for enable connect mysql use different port. An error occured when connect mysql use host:port method. mysql_connect can use.eg: http://www.php.net/manual/en/mysqli.construct.php
error:
<pre>
   [root@me scripts]# php ss_test.php --host t1 --items nn --port 3306
   bool(false)
   MySQL: Unknown MySQL server host 't1:3306' (3)
</pre>
Script file:
<pre>
--- ss_get_mysql_stats.php_20131016     2013-10-16 11:01:01.490394353 +0800
+++ ss_get_mysql_stats.php      2013-10-16 11:13:51.346582456 +0800
@@ -254,8 +254,7 @@
    $heartbeat = isset($options['heartbeat']) ? $options['heartbeat'] : $heartbeat;
    # If there is a port, or if it's a non-standard port, we add ":$port" to the
    # hostname.
-   $host_str  = $options['host']
-              . (isset($options['port']) || $port != 3306 ? ":$port" : '');
+   $host_str  = $options['host'];
    debug(array('connecting to', $host_str, $user, $pass));
    if ( !extension_loaded('mysqli') ) {
       debug("The MySQLi extension is not loaded");
@@ -264,10 +263,10 @@
    if ( $mysql_ssl || (isset($options['mysql_ssl']) && $options['mysql_ssl']) ) {
       $conn = mysqli_init();
       mysqli_ssl_set($conn, $mysql_ssl_key, $mysql_ssl_cert, NULL, NULL, NULL);
-      mysqli_real_connect($conn, $host_str, $user, $pass);
+      mysqli_real_connect($conn, $host_str, $user, $pass, '', $port);
    }
    else {
-      $conn = mysqli_connect($host_str, $user, $pass);
+      $conn = mysqli_connect($host_str, $user, $pass, '', $port);
    }
    if ( !$conn ) {
       debug("MySQL connection failed: " . mysqli_error());
</pre>

2. Change the port allow nulls property that in 'Data Input Methods'.
<pre>
   select * from data_input_fields where data_input_id in (select id from data_input where name regexp 'MySQL') and name = 'Port';

   update data_input_fields set allow_nulls = '' where name = 'Port' and data_input_id in (select id from data_input where name regexp 'MySQL');
</pre>

3. Change value that in 'Data template -- Custom data', involed every data input fields.

<pre>
   mysql> select id into outfile '/tmp/idinfo.txt' from data_input where input_string regexp 'ss_get_mysql_stats.php';
   Query OK, 43 rows affected (0.01 sec)
   # for x in `cat /tmp/idinfo.txt`; do mysql -S /tmp/mysql.sock -D cacti -Bse "update data_input_data set t_value = 'on' where data_input_field_id = (select id from data_input_fields where data_input_id = $x and name = 'Port') and data_template_data_id  = (select id from data_template_data where data_input_id = $x and local_data_template_data_id = 0)";echo ok;done
</pre>