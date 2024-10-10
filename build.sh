#!/usr/bin/env bash

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1
Build_Mod=$2

if [[ ! -f $BASE_PATH/deconfig/$Dev.config ]]; then
    echo "config not fond"
    exit 0
fi

if [[ ! -f $BASE_PATH/compilecfg/$Dev.ini ]]; then
    echo "ini not fond"
    exit 0
fi

read_ini_by_key() {
    local key=$1
    cat $BASE_PATH/compilecfg/$Dev.ini | awk -F"=" '/^'$key'/ {print $2}'
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
if [[ -z $REPO_BRANCH ]]; then
    REPO_BRANCH="main"
fi

$BASE_PATH/update.sh $REPO_URL $REPO_BRANCH $BASE_PATH/$BUILD_DIR

\cp -f $BASE_PATH/deconfig/$Dev.config $BASE_PATH/$BUILD_DIR/.config

cd $BASE_PATH/$BUILD_DIR
make defconfig

if [[ $Build_Mod == "debug" ]]; then
	exit 0
fi

make download -j$(nproc)
make -j$(nproc) || make -j1 || make -j1 V=s
