#!/usr/bin/env bash

set -e

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="23.x"
THEME_SET="argon"
LAN_ADDR="192.168.1.1"

clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo $REPO_URL $REPO_BRANCH
        git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
    fi
}

clean_up() {
    cd $BUILD_DIR
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
}

reset_feeds_conf() {
    git checkout $REPO_BRANCH
    git reset --hard origin/$REPO_BRANCH
    git clean -fd
    git pull origin $REPO_BRANCH
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
    #if git status | grep -qE "$FEEDS_CONF$"; then
    #    git reset HEAD $FEEDS_CONF
    #    git checkout $FEEDS_CONF
    #fi
}

update_feeds() {
    sed -i '/^#/d' $BUILD_DIR/$FEEDS_CONF
    if ! grep -q "small-package" $BUILD_DIR/$FEEDS_CONF; then
        echo "src-git small8 https://github.com/kenzok8/small-package" >> $BUILD_DIR/$FEEDS_CONF
    fi
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
        "luci-app-openclash"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2tcp" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed"
    )
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq"
    )

    for pkg in "${luci_packages[@]}"; do
        \rm -rf ./feeds/luci/applications/$pkg
        \rm -rf ./feeds/luci/themes/$pkg
    done

    for pkg in "${packages_net[@]}"; do
        \rm -rf ./feeds/packages/net/$pkg
    done

    for pkg in "${small8_packages[@]}"; do
        \rm -rf ./feeds/small8/$pkg
    done

    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi
}

update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        git clone $GOLANG_REPO -b $GOLANG_BRANCH ./feeds/packages/lang/golang
    fi
}

install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria naiveproxy \
        shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-plugin tuic-client chinadns-ng ipt2socks tcping \
        trojan-plus simple-obfs shadowsocksr-libev luci-app-passwall alist luci-app-alist smartdns luci-app-smartdns \
        v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm \
        luci-lib-taskd luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash
}

install_feeds() {
    ./scripts/feeds update -i
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                install_small8
            else
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}

fix_default_set() {
    #修改默认主题
    sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

    if [[ -f ./package/emortal/autocore/files/tempinfo ]]; then
        if [[ -f $BASE_PATH/patches/tempinfo ]]; then
            \cp -f $BASE_PATH/patches/tempinfo ./package/emortal/autocore/files/tempinfo
        fi
    fi
}

fix_miniupmpd() {
    local PKG_HASH=$(awk -F"=" '/^PKG_HASH:/ {print $2}' ./feeds/packages/net/miniupnpd/Makefile)
    if [[ $PKG_HASH == "fbdd5501039730f04a8420ea2f8f54b7df63f9f04cde2dc67fa7371e80477bbe" ]]; then
        if [[ -f $BASE_PATH/patches/400-fix_nft_miniupnp.patch ]]; then
            if [[ ! -d ./feeds/packages/net/miniupnpd/patches ]]; then
                mkdir -p ./feeds/packages/net/miniupnpd/patches
            fi
            \cp -f $BASE_PATH/patches/400-fix_nft_miniupnp.patch ./feeds/packages/net/miniupnpd/patches/
        fi
    fi
}

change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

chk_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        \cp -rf $BASE_PATH/fullconenat/fullconenat-nft $BUILD_DIR/package/network/utils
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        \cp -rf $BASE_PATH/fullconenat/fullconenat $BUILD_DIR/package/network/utils
    fi
}

fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-basic-mbedtls/wpad-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

add_wifi_default_set() {
    if [ -d $BUILD_DIR/package/base-files/files/etc/uci-defaults ]; then
        \cp -f $BASE_PATH/patches/992_set-wifi-uci.sh $BUILD_DIR/package/base-files/files/etc/uci-defaults
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}

main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    fix_default_set
    fix_miniupmpd
    update_golang
    change_dnsmasq2full
    chk_fullconenat
    fix_mk_def_depends
    add_wifi_default_set
    update_default_lan_addr
    install_feeds
}

main "$@"
