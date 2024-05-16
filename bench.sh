#!/bin/bash

CURDIR=$(dirname $0)
[ "$CURDIR" = "." ] && CURDIR=$(pwd)

cd $CURDIR

# use local user kubeconfig
# export KUBECONFIG=$CURDIR/setup/59-kubeconfig.yaml

NAMESPACE="network-test"
BENCHID=""
RUNID=""
OUTPUTDIR=""

CMDA1=""
CMDA2=""
CMDA3=""

DIRECT_A1=""
DIRECT_A2=""
DIRECT_A3=""

SVC_A1=""
SVC_A2=""
SVC_A3=""

WIPE_RESULTS=${WIPE_RESULTS:-false}

TEST_DURATION=60
DELAY_METRICS=10

# BENCHMARK_NUMBER_OF_RUNS=${BENCHMARK_NUMBER_OF_RUNS:-3}
BENCHMARK_NUMBER_OF_RUNS=${BENCHMARK_NUMBER_OF_RUNS:-1}

function statexec {
    echo "statexec -f $1 -d ${DELAY_METRICS} -l id=$BENCHID -l run=$RUNID -i $TEST -mst 1704067200000"
}

function prefix {
    echo "[${BENCHID}][${RUNID}][${TEST}] $(date "+%Y-%m-%d %H:%M:%S")"
}

function log { echo "$(prefix) $@"; }

function test_prepare {
    TEST="prepare"
    # OUTPUTDIR="./results/$BENCHID/$RUNID"
    OUTPUTDIR="/tmp/results/$BENCHID/$RUNID"

    log start
    [ -e $OUTPUTDIR ] && rm -rf $OUTPUTDIR
    mkdir -p $OUTPUTDIR

    # we don't need the maas stuff to run
    # if [ "${BENCHID:0:3}" = "st_" ]
    # then
    #     ./maas.sh init-tuned > /dev/null 2>&1
    # else
    #     ./maas.sh init > /dev/null 2>&1
    # fi

    # sleep 60

    log end
}

function test_setup {
    TEST="setup"
    
    log start RKE2
    ./maas.sh rke2-up > /dev/null 2>&1
    log end RKE2

    log start CNI

    if [ "${BENCHID:0:3}" = "st_" ]
    then
        ./maas.sh cni ${BENCHID:3} > /dev/null 2>&1
    else
        ./maas.sh cni ${BENCHID} > /dev/null 2>&1
    fi

    sleep 60
    
    log end CNI
}

function servercmd {
    # need to use /tmp to write files in our containers
    filepath="/tmp"
    filename="${TEST}-server"

    NUMABIND=""
    #[ "${BENCHID:0:3}" = "st_" ] && NUMABIND="numactl --cpunodebind=netdev:enp129s0f0 --membind=netdev:enp129s0f0"
    [ "${BENCHID:0:3}" = "st_" ] && NUMABIND="numactl --cpunodebind=1 --membind=1"

    echo "$CMDA2 $(statexec ${filepath}/${filename}.prom) -s -- $NUMABIND $@" > $OUTPUTDIR/${filename}.cmd

    $CMDA2 \
        $(statexec ${filepath}/${filename}.prom) -s -- \
        $NUMABIND $@ \
        > $OUTPUTDIR/${filename}.stdout \
        2> $OUTPUTDIR/${filename}.stderr

    # $CMDA2 \
    #     cat ${filepath}/${filename}.prom \
    #     > $OUTPUTDIR/${filename}.prom \
    #     2>/dev/null
    # kubectl -n network-test cp cni-benchmark-a2:/tmp/dts_1472-server.prom /tmp/results/cilium-nokproxy/1/dts_1472-server.prom
    kubectl -n $NAMESPACE cp --retries=5 cni-benchmark-a2:${filepath}/${filename}.prom ${OUTPUTDIR}/${filename}.prom 2>/dev/null

}
function clientcmd {
    # need to use /tmp to write files in our containers
    filepath="/tmp"
    filename="${TEST}-client"

    NUMABIND=""
    # numactl --cpunodebind 1 -s sleep 1
    #[ "${BENCHID:0:3}" = "st_" ] && NUMABIND="numactl --cpunodebind=netdev:enp129s0f0 --membind=netdev:enp129s0f0"
    [ "${BENCHID:0:3}" = "st_" ] && NUMABIND="numactl --cpunodebind=1 --membind=1"

    echo "$CMDA3 $(statexec ${filepath}/${filename}.prom) -dbc $(( ${DELAY_METRICS} + 1 ))  -c $DIRECT_A2 -- $NUMABIND $@" > $OUTPUTDIR/${filename}.cmd

    $CMDA3 \
        $(statexec ${filepath}/${filename}.prom) -dbc $(( ${DELAY_METRICS} + 1 ))  -c $DIRECT_A2 -- \
        $NUMABIND $@ \
        > $OUTPUTDIR/${filename}.stdout \
        2> $OUTPUTDIR/${filename}.stderr

    # $CMDA3 \
    #     cat ${filepath}/${filename}.prom \
    #     > $OUTPUTDIR/${filename}.prom \
    #     2>/dev/null

    # cat'ing the file sometimes failed to copy the whole prom file locally
    kubectl -n $NAMESPACE cp --retries=5 cni-benchmark-a3:${filepath}/${filename}.prom ${OUTPUTDIR}/${filename}.prom 2>/dev/null
}

