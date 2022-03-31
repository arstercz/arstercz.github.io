---
layout: post
title: "不同级别的延迟估算"
tags: [metric]
comments: true
---


## Order-of-Magnitude Estimates

> read more from <<Understanding Software Dynamics>>, Chapter 1, section 6.

The phrase order of magnitude refers to an approximate measure of the size of a number. A decimal order of magnitude gives an estimate that is the nearest power of 10 (1, 10, 100, ...), while a binary order of magnitude gives an estimate that is the nearest power of 2 (1, 2, 4, 8, and so on). we use the notation O(n) for “on the order of n,” with the units always specified. It matters a lot whether you are talking about O(10) nanoseconds or O(10) milliseconds or O(10) bytes. we will also use nsec, usec, and msec to abbreviate nanoseconds, microseconds, and milliseconds, respectively.

### Numbers Everyone Should Know [Dean 2009]

| **Action** | **Time** | **O(n)** |
| :- | -: | -: |
| L1 cache reference | 0.5 nsec | O(1) nsec |
| Branch mispredict | 5 nsec | O(10) nsec |
| L2 cache reference | 7 nsec | O(10) nsec |
| Mutex lock/unlock | 25 nsec | O(10) nsec |
| Main memory reference | 100 nsec | O(100) nsec |
| Compress 1K bytes with Zippy | 3,000 nsec | O(1) usec |
| Send 2K bytes over 1 Gbps network | 20,000 nsec | O(10) usec |
| Read 1 MB sequentially from memory | 250,000 nsec | O(100) usec |
| Round trip within same datacenter | 500,000 nsec | O(1) msec |
| Disk seek | 10,000,000 nsec | O(10) msec |
| Read 1 MB sequentially from disk | 20,000,000 nsec | O(10) msec |
| Send packet CA->Netherlands->CA | 150,000,000 nsec | O(100) msec |

Knowing the estimates in Table 1.1 will also guide you in identifying the likely source of a performance bug.
