#!/usr/bin/env bash

set -e

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR="$BASE_PATH/action_build"

echo $REPO_URL $REPO_BRANCH
git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR

mkdir -p "$BUILD_DIR/build_dir"
mkdir -p "$BUILD_DIR/staging_dir"