function extract_metrics {
    PREFIX=$1

    CLIENT_SYSTEM=$(grep -E '^statexec_summary_cpu_mean_seconds{.*mode="system"' $OUTPUTDIR/${TEST}-client.prom | awk '{print $2}')
    CLIENT_USER=$(grep -E '^statexec_summary_cpu_mean_seconds{.*mode="user"' $OUTPUTDIR/${TEST}-client.prom | awk '{print $2}')
    CLIENT_MEM=$(grep -E '^statexec_summary_memory_used_bytes{' $OUTPUTDIR/${TEST}-client.prom | awk '{print $2}')
    
    SERVER_SYSTEM=$(grep -E '^statexec_summary_cpu_mean_seconds{.*mode="system"' $OUTPUTDIR/${TEST}-server.prom | awk '{print $2}')
    SERVER_USER=$(grep -E '^statexec_summary_cpu_mean_seconds{.*mode="user"' $OUTPUTDIR/${TEST}-server.prom | awk '{print $2}')
    SERVER_MEM=$(grep -E '^statexec_summary_memory_used_bytes{' $OUTPUTDIR/${TEST}-server.prom | awk '{print $2}')

    echo "${PREFIX}_CLIENT_SYSTEM=$CLIENT_SYSTEM"
    echo "${PREFIX}_CLIENT_USER=$CLIENT_USER"
    echo "${PREFIX}_CLIENT_MEM=$CLIENT_MEM"
    echo "${PREFIX}_SERVER_SYSTEM=$SERVER_SYSTEM"
    echo "${PREFIX}_SERVER_USER=$SERVER_USER"
    echo "${PREFIX}_SERVER_MEM=$SERVER_MEM"

}

function test_info {
    TEST="info"

    log start
    $CMDA2 ip a > $OUTPUTDIR/${TEST}-server.interfaces
    $CMDA2 uname -a > $OUTPUTDIR/${TEST}-server.uname
    $CMDA3 ip a > $OUTPUTDIR/${TEST}-client.interfaces
    $CMDA3 uname -a > $OUTPUTDIR/${TEST}-client.uname
    # This needs some tweaking to get working
    # $CURDIR/assets/test-netpol.sh > $OUTPUTDIR/${TEST}-netpol
    log end

}

function test_idle {
    TEST="idle"

    log start
    servercmd sleep $TEST_DURATION &
    WAITPID=$!
    sleep 1
    clientcmd sleep $TEST_DURATION
    wait $WAITPID

    extract_metrics IDLE > $OUTPUTDIR/${TEST}.results

    log end
}

# Direct TCP Single Stream
function test_dts {
    local size=${1:-8972}  # If size is not specified, default to 9000
    local v6=${2:-""}  # If v6 is not specified, default to empty string

    # Ensure size is an integer between 88 and 9000
    if ! [[ "$size" =~ ^[0-9]+$ ]] || ((size < 88 || size > 8972)); then
        echo "Error: size must be an integer between 88 and 8972"
        return 1
    fi

    # TEST="dts_"$size  # Append underscore and size value to test name
    if [ -z "$v6" ]; then
        TEST="dts_"$size
    else
        TEST="dts_"$size"_v6"
    fi

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    # clientcmd iperf3 -c $DIRECT_A2 -O 1 -Z -t $TEST_DURATION --dont-fragment --json
    if [ -z "$v6" ]; then
        clientcmd iperf3 -c $DIRECT_A2 -O 1 -Z -t $TEST_DURATION -M $size --json
    else
        clientcmd iperf3 -c $DIRECT_A2_V6 -O 1 -Z -t $TEST_DURATION -M $size -6 --json
    fi
    wait $WAITPID

    # Extract results
    DTS_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    DTS_RTS=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_sent.retransmits')

    if [ -z "$v6" ]; then
        extract_metrics DTS_$size > $OUTPUTDIR/${TEST}.results
        echo "DTS_${size}_BW=$DTS_BW" >> $OUTPUTDIR/${TEST}.results
        echo "DTS_${size}_RTS=$DTS_RTS" >> $OUTPUTDIR/${TEST}.results
    else
        extract_metrics DTS_${size}_V6 > $OUTPUTDIR/${TEST}.results
        echo "DTS_${size}_V6_BW=$DTS_BW" >> $OUTPUTDIR/${TEST}.results
        echo "DTS_${size}_V6_RTS=$DTS_RTS" >> $OUTPUTDIR/${TEST}.results
    fi
    
    log end
}

