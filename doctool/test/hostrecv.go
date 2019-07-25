package main

import (
	"net"
	"fmt"
	"os"
	"time"
)

func main() {
	if len(os.Args) == 1 {
		fmt.Fprintf(os.Stderr, "usage: %s domainname\n", os.Args[0])
		os.Exit(1)
	}
	var resolvname string = os.Args[1]
	for {
		ips, err := net.LookupIP(resolvname)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Could not get IPs: %v\n", err)
			os.Exit(1)
		}
		for _, ip := range ips {
			fmt.Printf("%s. IN A %s\n", os.Args[1], ip.String())
		}
		fmt.Printf("\n")
		time.Sleep(2 * time.Second)
	}
}
