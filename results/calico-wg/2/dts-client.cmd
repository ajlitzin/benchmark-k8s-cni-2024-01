kubectl exec -it cni-benchmark-a3 --  statexec -f dts-client.prom -d 10 -l id=calico-wg -l run=2 -i dts -mst 1704067200000 -dbc 11  -c 10.42.78.196 --  iperf3 -c 10.42.78.196 -O 1 -Z -t 60 --dont-fragment --json
