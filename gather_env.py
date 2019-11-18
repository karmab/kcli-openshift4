import sys
import yaml

paramfile = sys.argv[1]

with open(paramfile) as entries:
    data = yaml.safe_load(entries)
    for key in data:
        if not isinstance(data[key], list) and not isinstance(data[key], dict):
            print("export %s=%s" % (key, data[key]))
