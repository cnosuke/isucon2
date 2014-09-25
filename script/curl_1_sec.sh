#!/bin/bash

while true
do
  curl http://127.0.0.1/purge_all_cache > /dev/null 2>&1
  usleep 820000 # 0.82s
done
