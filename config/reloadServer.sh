#!/bin/bash
sudo rsync -r --delete-excluded --force /home/ubuntu/node-temp/ /home/ubuntu/node-server
sudo rm -rf /home/ubuntu/node-temp 
cd /home/ubuntu/node-server
pm2 reload ecosystem.config.js
cd /home/ubuntu
pm2 save
