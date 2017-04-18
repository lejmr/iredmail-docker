#!/bin/bash

# Wait until mysql is started
while ! nc -z localhost 3306; do   
  sleep 1
done


