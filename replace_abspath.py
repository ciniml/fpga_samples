#!/usr/bin/env python3

import sys
import os
import re

with open(sys.argv[1], 'r') as f:
    for line in iter(f.readline, ''):
