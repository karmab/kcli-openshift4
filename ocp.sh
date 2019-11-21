#!/bin/bash

if [ "$#" == '1' ]; then
  python run.py -a deploy -f $1
else
  python run.py -a deploy
fi
