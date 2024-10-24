#!/usr/bin/env bash

if [ -z "${1}" ]; then
    echo "image name not specified, aborting"
    exit 1
fi

sudo arkdep-build $1
sudo mv target/$1*.tar.zst /arkdep/cache/
sudo arkdep deploy cache $1
