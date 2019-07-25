#!/bin/bash

set -e
[[ "$TRACE" ]] && set -x

while true; do
  echo "begin time: $(date +%FT%T.%N)"
  top -d 0.2 -bn 3 | perl -nae '
    BEGIN{
      use POSIX qw(strftime);
      $n = 0;
    }
   
    $a++ if /PID\s+USER/;
    s/^\s*//;
    if ($a == 3){
      $sum += $F[8];
      if(/\s*\d\s+/ && $n < 20) {
        $n++;
        my @a = split(/\s+/, $_);
        $h{$a[0]}{pid} = $a[0];
        $h{$a[0]}{cpu} = $a[8];
        $h{$a[0]}{state} = $a[7];
        $h{$a[0]}{command} = $a[-1]
      }
    }
   
    END{
      system("echo \"  end time: \$(date +%FT%T.%N)\"");
      print "Total cpu usage: $sum\n";
      foreach my $k (
        sort {$h{$b}{cpu} <=> $h{$a}{cpu}} keys %h) {
   
        printf("%6d -> cpu: %-.2f, state: %s, cmd: %s\n",
                $k, $h{$k}{cpu}, $h{$k}{state}, $h{$k}{command});
      }
      print "-" x 40 . "\n";
    }
  '
  numactl -H
  sleep 1
done
