#!/usr/bin/env python

import os
import json

path = '../build/contracts/'

dir_path = os.path.dirname(path)
for file in os.listdir(path):
    if file.endswith('.json'):
        with open(os.path.join(dir_path, file), 'r') as f:
            jsonObj = json.load(f)
            abiStr = json.dumps(jsonObj['abi'])
            abiStr = abiStr.replace('\n', '').replace('\r', '').replace(' ', '')
            
            filename = file.replace('.json', '') + '.abi'
            with open(os.path.join(dir_path, filename), 'w') as newFile:
                print "Dumping " + filename
                json.dump(json.loads(abiStr), newFile, sort_keys=True)
