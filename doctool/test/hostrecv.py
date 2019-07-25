#!/usr/bin/env python
# -*- coding: utf-8 -*-

import dns.resolver
import time
import sys

if len(sys.argv) == 1:
  print "usage: %s domainname" % sys.argv[0]
  sys.exit(1)

while 1:
  domain = sys.argv[1]
  A = dns.resolver.query(domain,'A')
  for i in A.response.answer:
     for j in i.items:
        print(j.address)
  time.sleep(2)
