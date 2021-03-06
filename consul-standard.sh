#!/bin/bash

function addConsulDnsDockerOpts()
{
    printf "***** Adding Consul DNS DOCKER_OPTS if needed\n"

    local toBeAppended="DOCKER_OPTS='--dns $(_dockerBridgeIp) --dns 8.8.8.8 --dns-search service.consul dns-search node.consul'"

    if [ ! -f /etc/default/docker ] || [ "$(grep -c DOCKER_OPTS /etc/default/docker)" -eq "0" ]; then
        echo $toBeAppended | sudo tee --append /etc/default/docker > /dev/null
        sudo service docker restart
    fi
}

function startRedis()
{
    printf "***** Starting Redis\n"

    local container=''

    container='beredissrv1' && docker run --name $container -d redis && _printContainerNameAndIp $container
    container='beredissrv2' && docker run --name $container -d redis && _printContainerNameAndIp $container
    container='feredissrv1' && docker run --name $container -d redis && _printContainerNameAndIp $container
    container='feredissrv2' && docker run --name $container -d redis && _printContainerNameAndIp $container
}

function pushItemsToRedis()
{
    printf "***** Pushing items to Redis\n"

    docker run -it --link beredissrv1:redis --rm redis redis-cli -h redis -p 6379 lpush myBeList1 BeL1First > /dev/null && \
    printf "Server beredissrv1 - Key myBeList1 items:\n" && \
    docker run -it --link beredissrv1:redis --rm redis redis-cli -h redis -p 6379 lrange myBeList1 0 -1

    docker run -it --link beredissrv2:redis --rm redis redis-cli -h redis -p 6379 lpush myBeList2 BeL2First > /dev/null && \
    printf "\nServer beredissrv2 - Key myBeList2 items:\n" && \
    docker run -it --link beredissrv2:redis --rm redis redis-cli -h redis -p 6379 lrange myBeList2 0 -1

    docker run -it --link feredissrv1:redis --rm redis redis-cli -h redis -p 6379 lpush myFeList1 FeL1First > /dev/null && \
    printf "\nServer feredissrv1 - Key myFeList1 items:\n" && \
    docker run -it --link feredissrv1:redis --rm redis redis-cli -h redis -p 6379 lrange myFeList1 0 -1

    docker run -it --link feredissrv2:redis --rm redis redis-cli -h redis -p 6379 lpush myFeList2 FeL2First > /dev/null && \
    printf "\nServer feredissrv2 - Key myFeList2 items:\n" && \
    docker run -it --link feredissrv2:redis --rm redis redis-cli -h redis -p 6379 lrange myFeList2 0 -1
}

function startConsulBootstrapAgents()
{
    printf "***** Starting consul bootsrap agents\n"

    local agent=''

    agent='be1srv1' && docker run -p 8411:8400 -p 8511:8500 -p 8611:8600/udp -p $(_dockerBridgeIp):53:8600/udp --name $agent -h $agent -d gliderlabs/consul-server -bootstrap-expect 3 -dc "backend" && _printContainerNameAndIp $agent
    agent='fe1srv1' && docker run -p 8421:8400 -p 8521:8500 -p 8621:8600/udp --name $agent -h $agent -d gliderlabs/consul-server -bootstrap-expect 3 -dc "frontend" && _printContainerNameAndIp $agent
    
    hostIp=$(_usedInterfaceIp)
    printf "BE Web UI URL is http://$hostIp:8511/ui and FE Web UI URL is http://$hostIp:8521/ui\n"
}

function startConsulMonitor()
{
    printf "***** Starting consul monitor\n"

    # hostname -i
    local ip=$1
    
    # 8411 or 8421
    local port=$2
    
    consul monitor -log-level "info" -rpc-addr "$ip:$port"
}

