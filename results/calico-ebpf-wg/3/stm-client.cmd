kubectl exec -it cni-benchmark-a3 --  statexec -f stm-client.prom -d 10 -l id=calico-ebpf-wg -l run=3 -i stm -mst 1704067200000 -dbc 11  -c 10.42.78.195 --  iperf3 -c cni-benchmark-a2 -O 1 -P 8 -Z -t 60 --dont-fragment --json
