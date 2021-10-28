---
layout: post
title: "macos 技巧汇总"
tags: [macos]
---

最近用 macbook pro 办公之后, 碰到了很多使用上的问题. 本文主要用来整理并记录这些问题.

## 问题列表

* [常用的效率工具](常用的效率工具)
* [chrome 浏览器不能处理 https 页面](#chome-浏览器不能处理-https-页面)  
* [锁屏后 ssh 连接中断](#锁屏后-ssh-连接中断)  
* [wireshark 不能使用](#wireshark-不能使用)  

## 常用的效率工具

[dash](https://kapeli.com/dash): 文档阅读工具, 技术工作者的首选文档工具.  
[滴答清单](https://www.dida365.com/): 好用的任务管理工具.  
[iTerm2](https://iterm2.com/): 好用的终端命令行工具.  

## chrome 浏览器不能处理 https 页面

使用 chrome 打开一些自签证书的 https 站点时, 经常出现 `NET::ERR_CERT_INVALID` 的错误, 点击高级后也没有任何下一步的按钮提示.  不像 macos 下的 firefox 或者 windows 下的 chrome, 可以接受风险并继续打开站点. 这种情况可以参考 [no-proceed-anyway-option-on-neterr-cert-invalid](https://stackoverflow.com/questions/58802767/no-proceed-anyway-option-on-neterr-cert-invalid-in-chrome-on-macos):

```
There's a secret passphrase built into the error page. Just make sure the page is selected (click anywhere on the screen), and just type thisisunsafe.
```

鼠标点击到失效的 https 站点页面, 直接键盘输入 `thisisunsafe` 即可正常访问.

## 锁屏后 ssh 连接中断

通过 Terminal 或者 iTerm2 远程 ssh 连接其他机器的时候, 经常会因为锁屏而中断连接. 看表象应该是锁屏后导致系统睡眠, 而导致 ssh 连接中断. 这种问题可以通过以下几种方式避免.

#### 安装效率软件

 比如 `Amphetamime`，通过软件来使 macos 保持唤醒状态, 锁屏后也保证在指定时间内不会睡眠. 这种方式需要依赖用户的习惯, 很难认为保证没有遗漏的情况.

#### 禁止系统睡眠

可以参考以下文章设置:

[prevent-your-mac-from-sleep](https://mackeeper.com/blog/prevent-your-mac-from-sleep/)  
[how-to-turn-off-sleep-mode-on-mac](https://www.hellotech.com/guide/for/how-to-turn-off-sleep-mode-on-mac)  

`M1` 系统可以通过以下访问路径开启 `当显示器关闭时, 防止电脑自动进入睡眠`:
```
系统偏好设置 -> 电池 -> 电源适配器
```

## wireshark 不能使用

截至目前(2021-10-18), wireshark 仅支持 macos 的 intel 架构, M1 架构还不支持. 如果要想分析抓包的文件, 只能借助支持 wireshark 的平台, 或者支持全平台的 [termshark](https://github.com/gcla/termshark) 工具以命令行的方式分析抓包文件.  不过 termshark 依赖的 tshark(wireshark 的组件) 不支持 macos. 所以如果手上有多余的 Linux 机器, 就直接用 termshark 来分析吧. 参考 [termshark-user-guide](https://github.com/gcla/termshark/blob/master/docs/UserGuide.md) 了解更多分析方法.

另外, 网上提到的 [charles](https://www.charlesproxy.com/) 或 [proxyman](https://proxyman.io/ ) 工具本质上都是 web 代理调试的工具, 仅支持 `http/https` 的分析, 其他协议还不支持. 或许再等待一段时间后, 可能会出现 wireshark 的 M1 版本.
