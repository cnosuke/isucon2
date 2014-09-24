#!/bin/bash

while true
do
  curl http://ec2-54-64-183-81.ap-northeast-1.compute.amazonaws.com/purge_all_cache > /dev/null 2>&1
  sleep 1
done

