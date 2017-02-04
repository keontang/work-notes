#!/bin/bash

set -o errexit

terminating_ns_array=`kubectl get namespaces | grep -o ".* Terminating" | awk '{print $1}'`

terminating_ns_array=`echo ${terminating_ns_array} | sed 's/\n/ /g'`

echo "Terminating namespaces: ${terminating_ns_array}"
echo ""

read -ra ns_array <<< "${terminating_ns_array}"

temp_json_dir=/tmp/terminating_ns

mkdir -p ${temp_json_dir}

trap 'rm -rf ${temp_json_dir}' EXIT

for (( i=0; i<${#ns_array[*]}; i++  )); do
    ns=${ns_array[$i]}
    kubectl get namespace ${ns} -o json > ${temp_json_dir}/${ns}.json
    sed -i '/^[ \t]*"kubernetes"$/d' ${temp_json_dir}/${ns}.json
    curl -s -H "Content-Type: application/json" -X PUT --data-binary @${temp_json_dir}/${ns}.json http://127.0.0.1:8080/api/v1/namespaces/${ns}/finalize > /dev/null
    echo "Namespace: ${ns} was finalized"
done
echo ""
