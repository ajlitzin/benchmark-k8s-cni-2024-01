kubectl exec -it cni-benchmark-a3 --  statexec -f sus-client.prom -d 10 -l id=cilium-bwmgr -l run=3 -i sus -mst 1704067200000 -dbc 11  -c 10.0.0.235 --  iperf3 -c cni-benchmark-a2 -O 1 -u -b 0 -Z -t 60 --json
