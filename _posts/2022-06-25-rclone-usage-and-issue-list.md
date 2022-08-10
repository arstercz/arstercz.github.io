---
layout: post
title: "rclone 工具使用及问题汇总"
tags: [rclone, s3, bucket]
comments: true
---

[rclone](https://rclone.org/) 作为文件和对象存储的管理工具, 经过近些年的发展已经完好的支持各种存储协议, 比如 HDFS, FTP, SFTP, GCS 和 S3(兼容 aws, 金山云, 腾讯云, 阿里云等)等, 逐渐有统一管理云存储之势, 从 [rclone-github](https://github.com/rclone/rclone) 来看, 各大云厂商也逐渐将各自的存储协议合并到了 rclone 中. 这在对象存储统一管理, 尤其是多云管理的场景中带来了很大的便利, 也便于我们实现诸如统一运维管理的目标.

同时, rclone 也支持多种模式来进行文件的传输管理, 不同模式各有优缺点, 常见的模式主要包含下面两种:

```
1. 命令行方式传输文件, 比如 copy, sync, move 等子命令;
2. mount 分区挂载方式传输文件, 类似挂载 nfs 等方式到本地;
```

两种模式都可以实现本地到云存储, 云存储到本地, 甚至云存储到云存储等方式的文件传输, 极大的方便了使用者. 下面则主要介绍在使用 rclone 的过程中可能碰到的问题, 以及一些使用方面的优化措施. 后期碰到的问题也会在该列表中持续更新.

## 问题列表

* [内核不支持插件问题](#内核不支持插件问题)  
* [安装问题](#安装问题)  
* [rsync 传输错误](#rsync-传输错误)  
* [md5 校验错误](md5-校验错误)  
* [一致性问题](#一致性问题)  
* [目录显示问题](#目录显示问题)  
* [windows 使用问题](#windows-使用问题)  
* [缓存目录过大问题](缓存目录过大问题)

## 最佳实践

* [systemd 管理挂载服务](#systemd-管理挂载服务)  
* [consul 特性支持](#consul-特性支持)  
* [各云存储配置示例](#各云存储配置示例)  
* [使用建议](#使用建议)  

## 内核不支持插件问题

一些系统可能采用了自行编译的内核, 且没有开启内核模块功能. 这种情况下不能有效加载 fuse 模块. 建议可以单独找一台标准的 `Centos 7/Ubuntu18.04` 机器安装 rclone 并正常挂载. 这些异常机器可以通过 rsync 传输到正常挂载的机器上.

## 安装问题

安装 rclone 的时候, 需要安装 fuse 依赖. 在使用 rclone 的 mount 特性的时候会依赖内核 FUSE, 且至少为 7.17 版本, 如果在低内核版本使用 mount 特性, 会出现版本过低的提示:
```
Fatal error: failed to mount FUSE fs: kernel FUSE version is too old: 7.14 < 7.17
``` 

比如标准发行版 RedHat/Centos 6 中目前的 FUSE 为 7.14 版本, 在 kernel-header 的头文件中可以看到版本信息:
```
grep FUSE_KERNEL_MINOR_VERSION /usr/include/linux/fuse.h
#define FUSE_KERNEL_MINOR_VERSION 14
```

遗憾的是标准版 Centos 6.10 最高版本也仅为 7.14. 鉴于这种方式建议采用 `内核不支持插件问题` 的方式进行处理, 或者通过 rclone 命令行的方式传输单个文件, 如下所示:
```
 rclone --config /etc/rclone/rclone.conf sync /tmp/file gcp_oss:test1_gcs/
 rclone --config /etc/rclone/rclone.conf ls gcp_oss:test1_gcs/
```

sync 等同 rsync 功能, 不过可能由于桶权限的问题, sync 可能不支持目录的传输. 对比起来还是建议使用 `内核不支持插件问题` 的方式.

## rsync 传输错误

> rsync 的传输错误假定 rclone 通过 mount 方式挂载到了本地.

#### rsync 传输到挂载目录出现错误

如果对象存储仅提供 put, get 的权限, `rsync` 默认会在目的目录中创建隐藏的校验文件, 再进行 `rename` 交换(等同需要 delete 权限), 所以直接 `rsync -vaZ source dest` 会出现以下问题:
```
rsync: failed to set time on ....: Input/output error  -- 不要用 -a 选项, 对象存储不支持修改 time 等参数.
rsync: rename ... -> ....: Input/output error
```

需要通过以下方式，更换校验需要的临时目录, 避免上述的错误:
```
mkdir /export/rsync_temp
rsync -vZ -T /export/rsync_temp source dest
```

#### rsync 服务模块配置说明

如果通过 rsync 服务的方式允许其它主机传输文件到本机的挂载目录, rsync 服务的配置需要遵循以下几点:
```
1. rsync 模块以 root 用户启动, 禁止 chroot;
2. rsync 模块 path 指定为挂载点的上层目录, 比如云盘挂载到本地 /mnt/rclone_mount/test1_gcs, 就将 path 指定为 /mnt/rclone_mount;
3. 在 path 目录创建 rsync 的临时目录， 比如 /mnt/rclone_mount/rsync_tmp;
4. 其它主机通过以下方式传输, 假定 rsync 模块名为 rsync_test1, 用户为 rsync_user, 云存储桶名为 test1_gcs, rsync 不要指定 -a 选项:
   rsync -T /rsync_tmp --password-file=/tmp/rsync.pass  -v --progress  /tmp/rsync.log  rsync_user@10.1.1.2::rsync_test1/test1_gcs/
```

上述的 -T 即指定了临时目录为 `/mnt/rclone_mount/rsync_tmp`, 目的端需要加上桶名的目录后缀. 另外这种方式在 `systemctl stop rclone@test1_gcs.service` 的时候也不会因为 rsync 占用句柄而关闭失败;

## md5 校验错误

参见 [issue-4031](https://github.com/rclone/rclone/issues/4031), 从目前的测试来看, mount 的时候, 只有设置了 `--vfs-cache-mode full` 选项, 才不会出现 issue 中的 hash 不匹配问题. 

> 备注: 如果自己制作了 rpm, 建议将该选项已合并到了 systemd 服务配置中.

## 一致性问题

建议通过以下方式保证数据的一致性:

#### 1. rsync 传输.

rclone 的挂载目录如果为目的端, 建议在本地使用 rsync 方式传输. 如果对象存储不赋予 delete 等权限, 在传输失败的时候, 需要做好重命名传输的处理, 比如 abc.tar.gz 传输失败, 再次传输目标文件可以变更为 abc_r1.tar.gz.
 
#### 2. rclone sync 传输.

等同 centos 6 中的问题, 如果没有设置 rsync 服务, 可以通过 rclone sync 命令行的方式传输文件, sync 选项以类似 rsync 的方式校验两边的数据保证一致性;
 
#### 3. md5 校验.

这种方式相对繁琐, 可以对每个文件做好 md5 校验, 并将校验值 `md5.list` 传到挂载目录中. 完整性校验的时候会对比对象存储中的文件和 `md5.list` 中文件的 md5 校验值. 不匹配则认为不一致. 通过脚本方式在实际传输文件的时候也可以对两边的文件进行 md5 校验, 不匹配则重新传输.

## 目录显示问题

对于 rclone 的 mount 方式而言, 期望的操作方式是本地挂载, 本地传输文件到远端, 这种方式新创建的目录或文件立即就可以生效显示. 如果是在远端传输文件, 本地挂载只为读取数据, 则会有一段时间的缓存, 新建的目录并不会立马显示, 该缓存时间受 `rclone mount` 选项 `--dir-cache-time` 控制, 超过指定时间再次访问的时候就会重新刷新目录列表, 对目录显示有短时间显示的需求, 可以将该值适当调小. 

## windows 使用问题

在 windows 系统中使用 rclone 的时候, 需要安装 windows 版的 fuse, 可以安装 [winfsp](https://github.com/winfsp/winfsp/) 以支持 fuse 功能. 在使用的时候也建议通过 windows 服务来启动 rclone, 如下所示, 可以通过windows 的 `sc` 命令以 cmd 方式来创建:

```
# 创建服务
sc create rclone binpath= "D:\rclone-windows\rclone.exe mount --config D:\rclone-windows\rclone.conf --allow-non-empty --allow-other --vfs-cache-mode full --dir-cache-time 3m --poll-interval 1m --vfs-read-chunk-size-limit 128M --vfs-write-back 0s --log-level INFO --log-file D:\rclone-windows\log\rclone-sftp.log -o FileSecurity=\"O:WDG:WDD:NO_ACCESS_CONTROL\" --bwlimit 100M rclone_mount:/mnt/dl_tmp D:\rclone_mount" displayname= "Rclone Service" depend= Tcpip start= auto

# 删除服务
sc delete rclone
```
在 windows 中, 实际的文件权限由 winfsp 的 fuse 特性来实现控制, rclone 在通过 winfsp 挂载远端的时候需要执行文件的安全策略使得 windows 可以对挂载点进行完全的访问控制. 更多见:
 
[rclone-windows-filesystem-permissions](https://rclone.org/commands/rclone_mount/#windows-filesystem-permissions) 
[windwos-SDDL](https://docs.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-string-format)  
[winfsp-github-391](https://github.com/winfsp/winfsp/issues/391)  
[rclone-github-4717](https://github.com/rclone/rclone/issues/4717)  
[rclone-modtime-change](https://github.com/rclone/rclone/issues/3029)  

> 备注: 如果提示`服务已标记删除 1072` 相关的错误, 需要关掉服务窗口, 再执行 `sc delete` 操作.

## 缓存目录过大问题

使用 mount 模式的时候, 在开启 `--vfs-cache-mode full` 选项的情况下, rclone 为了提升性能, 通常会将文件写到本地, 再由后台功能异步的传输到远端. 如果短时间内传输大量文件, 就可能会使得默认的 vfs 缓存目录 `/tmp/rclone` 过大, 甚至吃满磁盘空间. 可以设置下面两个选项此类问题:
 
```
// rclone flags
--cache-dir string                     Directory rclone will use for caching (default "/root/.cache/rclone")
...
--fs-cache-expire-duration duration    Cache remotes for this long (0 to disable caching) (default 5m0s)
```
 
由于 cache-dir 本身不够通用, 在 rpm 包中我们并未进行定制修改. `fs-cache-expire-duration` 则可以按需调整, 默认的 5m 也适合大多数场景. 线上传输较大的主机可以参考以下设置:
```
rclone --cache-dir /export/rclone/tmp  --fs-cache-expire-duration 2m mount ....
```
 
**备注**: 选项说明中的默认目录由实际的 `fs/config/config.go - makeCacheDir 函数决定`, linux 系统下默认为 `/tmp/rclone` 并非 `/root/.cache/rclone`, 如下所示:

```go
//fs/config/config.go 

678 // Code borrowed from go stdlib until it is made public
679 func makeCacheDir() (dir string) {
680         // Compute default location.
681         switch runtime.GOOS {
682         case "windows":
683                 dir = os.Getenv("LocalAppData")
684
685         case "darwin":
686                 dir = os.Getenv("HOME")
687                 if dir != "" {
688                         dir += "/Library/Caches"
689                 }
690
691         case "plan9":
692                 dir = os.Getenv("home")
693                 if dir != "" {
694                         // Plan 9 has no established per-user cache directory,
695                         // but $home/lib/xyz is the usual equivalent of $HOME/.xyz on Unix.
696                         dir += "/lib/cache"
697                 }
698
699         default: // Unix
700                 // https://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html
701                 dir = os.Getenv("XDG_CACHE_HOME")
702                 if dir == "" {
703                         dir = os.Getenv("HOME")
704                         if dir != "" {
705                                 dir += "/.cache"
706                         }
707                 }
708         }
709
710         // if no dir found then use TempDir - we will have a cachedir!
711         if dir == "" {
712                 dir = os.TempDir()
713         }
714         return filepath.Join(dir, "rclone")
715 }
```

## systemd 管理挂载服务

使用 mount 特性的时候, 建议通过 systemd 服务进行管理, 如下所示, 可以指定参数挂载多个云存储实例, 且自动重新启动:
```
[Unit]
Description=rclone: Remote FUSE filesystem for cloud storage config %i
Documentation=man:rclone(1)
After=network-online.target
Wants=network-online.target
AssertPathIsDirectory=/mnt/rclone_mount/

[Service]
Type=notify
ExecStartPre=/bin/mkdir -p /mnt/rclone_mount/%i
ExecStart=/usr/bin/rclone mount --config /etc/rclone/rclone.conf --allow-non-empty --allow-other --vfs-cache-mode full --vfs-cache-max-size 500M --dir-cache-time 5m --poll-interval 1m --vfs-read-chunk-size-limit 128M --vfs-read-chunk-size-limit off --log-level INFO --log-file /var/log/rclone/rclone-%i.log --bwlimit 20M --umask 022 rclone_oss_consul:%i /mnt/rclone_mount/%i
ExecStop=/bin/fusermount -uz /mnt/rclone_mount/%i
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

通过以下方式启动服务:
```
systemctl enable rclone@bucketname
systemctl start rclone@bucketname
systemctl status rclone@bucketname   -->  查看服务状态
```

启动后, 每个桶默认会挂载到 `/mnt/rclone_mount/bucketname` 目录. 对应的日志 `/var/log/rclone/rclone-bucketname.log`. 默认情况下 rclone 服务异常中断, 会定期重试启动, 重试信息会输出到对应的日志文件中.

## consul 特性支持

[consul](https://github.com/arstercz/rclone/commit/dbfc1be7451351be92a096738c574078eab1fd24) 特性为笔者自定义特性, 初衷是为了隐藏各云存储的桶的 key 信息, 方便所有桶账号的统一管理, 避免人员混杂的时候 key 信息可能乱用的情况. 

> 备注: 该功能不算通用, 仅满足于特定的需求. 这里的 consul 作为 kv 来使用, 实际上也可以替换为其它 DB 来实现，另外 rclone 本身支持对配置加密, 但是在 rclone 命令读取配置信息的时候实际上还能看到 key 的信息, 如果有很多桶的时候也不方便管理.

基于此特性, 可以做到以下几点:
```
1. 一个账号或 key 可以管理所有桶;
2. 一个账号或 key 映射为多个 consul key, 每个 key 可以对应单个项目;
3. 不可见账号或 key, 所有数据的传输均以 consul key 的形式通信;
4. 权限管理简单, 使用者和对象存储管理者均简单方便;
```

#### 如何实现 consul 特性

`consu` 特性的要点在于避免使用者直接通过 key 传输数据, 而对于 rclone 来讲, 以命令行或 mount 方式使用 rclone 的时候, 需要找到一种方式来隐藏 key 的显示. 笔者采用的方式整体流程如下所示(以 gcs 为例说明):
```
       client
   +-------------+          https         +---------------+
   |   rclone    |      --------------->  | consul server |
   +-------------+                        +---------------+
 
1. rclone 从 consul server 获取以 service-consul-key 为键的信息 value;
2. rclone 解析 value 中的 service_account 字段信息, 并进行解密;
3. 将解密内容直接赋值给选项 gcs-client-secret;
4. rclone 校验 value 的 buckets 选项, 通过后开始挂载或者传输数据;
```
整个 consul 特性的过程相当于替换了读取 `--gcs-service-account-file` 的过程, 后续的机制则不做改动. 基于此流程, rclone 的 gcs 相关部分可以做相关修改, 比如对 gcs 支持中增加以下选项:
```
--gcs-service-consul-key
--gcs-service-consul-server
--gcs-service-consul-token
--gcs-service-consul-tls
```
对应到 `rclone.conf` 的配置就如下所示:
```
service_consul_server = 10.1.1.2:8500
service_consul_token = ck843784-1fe8-95c9-12df-06ac368528gf
service_consul_key = 40f51886b53b4966c9d009e2ba05efb7
service_consul_tls = true
```

上述的几个选项即可实现替换原生的 gcs 选项(二选一):
```
--gcs-service-account-file
--gcs-client-secret
```

s3(包括 aws s3, 金山云 ks3, 腾讯云 cos, 阿里云 oss) 等方式与此类似. 不过需要实现替换以下选项:
```
--s3-access-key-id
--s3-secret-access-key
```

#### consul kv 示例

consul 中的格式需要根据 gcs 或者 s3 适当调整. 上述小节中的 `service_consul_key` 可以通过 [utils](https://github.com/arstercz/rclone/tree/version-1.58/utils) 的 `uniqsign` 生成, 作为 `aes256` 的 key. consul 中的 value 则为 json 串, 如下所示:

```
# gcs 示例
key:   oss/gcs/2d1127ff54d14cecb291cdba4460d890
value: {
  "team": "myteam",
  "service_account": "<aesutils 执行后加密的内容>",
  "buckets": ["test1", "test2", "test3"]
}

# s3 示例
key:   oss/s3/2c1127ff64d14cebb291cdba4460c809
value: {
  "team": "myteam",
  "provider": "Kingsoft oss",
  "access_key_id": "<aesutils 对 access key 加密后的内容>",
  "secret_access_key": "aesutils 对 access secret 加密后的内容",
  "buckets": ["test1", "test2", "test3"]
}
```

> buckets 对应 service 账号下的桶, 可以设置多个桶. 如果桶名包含 “allow_all”, 则 rclone 允许挂载该 key 下所有桶.

## 各云存储配置示例

> 笔者仅以 consul 特性为例, 不使用 consul 的配置与此等同, 只要去掉 consul 相关选项即可.

云厂商对应对象存储名称:
```
gcp      - gcs
aws      - s3
aliyun   - oss
tencent  - cos
kingsoft - ks3
```

#### gcs 配置

```
[rclone_oss_consul]
type = google cloud storage
object_acl = bucketOwnerFullControl
bucket_acl = private
auth_url = https://accounts.google.com/o/oauth2/auth
token_url = https://oauth2.googleapis.com/token
service_consul_server = <consul server>
service_consul_token = <consul token>
service_consul_key = <consul key>
service_consul_tls = true
```

#### s3 配置

```
[rclone_oss_consul]
type = s3
provider = AWS
env_auth = false
service_consul_server = <consul server>
service_consul_token = <sonsul token>
service_consul_key = <consul key>
service_consul_tls = true
region = <region>
endpoint = <endpoint>
acl = private
bucket_acl = private
storage_class = STANDARD
```

#### oss 配置

```
[rclone_oss_consul]
type = s3
provider = Alibaba
env_auth = false
service_consul_server = <consul server>
service_consul_token = <sonsul token>
service_consul_key = <consul key>
service_consul_tls = true
endpoint = <endpoint>
acl = private
bucket_acl = private
storage_class = STANDARD
```

#### cos 配置

```
[rclone_oss_consul]
type = s3
provider = TencentCOS
env_auth = false
service_consul_server = <consul server>
service_consul_token = <sonsul token>
service_consul_key = <consul key>
service_consul_tls = true
endpoint = <endpoint>
acl = private
bucket_acl = private
storage_class = STANDARD
```

#### ks3 配置

ks3 [Endpoint与Region的对应关系](https://docs.ksyun.com/documents/6761), region 需要为大写.
```
[rclone_oss_consul]
type = s3
provider = Other
env_auth = false
service_consul_server = <consul server>
service_consul_token = <sonsul token>
service_consul_key = <consul key>
service_consul_tls = true
endpoint = <endpoint>
region = <region>                      ---  金山云必须要指定 region
acl = private
bucket_acl = private
storage_class = STANDARD
```

## 使用建议

正常使用的时候, 建议注意以下几点:
```
1. 尽量保证一个项目只有一两台机器运行 rclone, 不要过多的挂载, 其它机器可以通过 rsync 传输文件;
2. rclone 做好限制, 比如 20M, 不要设置太大避免占用很多带宽;
3. rclone 的 mount 方式, 仅在启动的时候和 consul 通信, 挂载后不会再有交互;
4. rclone 的命令行方式, 执行一次就会和 consul 通信一次, 如果网络质量不好, 建议采用 mount 方式和 consul 通信;
```

