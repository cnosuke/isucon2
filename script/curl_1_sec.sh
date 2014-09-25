#!/bin/bash

while true
do
  # curl http://localhost/purge_all_cache > /dev/null 2>&1
  curl -X BAN http://localhost/ > /dev/null 2>&1
  usleep 820000 # 0.82s
done
