kubectl exec -it cni-benchmark-a3 --  statexec -f dus-client.prom -d 10 -l id=calico-vpp -l run=3 -i dus -mst 1704067200000 -dbc 11  -c 10.42.78.196 --  iperf3 -c 10.42.78.196 -O 1 -u -b 0 -Z -t 60 --json