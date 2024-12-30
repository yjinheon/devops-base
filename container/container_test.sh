#!/bin/bash

# if not exist, create a directory

if [ ! -d /tmp/myroot ]; then
  mkdir /tmp/myroot
fi

# check sh file

ldd /bin/sh

# copy ldd dependencies to /tmp/myroot
