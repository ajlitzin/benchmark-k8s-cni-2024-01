kubectl exec -it cni-benchmark-a3 --  statexec -f dum-client.prom -d 10 -l id=cilium-bwmgr -l run=3 -i dum -mst 1704067200000 -dbc 11  -c 10.0.0.235 --  iperf3 -c 10.0.0.235 -O 1 -u -b 0 -P 8 -Z -t 60 --json