# Direct TCP Multi Stream
function test_dtm {
    local size=${1:-8972}  # If size is not specified, default to 9000
    local v6=${2:-""}  # If v6 is not specified, default to empty string

    # Ensure size is an integer between 88 and 9000
    if ! [[ "$size" =~ ^[0-9]+$ ]] || ((size < 88 || size > 8972)); then
        echo "Error: size must be an integer between 88 and 8972"
        return 1
    fi

    if [ -z "$v6" ]; then
        TEST="dtm_"$size
    else
        TEST="dtm_"$size"_v6"
    fi

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    # clientcmd iperf3 -c $DIRECT_A2 -O 1 -P 8 -Z -t $TEST_DURATION --dont-fragment --json
    if [ -z "$v6" ]; then
        clientcmd iperf3 -c $DIRECT_A2 -O 1 -P 8 -Z -t $TEST_DURATION -M $size --json
    else
        clientcmd iperf3 -c $DIRECT_A2_V6 -O 1 -P 8 -Z -t $TEST_DURATION -M $size -6 --json
    fi
    wait $WAITPID

    # Extract results
    DTM_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    DTM_RTS=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_sent.retransmits')

    if [ -z "$v6" ]; then
        extract_metrics DTM_$size > $OUTPUTDIR/${TEST}.results
        echo "DTM_${size}_BW=$DTS_BW" >> $OUTPUTDIR/${TEST}.results
        echo "DTM_${size}_RTS=$DTS_RTS" >> $OUTPUTDIR/${TEST}.results
    else
        extract_metrics DTM_${size}_V6 > $OUTPUTDIR/${TEST}.results
        echo "DTM_${size}_V6_BW=$DTM_BW" >> $OUTPUTDIR/${TEST}.results
        echo "DTM_${size}_V6_RTS=$DTM_RTS" >> $OUTPUTDIR/${TEST}.results
    fi

    log end
}

# Direct UDP Single Stream
function test_dus {
    TEST="dus"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $DIRECT_A2 -O 1 -u -b 0 -Z -t $TEST_DURATION --json
    wait $WAITPID

    # Extract results
    DUS_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    DUS_JITTER=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.jitter_ms')
    DUS_LOST=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.lost_percent')

    extract_metrics DUS > $OUTPUTDIR/${TEST}.results
    echo "DUS_BW=$DUS_BW" >> $OUTPUTDIR/${TEST}.results
    echo "DUS_JITTER=$DUS_JITTER" >> $OUTPUTDIR/${TEST}.results
    echo "DUS_LOST=$DUS_LOST" >> $OUTPUTDIR/${TEST}.results

    log end
}

# Direct UDP Multi Stream
function test_dum {
    TEST="dum"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $DIRECT_A2 -O 1 -u -b 0 -P 8 -Z -t $TEST_DURATION --json
    wait $WAITPID

    # Extract results
    DUM_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    DUM_JITTER=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.jitter_ms')
    DUM_LOST=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.lost_percent')

    extract_metrics DUM > $OUTPUTDIR/${TEST}.results
    echo "DUM_BW=$DUM_BW" >> $OUTPUTDIR/${TEST}.results
    echo "DUM_JITTER=$DUM_JITTER" >> $OUTPUTDIR/${TEST}.results
    echo "DUM_LOST=$DUM_LOST" >> $OUTPUTDIR/${TEST}.results

    log end
}

# Service TCP Single Stream
function test_sts {
    TEST="sts"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $SVC_A2 -O 1 -Z -t $TEST_DURATION --dont-fragment --json
    wait $WAITPID

    # Extract results
    STS_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    STS_RTS=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_sent.retransmits')

    extract_metrics STS > $OUTPUTDIR/${TEST}.results
    echo "STS_BW=$STS_BW" >> $OUTPUTDIR/${TEST}.results
    echo "STS_RTS=$STS_RTS" >> $OUTPUTDIR/${TEST}.results

    log end
}

# Service TCP Multi Stream
function test_stm {
    TEST="stm"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $SVC_A2 -O 1 -P 8 -Z -t $TEST_DURATION --dont-fragment --json
    wait $WAITPID

    # Extract results
    STM_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    STM_RTS=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_sent.retransmits')

    extract_metrics STM > $OUTPUTDIR/${TEST}.results
    echo "STM_BW=$STM_BW" >> $OUTPUTDIR/${TEST}.results
    echo "STM_RTS=$STM_RTS" >> $OUTPUTDIR/${TEST}.results

    log end
}

# Service UDP Single Stream
function test_sus {
    TEST="sus"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $SVC_A2 -O 1 -u -b 0 -Z -t $TEST_DURATION --json
    wait $WAITPID

    # Extract results
    SUS_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    SUS_JITTER=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.jitter_ms')
    SUS_LOST=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.lost_percent')

    extract_metrics SUS > $OUTPUTDIR/${TEST}.results
    echo "SUS_BW=$SUS_BW" >> $OUTPUTDIR/${TEST}.results
    echo "SUS_JITTER=$SUS_JITTER" >> $OUTPUTDIR/${TEST}.results
    echo "SUS_LOST=$SUS_LOST" >> $OUTPUTDIR/${TEST}.results

    log end
}

# Service UDP Multi Stream
function test_sum {
    TEST="sum"

    log start
    servercmd iperf3 -s &
    WAITPID=$!
    sleep 1
    clientcmd iperf3 -c $SVC_A2 -O 1 -u -b 0 -P 8 -Z -t $TEST_DURATION --json
    wait $WAITPID

    # Extract results
    SUM_BW=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.bits_per_second')
    SUM_JITTER=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.jitter_ms')
    SUM_LOST=$(cat $OUTPUTDIR/${TEST}-client.stdout | jq -r '.end.sum_received.lost_percent')

    extract_metrics SUM > $OUTPUTDIR/${TEST}.results
    echo "SUM_BW=$SUM_BW" >> $OUTPUTDIR/${TEST}.results
    echo "SUM_JITTER=$SUM_JITTER" >> $OUTPUTDIR/${TEST}.results
    echo "SUM_LOST=$SUM_LOST" >> $OUTPUTDIR/${TEST}.results

    log end
}

