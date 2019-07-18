---
id: 867
title: 自定义 influxdb 数据结构, 生成 grafana 趋势图
date: 2017-09-04T15:17:38+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=867
permalink: '/%e8%87%aa%e5%ae%9a%e4%b9%89-influxdb-%e6%95%b0%e6%8d%ae%e7%bb%93%e6%9e%84-%e7%94%9f%e6%88%90-grafana-%e8%b6%8b%e5%8a%bf%e5%9b%be/'
categories:
  - code
  - database
  - monit
tags:
  - grafana
  - influxdb
---
## 介绍

目前使用 [grafana](https://grafana.com) 来生成漂亮的监控图像变得越来越流行, 笔者认为 grafana 之所以流行的原因主要在于它的灵活性和扩展性. 管理员可以很方便的选择各种数据源作为监控数据的后端存储, 这些源包括 [Graphite](https://graphiteapp.org/), [influxDB](https://www.influxdata.com/), [Prometheus](https://prometheus.io/), [OpenTSDB](http://opentsdb.net/) 等, 我们可以根据需要将搜集到的数据存到指定的源中, grafana 再读取源数据, 最后按照管理员指定的各种规则以不同的图像显示出指定的数据.

grafana 支持的图形方式则更为丰富[graph](http://docs.grafana.org/features/panels/graph/), 各种图形属性及展示方式应有尽有. 当然更为方便的是我们可以根据数据源的信息做出更为精细的图像进而展示. 以管理员经常用到的监控工具为例, nagios 适合报警触发, cacti 适合查看图像趋势, zabbix 则稍微好点, 包含了报警和图形趋势. 但是 cacti/zabbix 本身是以指定间隔时间采集数据, 时间太短的话会引起采集脚本负担太重, 时间太长则可能磨平问题发生时的图像尖峰. 而 grafana 支持较多的数据源, 如果我们将采集到的数据存储到基于时间序列的数据库中, 就有可能实现生成基于秒, 分钟的监控图像. 比如下图所示, 在访问突然增大的情况下, cacti 已经将尖峰削去了很多, grafana 则显示的更为精细, 这在故障发生进行追踪分析的时候就显得特别有用, 如下所示, 更精确的监控更能接近问题的真相:

cacti 监控:
![cacti1]({{ site.baseurl }}/images/articles/201709/cacti1.bmp)

grafana 监控
![grafana1]({{ site.baseurl }}/images/articles/201709/grafana1.bmp)

下面的我们介绍的实例基于数据源 influxdb, influxdb 官方的 [telegraf](https://docs.influxdata.com/telegraf/v1.3/) 已经实现了大多数我们经常用到的软件的监控, 并可以将监控数据送到 influxdb 供 grafana 生成图像. 如果需要自定义数据进行采集, 可参考以下链接:

[guides](https://docs.influxdata.com/influxdb/v1.2/guides/)
[data_exploration](https://docs.influxdata.com/influxdb/v1.2/query_language/data_exploration/)
[data-types](https://docs.influxdata.com/influxdb/v1.2//write_protocols/line_protocol_reference/#data-types)

下面则主要介绍如何实现基于 influxdb + grafana 的自定义图像.


## 自定义生成 influxDB 数据

往 influxDB 发送数据大致有两种方式, 各自编程语言的 client 驱动和 influxdb 提供的 http 接口, 使用 http 接口可以参考以下链接 [writing data](https://docs.influxdata.com/influxdb/v1.2/guides/writing_data/).

比如插入数据:
```
curl -i -XPOST 'http://localhost:8086/write?db=mydb' --data-binary 'cpu_load_short,host=server01,region=us-west value1=0.64143,value2=0.282717'
```
通过 write 接口往数据库 mydb 的 cpu_load_short 表里插入数据 value, 在 influxdb 结构中：
```
  key, tag, tag
cpu_load_short,host=server01,region=us-west 
```
这里的 cpu_load_short 即为 key, 相当于关系数据库里的表名; tag 标签 host 和 region 则相当于表的索引; value1 和 value2 则相当于表里的两个列; 0.64143, 0.282717 则相当于对应列的值.

备注: 如果 influxdb 里没有指定的 key, 新插入数据将默认创建对应的 key. 默认情况下插入到 influxdb 中的时间为插入时间, 如果需要自定义时间, 可以参考[writing-data-using-the-http-api](https://docs.influxdata.com/influxdb/v1.3/guides/writing_data/#writing-data-using-the-http-api)使用如下的格式:
```
curl -i -XPOST 'http://localhost:8086/write?db=mydb' --data-binary 'cpu_load_short,host=server01,region=us-west value1=0.64143,value2=0.282717 1548979200000000000'
```

#### 示例
以获取一个 user 表的最大自增 id 为例, 从数据库获取到表的最大自增id 后即可通过 curl 的 POST 方法向 influxdb 插入数据:
```perl
sub insert_data {
    my ($server, $ua, $data) = @_;
    $data .= "i";
    my $keyurl = "http://$server/write?db=dbmonitor&u=dbmonitor&p=xxxxxxxx";

    # post key value
    my $request  =   
        HTTP::Request::Common::POST(
                   $keyurl,
                   'User-Agent' => 'influx_curl0.1',
                   'Content' => "table_user,metric=maxid,region=test value=$data" 
                 );  
    my $res = $ua->request($request);
    #print Dumper($res);
    unless ($res->is_success) {
        return 0;
    }   
    return 1;
}
```
这里的代码以 Perl 语言编写, 大家可以选择适合自己的语言按照以上方式实现插入数据.

influxdb 的 dbmonitor 数据库则新增 key table_user, metric 和 region 为相关的索引, value 为具体的值:
```
> select * from table_user where metric = 'maxid' order by time desc limit 2;
name: table_user
time                           metric region value
----                           ------ ------ -----
2017-05-12T08:38:01.33652891Z  maxid  test   87026236
2017-05-12T08:37:02.016900366Z maxid  test   87026234
```

时间字段中, 需要我们转为 CST 时区, 默认加8个小时, grafana 模板显示的时候已经默认做了转换, 不需要我们额外设置.

## 在 grafana 中添加图像

在上述的介绍中, 我们已经将搜集到的信息存到了 influxdb 中, 要生成对应的图像只需要选择对应的数据源即可, 如下所示, 选择 influxDB 作为数据源:
![create1]({{ site.baseurl }}/images/articles/201709/create1.jpg)

选择好对应的表名, 和 `test_influxdb` 作为数据源, 另外因为我们每次都是获取的最大的自增 id, 所以图像中如果要计算增量情况则需要选择好对应的 difference 函数进行计算, 而且搜集的数据是每分钟一次, 所以我们需要指定按照1分钟`group by (1m)` 进行计算. 

实际上的 sql 语句就等同以下:
```
SELECT difference(last("value")) FROM "test_user" WHERE "metric" = 'maxid' AND $timeFilter GROUP BY time(1m) fill(null)
```
last(value) 即为value 列每次取的最新的值, drifference 为两次值的差, group by 按照 1 分钟(脚本多长时间收集一次数据, 这里就选多长时间)聚合运算. 最后生成的图如下:
![graph2]({{ site.baseurl }}/images/articles/201709/graph2.bmp)

## 总结

总体上来讲, grafana 为我们提供了一个更自由, 更直接美观的图表显示工具, 能够解决很多管理员长期以来可以写脚本而难以通过图表进行分析的痛点. 只要我们了解自定义规则, 就可以做出漂亮, 直观且适合我们自己的图表. 另外 grafana 支持创建模板变量避免管理员重复的手动操作, 但是目前为止对于模板的告警没实现, 详见 [issue6557](https://github.com/grafana/grafana/issues/6557); percona 则提供了另一种方式进行告警, 但是比较复杂[pmm-alerting-with-grafana](https://www.percona.com/blog/2017/02/02/pmm-alerting-with-grafana-working-with-templated-dashboards/). 我们可以期待 grafana 的后续版本解决模板变量的告警问题.
