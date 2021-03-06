#!/bin/bash
if [ $# -eq 0 ]
  then
    echo "No docker tag argument supplied. Use './build.sh <tag>'"
    exit 1
fi
docker build --build-arg VERSION=$1 --tag lbry/lbrynet:$1 .
docker push lbry/lbrynet:$1