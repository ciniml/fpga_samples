#!/bin/bash

for a in `find eda -name "*.gprj"`; do 
    grep -e "/home(/[^/]+)+" $a
done