#!/bin/bash

if [ "$#" == '1' ]; then
  python run.py -a scale -w $1
elif [ "$#" == '2' ]; then
  python run.py -a scale --paramfile $1 -w $2
else
  echo -e "${RED}Usage: $0 [\$parameter_file] \$num_workers ${NC}"
  exit 1
fi
