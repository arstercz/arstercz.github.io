#!/usr/bin/env perl
# name service test.
# 2018-12-18
use strict;
use warnings FATAL => 'all';
use Net::DNS;
use Data::Dumper;

unless (defined $ARGV[0]) {
  print "usage: $0 domainname\n";
  exit 1;
}

while (1) {
  my $res = Net::DNS::Resolver->new()
            or die "dns error:$!";

  my $a_query = $res->search($ARGV[0]);
  print "Website IP Address...\n";

  if ($a_query) {
    foreach my $rr ($a_query->answer) {
      next unless $rr->type eq "A";
      print $rr->address, "\n";
    }
  } else {
    warn "Unable to obtain A record: ", $res->errorstring, "\n";
  }
  sleep 2;
}
