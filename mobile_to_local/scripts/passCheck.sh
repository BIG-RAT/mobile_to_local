#!/bin/bash

local_pwd="$1"
uname=$(stat -f%Su /dev/console)

dscl . -authonly "$uname" "$local_pwd"
