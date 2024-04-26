#!/usr/bin/env bash

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

dev_mod=$1
clear=$2

if [[ ! -f $BASE_PATH/diffconfig.$dev_mod ]]; then
	echo "config not fond: diffconfig.$dev_mod"
	exit 0
fi

$BASE_PATH/update.sh

cd $BASE_PATH/immortalwrt-mt798x

if [[ $clear == "clear" ]]; then
	find ./ -name "*.ipk" | xargs \rm -f
fi

\cp -f $BASE_PATH/diffconfig.$dev_mod .config

make defconfig

if [[ $clear == "debug" ]]; then
    exit 0
fi

make download -j$(nproc)
if [[ $clear == "clear" ]]; then
	make V=s -j1
else
	make V=s -j$(nproc)
fi
