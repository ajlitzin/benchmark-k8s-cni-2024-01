kubectl exec -it cni-benchmark-a3 --  statexec -f dtm-client.prom -d 10 -l id=calico-wg -l run=1 -i dtm -mst 1704067200000 -dbc 11  -c 10.42.78.198 --  iperf3 -c 10.42.78.198 -O 1 -P 8 -Z -t 60 --dont-fragment --json
