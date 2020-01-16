!/bin/bash

docker ps -a|awk '{print $1}'|xargs docker rm
docker rmi $(docker images -f "dangling=true" -q)

