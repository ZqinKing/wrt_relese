#!/usr/bin/env bash

set -e

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1
Build_Mod=$2

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
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

$BASE_PATH/update.sh "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH"

# Handle build cache
if [[ -d "$BASE_PATH/build_cache" ]]; then
    # 检查目录是否为空
    if [ -n "$(ls -A "$BASE_PATH/build_cache")" ]; then
        if [ -d "$BASE_PATH/build_cache/staging_dir" ]; then
            mkdir -p "$BASE_PATH/$BUILD_DIR/staging_dir/"
            rsync -a --delete "$BASE_PATH/build_cache/staging_dir/" "$BASE_PATH/$BUILD_DIR/staging_dir/"
        fi
        if [ -d "$BASE_PATH/build_cache/build_dir" ]; then
            mkdir -p "$BASE_PATH/$BUILD_DIR/build_dir/"
            rsync -a --delete "$BASE_PATH/build_cache/build_dir/" "$BASE_PATH/$BUILD_DIR/build_dir/"
        fi
        echo "user build caching"
    fi
    \rm -rf $BASE_PATH/build_cache/*
fi

\cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"

cd "$BASE_PATH/$BUILD_DIR"
make defconfig

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" \) -exec rm -f {} +
fi

make download -j$(nproc)
make -j$(nproc) || make -j1 V=s

FIRMWARE_DIR="$BASE_PATH/firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
\rm -f "$BASE_PATH/firmware/Packages.manifest" 2>/dev/null

# Clean up build cache
if [[ -d "$BASE_PATH/build_cache" ]]; then
    echo "copy build cache"
    make clean
    \rm -rf "$BASE_PATH/$BUILD_DIR/dl/"
    mkdir -p "$BASE_PATH/build_cache/staging_dir"
    rsync -a --delete "$BASE_PATH/$BUILD_DIR/staging_dir/" "$BASE_PATH/build_cache/staging_dir/"
    \rm -rf $BASE_PATH/$BUILD_DIR/staging_dir/*
    mkdir -p "$BASE_PATH/build_cache/build_dir"
    rsync -a --delete "$BASE_PATH/$BUILD_DIR/build_dir/" "$BASE_PATH/build_cache/build_dir/"
    \rm -rf $BASE_PATH/$BUILD_DIR/build_dir/*
fi
