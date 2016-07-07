#!/bin/bash

function destroyContainers()
{
    printf "***** Destroying containers\n"

    local filterBy=$1

    printf "List of all containers before destruction\n"
    docker -H tcp://0.0.0.0:2375 ps -a

    printf "Stopping and removing containers\n"
    local toBeDestroyed=$(docker -H tcp://0.0.0.0:2375 ps -a | tail -n +2 | grep $filterBy | awk '{ print $1 }')
    docker -H tcp://0.0.0.0:2375 stop $toBeDestroyed > /dev/null
    docker -H tcp://0.0.0.0:2375 rm $toBeDestroyed > /dev/null

    printf "List of all containers after destruction\n"
    docker -H tcp://0.0.0.0:2375 ps -a
}

function startRedis()
{
    printf "***** Starting Redis\n"

    docker -H tcp://0.0.0.0:2375 run --name beredissrv1 -d redis
    local beredissrv1Ip="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' beredissrv1)"
    printf "Started beredissrv1 with IP $beredissrv1Ip\n"

    docker -H tcp://0.0.0.0:2375 run --name beredissrv2 -d redis
    local beredissrv2Ip="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' beredissrv2)"
    printf "Started beredissrv2 with IP $beredissrv2Ip\n"

    docker -H tcp://0.0.0.0:2375 run --name feredissrv1 -d redis
    local feredissrv1Ip="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' feredissrv1)"
    printf "Started feredissrv1 with IP $feredissrv1Ip\n"

    docker -H tcp://0.0.0.0:2375 run --name feredissrv2 -d redis
    local feredissrv2Ip="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' feredissrv2)"
    printf "Started feredissrv2 with IP $feredissrv2Ip\n"    
}

function pushItemsToRedis()
{
    printf "***** Pushing items to Redis\n"

    docker -H tcp://0.0.0.0:2375 run -it --link beredissrv1:redis --rm redis redis-cli -h redis -p 6379 lpush myBeList1 BeL1First > /dev/null && \
    printf "Server beredissrv1 - Key myBeList1 items:\n" && \
    docker -H tcp://0.0.0.0:2375 run -it --link beredissrv1:redis --rm redis redis-cli -h redis -p 6379 lrange myBeList1 0 -1

    docker -H tcp://0.0.0.0:2375 run -it --link beredissrv2:redis --rm redis redis-cli -h redis -p 6379 lpush myBeList2 BeL2First > /dev/null && \
    printf "Server beredissrv2 - Key myBeList2 items:\n" && \
    docker -H tcp://0.0.0.0:2375 run -it --link beredissrv1:redis --rm redis redis-cli -h redis -p 6379 lrange myBeList2 0 -1

    docker -H tcp://0.0.0.0:2375 run -it --link feredissrv1:redis --rm redis redis-cli -h redis -p 6379 lpush myFeList1 FeL1First > /dev/null && \
    printf "Server feredissrv1 - Key myFeList1 items:\n" && \
    docker -H tcp://0.0.0.0:2375 run -it --link feredissrv1:redis --rm redis redis-cli -h redis -p 6379 lrange myFeList1 0 -1

    docker -H tcp://0.0.0.0:2375 run -it --link feredissrv2:redis --rm redis redis-cli -h redis -p 6379 lpush myFeList2 FeL2First > /dev/null && \
    printf "Server feredissrv2 - Key myFeList2 items:\n" && \
    docker -H tcp://0.0.0.0:2375 run -it --link feredissrv2:redis --rm redis redis-cli -h redis -p 6379 lrange myFeList2 0 -1
}

function startConsulBootstrapAgents()
{
    printf "***** Starting consul bootsrap agents\n"

    local ip=$1

    docker -H tcp://0.0.0.0:2375 run -d -p 8411:8400 -p 8511:8500 -p 8611:8600/udp --name be1srv1 -h be1srv1 gliderlabs/consul-server -bootstrap-expect 3 -dc "backenddc"
    printf "BE Web UI URL is http://$ip:8511/ui\n"
    
    docker -H tcp://0.0.0.0:2375 run -d -p 8421:8400 -p 8521:8500 -p 8621:8600/udp --name fe1srv1 -h fe1srv1 gliderlabs/consul-server -bootstrap-expect 3 -dc "frontenddc"
    printf "FE Web UI URL is http://$ip:8521/ui\n"
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

    local beJoinIp="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' be1srv1)"

    docker -H tcp://0.0.0.0:2375 run -d -p 8412:8400 -p 8512:8500 -p 8612:8600/udp --name be2srv2 -h be2srv2 gliderlabs/consul-server -dc "backenddc" -join $beJoinIp -join-wan $beJoinIp && printf "Started be2srv2\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8413:8400 -p 8513:8500 -p 8613:8600/udp --name be3srv3 -h be3srv3 gliderlabs/consul-server -dc "backenddc" -join $beJoinIp -join-wan $beJoinIp && printf "Started be3srv3\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8414:8400 -p 8514:8500 -p 8614:8600/udp --name be4cli1 -h be4cli1 gliderlabs/consul-agent -dc "backenddc" -join $beJoinIp && printf "Started be4cli1\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8415:8400 -p 8515:8500 -p 8615:8600/udp --name be5cli2 -h be5cli2 gliderlabs/consul-agent -dc "backenddc" -join $beJoinIp && printf "Started be5cli2\n"

    local feJoinIp="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' fe1srv1)"
    
    docker -H tcp://0.0.0.0:2375 run -d -p 8422:8400 -p 8522:8500 -p 8622:8600/udp --name fe2srv2 -h fe2srv2 gliderlabs/consul-server -dc "frontenddc" -join $feJoinIp -join-wan $feJoinIp && printf "Started fe2srv2\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8423:8400 -p 8523:8500 -p 8623:8600/udp --name fe3srv3 -h fe3srv3 gliderlabs/consul-server -dc "frontenddc" -join $feJoinIp -join-wan $feJoinIp && printf "Started fe3srv3\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8424:8400 -p 8524:8500 -p 8624:8600/udp --name fe4cli1 -h fe4cli1 gliderlabs/consul-agent -dc "frontenddc" -join $feJoinIp && printf "Started fe4cli1\n"
    docker -H tcp://0.0.0.0:2375 run -d -p 8425:8400 -p 8525:8500 -p 8625:8600/udp --name fe5cli2 -h fe5cli2 gliderlabs/consul-agent -dc "frontenddc" -join $feJoinIp && printf "Started fe5cli2\n"
}

function joinDatacenters()
{
    printf "***** Joining data centers\n"

    printf "Data centers before join (look also at Web UIs):\n$(curl --silent 'http://localhost:8515/v1/catalog/datacenters')"
    
    local beJoinIp="$(docker -H tcp://0.0.0.0:2375 inspect -f '{{.NetworkSettings.IPAddress}}' be1srv1)"
    docker -H tcp://0.0.0.0:2375 exec fe1srv1 /bin/consul join -wan $beJoinIp

    printf "Data centers after join (look also at Web UIs):\n$(curl --silent 'http://localhost:8515/v1/catalog/datacenters')"
}

function showCatalogInfo()
{
    printf "***** Showing catalog info\n"

    printf "catalog/nodes\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes' | jq

    printf "catalog/nodes?dc=frontenddc&near=fe4cli1\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes?dc=frontenddc&near=fe4cli1' | jq

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

function showAgentServicesAndChecks()
{
    local port=$1
    
    printf "agent/services\n"
    curl --silent "http://localhost:$port/v1/agent/services" | jq
    printf "agent/checks\n"
    curl --silent "http://localhost:$port/v1/agent/checks" | jq
}

function addAgentServiceAndCheckSeparately()
{
    printf "***** Adding agent service and check separately\n"

    curl --silent -X PUT --data '{ "ID": "berdssrv1", "Name": "be-redis", "Tags": [ "official", "nosql" ], "Address": "'$beredissrv1Ip'", "Port": 6379 }' 'http://localhost:8514/v1/agent/service/register'
    printf "Added service with ID berdssrv1 and name be-redis\n"
    showAgentServicesAndChecks 8514

    curl --silent -X PUT --data '{ "ServiceID": "berdssrv1", "ID": "beredissrv1UpAndRunning", "Name": "BE Redis 1 up and running", "TCP": "'$beredissrv1Ip':6379", "interval": "20s", "timeout": "2s" }' 'http://localhost:8514/v1/agent/check/register'
    printf "Added check for service berdssrv1 with ID beredissrv1UpAndRunning and name BE Redis 1 up and running\n"
    showAgentServicesAndChecks 8514
}

function addAgentServiceAndCheckAtOnce()
{
    printf "***** Adding agent service and check at once\n"

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "$beredissrv2Ip", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "15s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Added service with ID berdssrv2 and name be-redis\n"
    showAgentServicesAndChecks 8515

    curl --silent 'http://localhost:8515/v1/agent/service/deregister/berdssrv2'
    printf "Removed service with ID berdssrv2\n"
    showAgentServicesAndChecks 8515

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "'$beredissrv2Ip'", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "5s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Readded service with ID berdssrv2 and name be-redis\n"
    showAgentServicesAndChecks 8515

    curl --silent 'http://localhost:8515/v1/agent/check/deregister/service:berdssrv2'
    printf "Removed check with ID service:berdssrv2\n"
    showAgentServicesAndChecks 8515

    curl --silent 'http://localhost:8515/v1/agent/service/deregister/berdssrv2'
    printf "Removed service with ID berdssrv2\n"
    showAgentServicesAndChecks 8515

    curl --silent -X PUT --data '{ "ID": "berdssrv2", "Name": "be-redis", "Tags": [ "backup", "nosql" ], "Address": "'$beredissrv2Ip'", "Port": 6379, "Check": { "ID": "beredissrv2UpAndRunning", "Name": "BE Redis 2 up and running", "TCP": "'$beredissrv2Ip':6379", "interval": "15s", "timeout": "2s" } }' 'http://localhost:8515/v1/agent/service/register'
    printf "Restored service with ID berdssrv2 and name be-redis\n"
}

function showPassingAndCriticalChecks()
{
    printf "health/state/passing\n"
    curl --silent 'http://localhost:8511/v1/health/state/passing' | jq '.[] | select(.CheckID!="serfHealth")'

    printf "health/state/critical\n"
    curl --silent 'http://localhost:8511/v1/health/state/critical' | jq
}

function ShowHealthInfo()
{
    printf "***** Showing health info\n"

    printf "health/node/be5cli2\n"
    curl --silent 'http://localhost:8511/v1/health/node/be5cli2' | jq '.[] | select(.CheckID!="serfHealth")'
    printf "health/checks/be-redis\n"
    curl --silent 'http://localhost:8511/v1/health/checks/be-redis' | jq
    printf "health/service/be-redis\n"
    curl --silent 'http://localhost:8511/v1/health/service/be-redis' | jq

    showPassingAndCriticalChecks

    printf "Stopping beredissrv2 and waiting before showing check status (look also at Web UIs)\n"
    docker -H tcp://0.0.0.0:2375 stop beredissrv2
    sleep 10
    showPassingAndCriticalChecks

    printf "Starting beredissrv2 and waiting before showing check status (look also at Web UIs)\n"
    docker -H tcp://0.0.0.0:2375 start beredissrv2
    sleep 10
    showPassingAndCriticalChecks
}

function QueryDns()
{
    printf "***** Querying DNS\n"

    printf "catalog/nodes\n"
    curl --silent 'http://localhost:8515/v1/catalog/nodes' | jq
    printf "catalog/services\n"
    curl --silent 'http://localhost:8515/v1/catalog/services' | jq

    printf "All be-redis services: dig @127.0.0.1 -p 8611 be-redis.service.consul\n"
    dig @127.0.0.1 -p 8611 be-redis.service.consul
    
    printf "Filter services by tag: dig @127.0.0.1 -p 8611 official.be-redis.service.consul\n"
    dig @127.0.0.1 -p 8611 official.be-redis.service.consul

    printf "Detailed service info: dig @127.0.0.1 -p 8611 official.be-redis.service.consul SRV\n"
    dig @127.0.0.1 -p 8611 official.be-redis.service.consul SRV
}

function ManipulateKeyValueEntries()
{
    printf "***** Manipulating key value entries\n"

    printf "kv/?recurse\n"
    curl --silent 'http://localhost:8515/v1/kv/?recurse'

    printf "Putting and retrieving kv/category/application/sampleKey with value ABC\n"
    echo "$(curl --silent -X PUT --data 'ABC' 'http://localhost:8515/v1/kv/category/application/sampleKey')"
    curl --silent 'http://localhost:8515/v1/kv/category/application/sampleKey' | jq

    printf "Deleting and retrieving kv/category/application/sampleKey\n"
    curl --silent -X DELETE 'http://localhost:8515/v1/kv/category/application/sampleKey' | jq
    curl --silent 'http://localhost:8515/v1/kv/category/application/sampleKey' | jq

    printf "Putting and retrieving kv/category/application/retryInterval\n"
    echo "$(curl --silent -X PUT --data '5000' 'http://localhost:8515/v1/kv/category/application/retryInterval')"

    printf "Putting and retrieving kv/category/application/dbHost\n"
    echo "$(curl --silent -X PUT --data 'ìù@gò' 'http://localhost:8515/v1/kv/category/application/dbHost')"

    printf "Deleting kv/category/application\n"
    echo "$(curl --silent -X DELETE 'http://localhost:8515/v1/kv/category/application')"

    printf "Retrieving all keys with decoded values (look also at Web UIs)\n"
    encodedkv=$(curl --silent 'http://localhost:8515/v1/kv/?recurse') && decodedkv=$encodedkv && while read encoded; do decoded=$(printf $encoded | base64 -di); decodedkv=$(printf $decodedkv | sed "s@$encoded@$decoded@"g); done< <(printf $encodedkv | jq '.[] | .Value' | sed 's@"@@'g) && printf $decodedkv | jq
}

function showLeaderAndPeers()
{
    printf "status/leader\n"
    echo "$(curl --silent 'http://localhost:8515/v1/status/leader')"

    printf "status/peers\n"
    echo "$(curl --silent 'http://localhost:8515/v1/status/peers')"
}

function ShowStatusInfo()
{
    printf "***** Showing status info\n"

    showLeaderAndPeers

    printf "Sending SIGINT to be2srv2 (look at the monitor window)\n"
    docker -H tcp://0.0.0.0:2375 exec be2srv2 kill -INT 1
    showLeaderAndPeers

    printf "Turning be2srv2 back on (look at the monitor window)\n"
    docker -H tcp://0.0.0.0:2375 start be2srv2
    showLeaderAndPeers
}