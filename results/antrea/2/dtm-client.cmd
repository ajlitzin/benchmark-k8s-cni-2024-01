kubectl exec -it cni-benchmark-a3 --  statexec -f dtm-client.prom -d 10 -l id=antrea -l run=2 -i dtm -mst 1704067200000 -dbc 11  -c 10.42.1.3 --  iperf3 -c 10.42.1.3 -O 1 -P 8 -Z -t 60 --dont-fragment --json