function startConsulNonBootstrapAgents()
{
    printf "***** Starting consul non bootsrap agents\n"

    local agent=''

    local beJoinIp="$(_containerIp be1srv1)"

    agent='be2srv2' && docker run -d -p 8412:8400 -p 8512:8500 -p 8612:8600/udp --name $agent -h $agent gliderlabs/consul-server -dc "backend" -join $beJoinIp -join-wan $beJoinIp && _printContainerNameAndIp $agent
    agent='be3srv3' && docker run -d -p 8413:8400 -p 8513:8500 -p 8613:8600/udp --name $agent -h $agent gliderlabs/consul-server -dc "backend" -join $beJoinIp -join-wan $beJoinIp && _printContainerNameAndIp $agent
    agent='be4cli1' && docker run -d -p 8414:8400 -p 8514:8500 -p 8614:8600/udp --name $agent -h $agent gliderlabs/consul-agent -dc "backend" -join $beJoinIp && _printContainerNameAndIp $agent
    agent='be5cli2' && docker run -d -p 8415:8400 -p 8515:8500 -p 8615:8600/udp --name $agent -h $agent gliderlabs/consul-agent -dc "backend" -join $beJoinIp && _printContainerNameAndIp $agent

    local feJoinIp="$(_containerIp fe1srv1)"
    
    agent='fe2srv2' && docker run -d -p 8422:8400 -p 8522:8500 -p 8622:8600/udp --name $agent -h $agent gliderlabs/consul-server -dc "frontend" -join $feJoinIp -join-wan $feJoinIp && _printContainerNameAndIp $agent
    agent='fe3srv3' && docker run -d -p 8423:8400 -p 8523:8500 -p 8623:8600/udp --name $agent -h $agent gliderlabs/consul-server -dc "frontend" -join $feJoinIp -join-wan $feJoinIp && _printContainerNameAndIp $agent
    agent='fe4cli1' && docker run -d -p 8424:8400 -p 8524:8500 -p 8624:8600/udp --name $agent -h $agent gliderlabs/consul-agent -dc "frontend" -join $feJoinIp && _printContainerNameAndIp $agent
    agent='fe5cli2' && docker run -d -p 8425:8400 -p 8525:8500 -p 8625:8600/udp --name $agent -h $agent gliderlabs/consul-agent -dc "frontend" -join $feJoinIp && _printContainerNameAndIp $agent
}

function joinDatacenters()
{
    printf "***** Joining data centers\n"

    printf "Data centers before join (look also at Web UIs):\n$(curl --silent 'http://localhost:8515/v1/catalog/datacenters')\n"
    
    local beJoinIp="$(_containerIp be1srv1)"
    docker exec fe1srv1 /bin/consul join -wan $beJoinIp
    sleep 5

    printf "Data centers after join (look also at Web UIs):\n$(curl --silent 'http://localhost:8515/v1/catalog/datacenters')\n"
}

function showCatalogInfo()
{
    printf "***** Showing catalog info\n"

    printf "catalog/nodes\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes' | jq

    printf "catalog/nodes?dc=frontend&near=fe4cli1\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes?dc=frontend&near=fe4cli1' | jq

    printf "catalog/node/be1srv1\n"
    curl --silent 'http://localhost:8515/v1/catalog/node/be1srv1' | jq

    printf "catalog/services\n"
    curl --silent 'http://localhost:8515/v1/catalog/services' | jq

    printf "catalog/service/consul\n"
    curl --silent 'http://localhost:8515/v1/catalog/service/consul' | jq
}

function showCoordinateInfo()
{
    printf "***** Showing coordinate info\n"

    printf "coordinate/datacenters\n"
    curl --silent 'http://localhost:8515/v1/coordinate/datacenters' | jq

    printf "coordinate/nodes\n"
    curl --silent 'http://localhost:8515/v1/coordinate/nodes' | jq
}

function showAgentConfiguration()
{
    printf "***** Showing local agent configuration\n"

    # 8515
    local port=$1
    curl --silent "http://localhost:$port/v1/agent/self" | jq
}

function _showAgentServicesAndChecks()
{
    local port=$1
    
    printf "agent/services\n"
    curl --silent "http://localhost:$port/v1/agent/services" | jq

    printf "agent/checks\n"
    curl --silent "http://localhost:$port/v1/agent/checks" | jq
}

