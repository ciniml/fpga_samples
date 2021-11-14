#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)
for f in `find ./src -name "*.scala"`; do
    if ! head -n 1 $f | grep "SPDX-License-Identifier" > /dev/null; then
        echo -e "$(cat ${SCRIPT_DIR}/LICENSE.header)\n\n$(cat $f)" > $f
    fi
done