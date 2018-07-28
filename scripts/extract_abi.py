#!/usr/bin/env python

import os
import json

for file in os.listdir("../build/contracts"):
    if file.endswith(".json"):
        with open(file, 'r') as f:
            jsonObj = json.load(f)
            abiStr = json.dumps(jsonObj["abi"])
            abiStr = abiStr.replace('\n', '').replace('\r', '').replace(' ', '')
            print file