function _removeAgentService()
{
    # 8515
    local port=$1
    local serviceId=$2

    curl --silent "http://localhost:$port/v1/agent/service/deregister/$serviceId"
    printf "Removed service with ID $serviceId\n"
}

function _removeAgentCheck()
{
    # 8515
    local port=$1
    local checkId=$2

    curl --silent "http://localhost:$port/v1/agent/check/deregister/$checkId"
    printf "Removed check with ID $checkId\n"
}

function addAgentServiceAndCheckSeparately()
{
    printf "***** Adding agent service and check separately\n"

    local beredissrv1Ip="$(_containerIp beredissrv1)"

    curl --silent -X PUT --data '{ "ID": "berdssrv1", "Name": "be-redis", "Tags": [ "official", "nosql" ], "Address": "'$beredissrv1Ip'", "Port": 6379 }' 'http://localhost:8514/v1/agent/service/register'
    printf "Added service { ID: \"berdssrv1\", Name: \"be-redis\" }\n"
    _showAgentServicesAndChecks 8514

    curl --silent -X PUT --data '{ "ServiceID": "berdssrv1", "ID": "beredissrv1UpAndRunning", "Name": "BE Redis 1 up and running", "TCP": "'$beredissrv1Ip':6379", "interval": "20s", "timeout": "2s" }' 'http://localhost:8514/v1/agent/check/register'
    printf "Added check for service with ID berdssrv1 { ID: \"beredissrv1UpAndRunning\", Name: \"BE Redis 1 up and running\" }\n"
    _showAgentServicesAndChecks 8514
}

function addAgentServiceAndCheckAtOnce()
{
    printf "***** Adding agent service and check at once\n"

    local beredissrv2Ip="$(_containerIp beredissrv2)"

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "$beredissrv2Ip", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "15s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Added service { ID: \"berdssrv2\", Name: \"be-redis\" } and check { ID: \"service:berdssrv2\", Name: \"Service 'be-redis' check\" }\n"
    _showAgentServicesAndChecks 8515

    _removeAgentService 8515 'berdssrv2'
    _showAgentServicesAndChecks 8515

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "'$beredissrv2Ip'", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "5s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Readded service { ID: \"berdssrv2\", Name: \"be-redis\" } and check { ID: \"service:berdssrv2\", Name: \"Service 'be-redis' check\" }\n"
    _showAgentServicesAndChecks 8515

    _removeAgentCheck 8515 'service:berdssrv2'
    _showAgentServicesAndChecks 8515

    _removeAgentService 8515 'berdssrv2'
    _showAgentServicesAndChecks 8515

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "'$beredissrv2Ip'", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "15s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Restored service { ID: \"berdssrv2\", Name: \"be-redis\" } and check { ID: \"service:berdssrv2\", Name: \"Service 'be-redis' check\" }\n"
}

function _showPassingAndCriticalChecks()
{
    printf "health/state/passing\n"
    curl --silent 'http://localhost:8511/v1/health/state/passing' | jq '.[] | select(.CheckID!="serfHealth")'

    printf "health/state/critical\n"
    curl --silent 'http://localhost:8511/v1/health/state/critical' | jq
}

function showNodeCheckServiceHealthInfo()
{
    printf "***** Showing nodes, check and service health info\n"

    printf "health/node/be5cli2\n"
    curl --silent 'http://localhost:8511/v1/health/node/be5cli2' | jq '.[] | select(.CheckID!="serfHealth")'
    printf "health/checks/be-redis (service name instead of ID)\n"
    curl --silent 'http://localhost:8511/v1/health/checks/be-redis' | jq
    printf "health/service/be-redis (service name instead of ID)\n"
    curl --silent 'http://localhost:8511/v1/health/service/be-redis' | jq
}

