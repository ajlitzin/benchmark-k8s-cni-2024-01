kubectl exec -it cni-benchmark-a2 --  statexec -f dum-server.prom -d 10 -l id=cilium-nokproxy -l run=1 -i dum -mst 1704067200000 -s --  iperf3 -s