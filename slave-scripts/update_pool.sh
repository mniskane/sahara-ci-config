#!/bin/bash -e

for i in $(nodepool-client list | grep cilab | awk -F '|' '{ print $2 }')
do
   nodepool-client delete $i
   sleep 2
done