function showCheckStateHealthInfo()
{
    printf "***** Showing check state health info\n"

    _showPassingAndCriticalChecks

    printf "Stopping beredissrv2 and waiting before showing check status (look also at Web UIs)\n"
    docker stop beredissrv2
    sleep 15
    _showPassingAndCriticalChecks

    printf "Starting beredissrv2 and waiting before showing check status (look also at Web UIs)\n"
    docker start beredissrv2
    sleep 15
    _showPassingAndCriticalChecks
}

function queryDns()
{
    printf "***** Querying DNS\n"

    printf "catalog/nodes\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes' | jq
    printf "catalog/services\n"
    curl --silent 'http://localhost:8515/v1/catalog/services' | jq

    printf "\n\n\n\n\nAll be-redis services\n"
    dig @127.0.0.1 -p 8611 be-redis.service.consul
    
    printf "\n\n\n\n\nFilter services by tag\n"
    dig @127.0.0.1 -p 8611 official.be-redis.service.consul

    printf "\n\n\n\n\nStopping beredissrv1\n"
    docker stop beredissrv1 > /dev/null
    sleep 20
    printf "Detailed service info: DNS resolution is disabled\n"
    dig @127.0.0.1 -p 8611 official.be-redis.service.consul SRV

    printf "\n\n\n\n\nStarting beredissrv1\n"
    docker start beredissrv1 > /dev/null
    sleep 20
    printf "Detailed service info: DNS resolution is enabled\n"
    dig @127.0.0.1 -p 8611 official.be-redis.service.consul SRV
}

function manipulateKeyValueEntries()
{
    printf "***** Manipulating key value entries\n"

    printf "kv/?recurse\n"
    curl --silent 'http://localhost:8515/v1/kv/?recurse'

    printf "Putting kv/category/application/sampleKey with value ABC\n"
    echo "$(curl --silent -X PUT --data 'ABC' 'http://localhost:8515/v1/kv/category/application/sampleKey')"
    printf "Retrieving kv/category/application/sampleKey\n"
    curl --silent 'http://localhost:8515/v1/kv/category/application/sampleKey' | jq

    printf "\n\nDeleting kv/category/application/sampleKey\n"
    echo "$(curl --silent -X DELETE 'http://localhost:8515/v1/kv/category/application/sampleKey')"
    printf "Retrieving kv/category/application/sampleKey\n"
    curl --silent 'http://localhost:8515/v1/kv/category/application/sampleKey' | jq

    printf "\n\nPutting kv/category/application/retryInterval\n"
    echo "$(curl --silent -X PUT --data '5000' 'http://localhost:8515/v1/kv/category/application/retryInterval')"
    printf "Putting kv/category/application/dbHost\n"
    echo "$(curl --silent -X PUT --data 'ìù@gò' 'http://localhost:8515/v1/kv/category/application/dbHost')"
    printf "Deleting kv/category/application\n"
    echo "$(curl --silent -X DELETE 'http://localhost:8515/v1/kv/category/application')"

    printf "Retrieving all keys with decoded values (look also at Web UIs)\n"
    encodedkv=$(curl --silent 'http://localhost:8515/v1/kv/?recurse') && \
    decodedkv=$encodedkv && \
    while read encoded; do decoded=$(printf "$encoded" | base64 -di); decodedkv=${decodedkv//$encoded/$decoded}; done < <(printf $encodedkv | jq '.[] | .Value' | sed 's@"@@'g) && \
    printf $decodedkv | jq
}

function _showLeaderAndPeers()
{
    printf "status/leader\n"
    echo "$(curl --silent 'http://localhost:8515/v1/status/leader')"

    printf "status/peers\n"
    echo "$(curl --silent 'http://localhost:8515/v1/status/peers')"
}

function showStatusInfo()
{
    printf "***** Showing status info\n"

    _showLeaderAndPeers

    printf "Sending SIGINT to be2srv2 (look at the monitor window)\n"
    docker exec be2srv2 kill -INT 1
    sleep 15
    _showLeaderAndPeers

    printf "Turning be2srv2 back on (look at the monitor window)\n"
    docker start be2srv2
    sleep 15
    _showLeaderAndPeers
}