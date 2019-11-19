#!/bin/bash

if [ "$#" == '1' ]; then
  python run.py -a clean -f $1
else
  python run.py -a clean
fi