function test_cleanup {
    TEST="cleanup"

    log start
    ./maas.sh cleanup > /dev/null 2>&1
    sleep 10
    log end
}

function reset_result_vars {
    unset IDLE_CLIENT_SYSTEM IDLE_CLIENT_USER IDLE_CLIENT_MEM IDLE_SERVER_SYSTEM IDLE_SERVER_USER IDLE_SERVER_MEM
    unset DTS_88_CLIENT_SYSTEM DTS_88_CLIENT_USER DTS_88_CLIENT_MEM DTS_88_SERVER_SYSTEM DTS_88_SERVER_USER DTS_88_SERVER_MEM DTS_88_BW DTS_88_RTS
    unset DTS_1472_CLIENT_SYSTEM DTS_1472_CLIENT_USER DTS_1472_CLIENT_MEM DTS_1472_SERVER_SYSTEM DTS_1472_SERVER_USER DTS_1472_SERVER_MEM DTS_1472_BW DTS_1472_RTS
    unset DTS_8972_CLIENT_SYSTEM DTS_8972_CLIENT_USER DTS_8972_CLIENT_MEM DTS_8972_SERVER_SYSTEM DTS_8972_SERVER_USER DTS_8972_SERVER_MEM DTS_8972_BW DTS_8972_RTS
    unset DTS_1472_V6_CLIENT_SYSTEM DTS_1472_V6_CLIENT_USER DTS_1472_V6_CLIENT_MEM DTS_1472_V6_SERVER_SYSTEM DTS_1472_V6_SERVER_USER DTS_1472_V6_SERVER_MEM DTS_1472_V6_BW DTS_1472_V6_RTS
    unset DTS_8972_V6_CLIENT_SYSTEM DTS_8972_V6_CLIENT_USER DTS_8972_V6_CLIENT_MEM DTS_8972_V6_SERVER_SYSTEM DTS_8972_V6_SERVER_USER DTS_8972_V6_SERVER_MEM DTS_8972_V6_BW DTS_8972_V6_RTS
    unset DTS_CLIENT_SYSTEM DTS_CLIENT_USER DTS_CLIENT_MEM DTS_SERVER_SYSTEM DTS_SERVER_USER DTS_SERVER_MEM DTS_BW DTS_RTS
    unset DTM_CLIENT_SYSTEM DTM_CLIENT_USER DTM_CLIENT_MEM DTM_SERVER_SYSTEM DTM_SERVER_USER DTM_SERVER_MEM DTM_BW DTM_RTS
    unset DUS_CLIENT_SYSTEM DUS_CLIENT_USER DUS_CLIENT_MEM DUS_SERVER_SYSTEM DUS_SERVER_USER DUS_SERVER_MEM DUS_BW DUS_JITTER DUS_LOST
    unset DUM_CLIENT_SYSTEM DUM_CLIENT_USER DUM_CLIENT_MEM DUM_SERVER_SYSTEM DUM_SERVER_USER DUM_SERVER_MEM DUM_BW DUM_JITTER DUM_LOST
    unset STS_CLIENT_SYSTEM STS_CLIENT_USER STS_CLIENT_MEM STS_SERVER_SYSTEM STS_SERVER_USER STS_SERVER_MEM STS_BW STS_RTS
    unset STM_CLIENT_SYSTEM STM_CLIENT_USER STM_CLIENT_MEM STM_SERVER_SYSTEM STM_SERVER_USER STM_SERVER_MEM STM_BW STM_RTS
    unset SUS_CLIENT_SYSTEM SUS_CLIENT_USER SUS_CLIENT_MEM SUS_SERVER_SYSTEM SUS_SERVER_USER SUS_SERVER_MEM SUS_BW SUS_JITTER SUS_LOST
    unset SUM_CLIENT_SYSTEM SUM_CLIENT_USER SUM_CLIENT_MEM SUM_SERVER_SYSTEM SUM_SERVER_USER SUM_SERVER_MEM SUM_BW SUM_JITTER SUM_LOST
}

