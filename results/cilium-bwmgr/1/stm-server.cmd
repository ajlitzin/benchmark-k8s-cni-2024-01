kubectl exec -it cni-benchmark-a2 --  statexec -f stm-server.prom -d 10 -l id=cilium-bwmgr -l run=1 -i stm -mst 1704067200000 -s --  iperf3 -s
