kubectl exec -it cni-benchmark-a3 --  statexec -f sum-client.prom -d 10 -l id=calico -l run=3 -i sum -mst 1704067200000 -dbc 11  -c 10.42.78.196 --  iperf3 -c cni-benchmark-a2 -O 1 -u -b 0 -P 8 -Z -t 60 --json