function compute_results {
    # Compute results
    # RUNS=$(cd ./results/$BENCHID; ls -1 |grep -E "^[0-9]+$")
    RUNS=$(cd /tmp/results/$BENCHID; ls -1 |grep -E "^[0-9]+$")
    echo $RUNS
    for i in $RUNS
    do
        reset_result_vars
        source /tmp/results/$BENCHID/$i/all.results
        (
            echo -en "IDLE: $IDLE_CLIENT_SYSTEM\t$IDLE_CLIENT_USER\t$IDLE_CLIENT_MEM\t$IDLE_SERVER_SYSTEM\t$IDLE_SERVER_USER\t$IDLE_SERVER_MEM\t"
            echo -en "DTS: $DTS_CLIENT_SYSTEM\t$DTS_CLIENT_USER\t$DTS_CLIENT_MEM\t$DTS_SERVER_SYSTEM\t$DTS_SERVER_USER\t$DTS_SERVER_MEM\t$DTS_BW\t$DTS_RTS\t"
            echo -en "DTS_88: $DTS_88_CLIENT_SYSTEM\t$DTS_88_CLIENT_USER\t$DTS_88_CLIENT_MEM\t$DTS_88_SERVER_SYSTEM\t$DTS_88_SERVER_USER\t$DTS_88_SERVER_MEM\t$DTS_88_BW\t$DTS_88_RTS\t"
            echo -en "DTS_1472: $DTS_1472_CLIENT_SYSTEM\t$DTS_1472_CLIENT_USER\t$DTS_1472_CLIENT_MEM\t$DTS_1472_SERVER_SYSTEM\t$DTS_1472_SERVER_USER\t$DTS_1472_SERVER_MEM\t$DTS_1472_BW\t$DTS_1472_RTS\t"
            echo -en "DTS_8972: $DTS_8972_CLIENT_SYSTEM\t$DTS_8972_CLIENT_USER\t$DTS_8972_CLIENT_MEM\t$DTS_8972_SERVER_SYSTEM\t$DTS_8972_SERVER_USER\t$DTS_8972_SERVER_MEM\t$DTS_8972_BW\t$DTS_8972_RTS\t"
            echo -en "DTS_1472_V6: $DTS_1472_V6_CLIENT_SYSTEM\t$DTS_1472_V6_CLIENT_USER\t$DTS_1472_V6_CLIENT_MEM\t$DTS_1472_V6_SERVER_SYSTEM\t$DTS_1472_V6_SERVER_USER\t$DTS_1472_V6_SERVER_MEM\t$DTS_1472_V6_BW\t$DTS_1472_V6_RTS\t"
            echo -en "DTS_8972_V6: $DTS_8972_V6_CLIENT_SYSTEM\t$DTS_8972_V6_CLIENT_USER\t$DTS_8972_V6_CLIENT_MEM\t$DTS_8972_V6_SERVER_SYSTEM\t$DTS_8972_V6_SERVER_USER\t$DTS_8972_V6_SERVER_MEM\t$DTS_8972_V6_BW\t$DTS_8972_V6_RTS\t"
            echo -en "DTM_88: $DTM_88_CLIENT_SYSTEM\t$DTM_88_CLIENT_USER\t$DTM_88_CLIENT_MEM\t$DTM_88_SERVER_SYSTEM\t$DTM_88_SERVER_USER\t$DTM_88_SERVER_MEM\t$DTM_88_BW\t$DTM_88_RTS\t"
            echo -en "DTM_1472: $DTM_1472_CLIENT_SYSTEM\t$DTM_1472_CLIENT_USER\t$DTM_1472_CLIENT_MEM\t$DTM_1472_SERVER_SYSTEM\t$DTM_1472_SERVER_USER\t$DTM_1472_SERVER_MEM\t$DTM_1472_BW\t$DTM_1472_RTS\t"
            echo -en "DTM_8972: $DTM_8972_CLIENT_SYSTEM\t$DTM_8972_CLIENT_USER\t$DTM_8972_CLIENT_MEM\t$DTM_8972_SERVER_SYSTEM\t$DTM_8972_SERVER_USER\t$DTM_8972_SERVER_MEM\t$DTM_8972_BW\t$DTM_8972_RTS\t"
            echo -en "DTM_1472_V6: $DTM_1472_V6_CLIENT_SYSTEM\t$DTM_1472_V6_CLIENT_USER\t$DTM_1472_V6_CLIENT_MEM\t$DTM_1472_V6_SERVER_SYSTEM\t$DTM_1472_V6_SERVER_USER\t$DTM_1472_V6_SERVER_MEM\t$DTM_1472_V6_BW\t$DTM_1472_V6_RTS\t"
            echo -en "DTM_8972_V6: $DTM_8972_V6_CLIENT_SYSTEM\t$DTM_8972_V6_CLIENT_USER\t$DTM_8972_V6_CLIENT_MEM\t$DTM_8972_V6_SERVER_SYSTEM\t$DTM_8972_V6_SERVER_USER\t$DTM_8972_V6_SERVER_MEM\t$DTM_8972_V6_BW\t$DTM_8972_V6_RTS\t"
            echo -en "DUS: $DUS_CLIENT_SYSTEM\t$DUS_CLIENT_USER\t$DUS_CLIENT_MEM\t$DUS_SERVER_SYSTEM\t$DUS_SERVER_USER\t$DUS_SERVER_MEM\t$DUS_BW\t$DUS_JITTER\t$DUS_LOST\t"
            echo -en "DUM: $DUM_CLIENT_SYSTEM\t$DUM_CLIENT_USER\t$DUM_CLIENT_MEM\t$DUM_SERVER_SYSTEM\t$DUM_SERVER_USER\t$DUM_SERVER_MEM\t$DUM_BW\t$DUM_JITTER\t$DUM_LOST\t"
            echo -en "STS: $STS_CLIENT_SYSTEM\t$STS_CLIENT_USER\t$STS_CLIENT_MEM\t$STS_SERVER_SYSTEM\t$STS_SERVER_USER\t$STS_SERVER_MEM\t$STS_BW\t$STS_RTS\t"
            echo -en "STM: $STM_CLIENT_SYSTEM\t$STM_CLIENT_USER\t$STM_CLIENT_MEM\t$STM_SERVER_SYSTEM\t$STM_SERVER_USER\t$STM_SERVER_MEM\t$STM_BW\t$STM_RTS\t"
            echo -en "SUS: $SUS_CLIENT_SYSTEM\t$SUS_CLIENT_USER\t$SUS_CLIENT_MEM\t$SUS_SERVER_SYSTEM\t$SUS_SERVER_USER\t$SUS_SERVER_MEM\t$SUS_BW\t$SUS_JITTER\t$SUS_LOST\t"
            echo -en "SUM: $SUM_CLIENT_SYSTEM\t$SUM_CLIENT_USER\t$SUM_CLIENT_MEM\t$SUM_SERVER_SYSTEM\t$SUM_SERVER_USER\t$SUM_SERVER_MEM\t$SUM_BW\t$SUM_JITTER\t$SUM_LOST\t"
            echo        
        ) >> /tmp/results/$BENCHID/results-spreadsheet.csv
        # ) >> ./results/$BENCHID/results-spreadsheet.csv
        
        (
            LABELS='id="'$BENCHID'",run="'$i'"'

            if [ ! -z "$IDLE_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="idle",role="client",mode="system"} '${IDLE_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="idle",role="client",mode="user"} '${IDLE_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="idle",role="client"} '${IDLE_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="idle",role="server",mode="system"} '${IDLE_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="idle",role="server",mode="user"} '${IDLE_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="idle",role="server"} '${IDLE_SERVER_MEM}' 1704067200000'
            fi

            if [ ! -z "$DTS_88_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_88",role="client",mode="system"} '${DTS_88_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_88",role="client",mode="user"} '${DTS_88_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_88",role="client"} '${DTS_88_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_88",role="server",mode="system"} '${DTS_88_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_88",role="server",mode="user"} '${DTS_88_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_88",role="server"} '${DTS_88_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dts_88"} '${DTS_88_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dts_88"} '${DTS_88_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTS_1472_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472",role="client",mode="system"} '${DTS_1472_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472",role="client",mode="user"} '${DTS_1472_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_1472",role="client"} '${DTS_1472_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472",role="server",mode="system"} '${DTS_1472_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472",role="server",mode="user"} '${DTS_1472_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_1472",role="server"} '${DTS_1472_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dts_1472"} '${DTS_1472_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dts_1472"} '${DTS_1472_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTS_8972_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972",role="client",mode="system"} '${DTS_8972_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972",role="client",mode="user"} '${DTS_8972_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_8972",role="client"} '${DTS_8972_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972",role="server",mode="system"} '${DTS_8972_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972",role="server",mode="user"} '${DTS_8972_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_8972",role="server"} '${DTS_8972_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dts_8972"} '${DTS_8972_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dts_8972"} '${DTS_8972_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTS_1472_V6_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472_v6",role="client",mode="system"} '${DTS_1472_V6_CLIENT_SYSTEM}' 17040672_v600000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472_v6",role="client",mode="user"} '${DTS_1472_V6_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_1472_v6",role="client"} '${DTS_1472_V6_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472_v6",role="server",mode="system"} '${DTS_1472_V6_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_1472_v6",role="server",mode="user"} '${DTS_1472_V6_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_1472_v6",role="server"} '${DTS_1472_V6_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dts_1472_v6"} '${DTS_1472_V6_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dts_1472_v6"} '${DTS_1472_V6_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTS_8972_V6_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972_v6",role="client",mode="system"} '${DTS_8972_V6_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972_v6",role="client",mode="user"} '${DTS_8972_V6_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_8972_v6",role="client"} '${DTS_8972_V6_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972_v6",role="server",mode="system"} '${DTS_8972_V6_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dts_8972_v6",role="server",mode="user"} '${DTS_8972_V6_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dts_8972_v6",role="server"} '${DTS_8972_V6_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dts_8972_v6"} '${DTS_8972_V6_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dts_8972_v6"} '${DTS_8972_V6_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTM_88_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_88",role="client",mode="system"} '${DTM_88_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_88",role="client",mode="user"} '${DTM_88_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_88",role="client"} '${DTM_88_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_88",role="server",mode="system"} '${DTM_88_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_88",role="server",mode="user"} '${DTM_88_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_88",role="server"} '${DTM_88_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dtm_88"} '${DTM_88_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dtm_88"} '${DTM_88_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTM_1472_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472",role="client",mode="system"} '${DTM_1472_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472",role="client",mode="user"} '${DTM_1472_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_1472",role="client"} '${DTM_1472_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472",role="server",mode="system"} '${DTM_1472_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472",role="server",mode="user"} '${DTM_1472_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_1472",role="server"} '${DTM_1472_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dtm_1472"} '${DTM_1472_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dtm_1472"} '${DTM_1472_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTM_8972_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972",role="client",mode="system"} '${DTM_8972_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972",role="client",mode="user"} '${DTM_8972_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_8972",role="client"} '${DTM_8972_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972",role="server",mode="system"} '${DTM_8972_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972",role="server",mode="user"} '${DTM_8972_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_8972",role="server"} '${DTM_8972_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dtm_8972"} '${DTM_8972_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dtm_8972"} '${DTM_8972_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTM_1472_V6_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472_v6",role="client",mode="system"} '${DTM_1472_V6_CLIENT_SYSTEM}' 17040672_v600000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472_v6",role="client",mode="user"} '${DTM_1472_V6_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_1472_v6",role="client"} '${DTM_1472_V6_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472_v6",role="server",mode="system"} '${DTM_1472_V6_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_1472_v6",role="server",mode="user"} '${DTM_1472_V6_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_1472_v6",role="server"} '${DTM_1472_V6_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dtm_1472_v6"} '${DTM_1472_V6_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dtm_1472_v6"} '${DTM_1472_V6_RTS}' 1704067200000'
            fi

            if [ ! -z "$DTM_8972_V6_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972_v6",role="client",mode="system"} '${DTM_8972_V6_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972_v6",role="client",mode="user"} '${DTM_8972_V6_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_8972_v6",role="client"} '${DTM_8972_V6_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972_v6",role="server",mode="system"} '${DTM_8972_V6_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dtm_8972_v6",role="server",mode="user"} '${DTM_8972_V6_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dtm_8972_v6",role="server"} '${DTM_8972_V6_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dtm_8972_v6"} '${DTM_8972_V6_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="dtm_8972_v6"} '${DTM_8972_V6_RTS}' 1704067200000'
            fi

            if [ ! -z "$DUS_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dus",role="client",mode="system"} '${DUS_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dus",role="client",mode="user"} '${DUS_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dus",role="client"} '${DUS_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dus",role="server",mode="system"} '${DUS_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dus",role="server",mode="user"} '${DUS_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dus",role="server"} '${DUS_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dus"} '${DUS_BW}' 1704067200000'
                echo 'benchmark_iperf_jitter_milliseconds{'$LABELS',test="dus"} '${DUS_JITTER}' 1704067200000'
                echo 'benchmark_iperf_lost_percent{'$LABELS',test="dus"} '${DUS_LOST}' 1704067200000'
            fi

            if [ ! -z "$DUM_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="dum",role="client",mode="system"} '${DUM_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dum",role="client",mode="user"} '${DUM_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dum",role="client"} '${DUM_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dum",role="server",mode="system"} '${DUM_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="dum",role="server",mode="user"} '${DUM_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="dum",role="server"} '${DUM_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="dum"} '${DUM_BW}' 1704067200000'
                echo 'benchmark_iperf_jitter_milliseconds{'$LABELS',test="dum"} '${DUM_JITTER}' 1704067200000'
                echo 'benchmark_iperf_lost_percent{'$LABELS',test="dum"} '${DUM_LOST}' 1704067200000'
            fi 

            if [ ! -z "$STS_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="sts",role="client",mode="system"} '${STS_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sts",role="client",mode="user"} '${STS_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sts",role="client"} '${STS_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sts",role="server",mode="system"} '${STS_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sts",role="server",mode="user"} '${STS_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sts",role="server"} '${STS_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="sts"} '${STS_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="sts"} '${STS_RTS}' 1704067200000'
            fi

            if [ ! -z "$STM_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="stm",role="client",mode="system"} '${STM_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="stm",role="client",mode="user"} '${STM_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="stm",role="client"} '${STM_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="stm",role="server",mode="system"} '${STM_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="stm",role="server",mode="user"} '${STM_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="stm",role="server"} '${STM_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="stm"} '${STM_BW}' 1704067200000'
                echo 'benchmark_iperf_retransmits_count{'$LABELS',test="stm"} '${STM_RTS}' 1704067200000'
            fi

            if [ ! -z "$SUS_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="sus",role="client",mode="system"} '${SUS_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sus",role="client",mode="user"} '${SUS_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sus",role="client"} '${SUS_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sus",role="server",mode="system"} '${SUS_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sus",role="server",mode="user"} '${SUS_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sus",role="server"} '${SUS_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="sus"} '${SUS_BW}' 1704067200000'
                echo 'benchmark_iperf_jitter_milliseconds{'$LABELS',test="sus"} '${SUS_JITTER}' 1704067200000'
                echo 'benchmark_iperf_lost_percent{'$LABELS',test="sus"} '${SUS_LOST}' 1704067200000'
            fi

            if [ ! -z "$SUM_CLIENT_SYSTEM" ]; then
                echo 'benchmark_cpu_seconds{'$LABELS',test="sum",role="client",mode="system"} '${SUM_CLIENT_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sum",role="client",mode="user"} '${SUM_CLIENT_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sum",role="client"} '${SUM_CLIENT_MEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sum",role="server",mode="system"} '${SUM_SERVER_SYSTEM}' 1704067200000'
                echo 'benchmark_cpu_seconds{'$LABELS',test="sum",role="server",mode="user"} '${SUM_SERVER_USER}' 1704067200000'
                echo 'benchmark_mem_bytes{'$LABELS',test="sum",role="server"} '${SUM_SERVER_MEM}' 1704067200000'
                echo 'benchmark_iperf_bandwidth_bits_per_second{'$LABELS',test="sum"} '${SUM_BW}' 1704067200000'
                echo 'benchmark_iperf_jitter_milliseconds{'$LABELS',test="sum"} '${SUM_JITTER}' 1704067200000'
                echo 'benchmark_iperf_lost_percent{'$LABELS',test="sum"} '${SUM_LOST}' 1704067200000'
            fi
        ) >> /tmp/results/$BENCHID/results.prom
        # ) >> ./results/$BENCHID/results.prom
    done
}

function bench_cni {
    BENCHID="$1"
    shift

    CMDA1="kubectl -n $NAMESPACE exec -it cni-benchmark-a1 -- "
    CMDA2="kubectl -n $NAMESPACE exec -it cni-benchmark-a2 -- "
    CMDA3="kubectl -n $NAMESPACE exec -it cni-benchmark-a3 -- "

    SVC_A1="cni-benchmark-a1"
    SVC_A2="cni-benchmark-a2"
    SVC_A3="cni-benchmark-a3"

    # if  $WIPE_RESULTS=; then
    #     echo "Wiping results"
    #     [ -d ./results/$BENCHID ] && rm -rf ./results/$BENCHID
    # fi

    for RUNID in $(seq 1 ${BENCHMARK_NUMBER_OF_RUNS}); do

        test_prepare

        # don't need to tweak cluster
        # test_setup

        kubectl -n $NAMESPACE apply -f ./assets/benchmark-resources.yaml

        kubectl -n $NAMESPACE wait --for=condition=Ready pod/cni-benchmark-a1 --timeout=300s
        kubectl -n $NAMESPACE wait --for=condition=Ready pod/cni-benchmark-a2 --timeout=300s
        kubectl -n $NAMESPACE wait --for=condition=Ready pod/cni-benchmark-a3 --timeout=300s

        DIRECT_A1="$(kubectl -n $NAMESPACE get pod cni-benchmark-a1 -o jsonpath='{.status.podIP}')"
        DIRECT_A2="$(kubectl -n $NAMESPACE get pod cni-benchmark-a2 -o jsonpath='{.status.podIP}')"
        DIRECT_A3="$(kubectl -n $NAMESPACE get pod cni-benchmark-a3 -o jsonpath='{.status.podIP}')"

        # Making a big assumption that the v4 addr is always returned first
        # could loop through results and do a simple test for colon to determine v6
        # kubectl -n network-test get pod cni-benchmark-a1 -o jsonpath='{.status.podIPs}'
        # [{"ip":"198.19.2.107"},{"ip":"2001:558:104c:10a::2:5bff"}]
        DIRECT_A2_V6="$(kubectl -n $NAMESPACE get pod cni-benchmark-a2 -o jsonpath='{.status.podIPs[1].ip}')"
        # kubectl -n network-test get service cni-benchmark-a2 -o jsonpath='{.status.loadBalancer.ingress}'
        # [{"ip":"10.112.182.57"},{"ip":"2001:558:104c:108::1:7"}]
        SVC_A2_V6=kubectl -n network-test get service cni-benchmark-a2 -o jsonpath='{.status.loadBalancer.ingress[1].ip}'
        test_info

        test_idle
        
        # You can pass in different values for packet size in each test, but if you deviate from 88, 1472, and 8972,
        # you'll need to update the metrics gathering in compute_results and the grafana dashboard json definitions
        # in explorer/config/grafana-dashboards/benchmark.json
        test_dts 88
        test_dts 1472
        test_dts 8972
        test_dts 1472 v6
        test_dts 8972 v6
        test_dtm 88
        test_dtm 1472
        test_dtm 8972
        test_dtm 1472 v6
        test_dtm 8972 v6
        # test_dus
        # test_dum
        
        # test_sts
        # test_stm
        # test_sus
        # test_sum

        cat $OUTPUTDIR/*.results > $OUTPUTDIR/all.results

        # cleans up the maas stuff that we're not currently using
        # test_cleanup
    done

    compute_results
}

function bench_baremetal {
    BENCHID="$1"
    EXEC_CMD="./maas.sh ssh"

    CMDA1="./maas.sh ssh a1"
    CMDA2="./maas.sh ssh a2"
    CMDA3="./maas.sh ssh a3"

    DIRECT_A1="$(./maas.sh getip a1)"
    DIRECT_A2="$(./maas.sh getip a2)"
    DIRECT_A3="$(./maas.sh getip a3)"

    [ -d ./results/$BENCHID ] && rm -rf ./results/$BENCHID

    for RUNID in $(seq 1 ${BENCHMARK_NUMBER_OF_RUNS}); do

        test_prepare
        
        test_idle
        
        test_dts
        test_dtm
        test_dus
        test_dum
        
        # There is no service mode for baremetal as there is no k8s
        # test_sts
        # test_stm
        # test_sus
        # test_sum

        cat $OUTPUTDIR/*.results > $OUTPUTDIR/all.results

        test_cleanup
    done

    compute_results
}

case $1 in 
    baremetal|bm)
        bench_baremetal baremetal
        ;;
    tuned-baremetal|tbm)
        BENCHSUFFIX=""
        [ ! -z "$2" ] && BENCHSUFFIX="_${2}"
        bench_baremetal st_baremetal${BENCHSUFFIX}
        ;;
    cni)
        export NOKUBEPROXY="false"
        grep -q "#Flag:NOKUBEPROXY" ./setup/cni-configs/$2.sh && export NOKUBEPROXY="true"
        echo "NOKUBEPROXY = $NOKUBEPROXY"
        bench_cni $2 ${@:2}
        ;;
    tuned-cni|tcni)
        export NOKUBEPROXY="false"
        grep -q "#Flag:NOKUBEPROXY" ./setup/cni-configs/$2.sh && export NOKUBEPROXY="true"
        bench_cni st_$2 ${@:3}
        ;;
    *)
        echo "Usage: $0 (baremetal|cni <cni>)"
        exit 1
        ;;
esac
