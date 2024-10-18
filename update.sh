#!/usr/bin/env bash

set -e

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="23.x"
THEME_SET="argon"
#SSID_NAME="Newifi2_D1"

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
    git reset --hard origin/$REPO_BRANCH
    git clean -fd
    git checkout .
    git pull
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
    # sed -i 's#https://#git://#g' $BUILD_DIR/$FEEDS_CONF
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
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

install_feeds() {
    ./scripts/feeds update -i
    ./scripts/feeds install -f -ap packages
    ./scripts/feeds install -f -ap luci
    ./scripts/feeds install -f -ap routing
    ./scripts/feeds install -f -ap telephony
    if [[ -d ./feeds/nss_packages ]]; then
        ./scripts/feeds install -f -ap nss_packages
    fi
    if [[ -d ./feeds/sqm_scripts_nss ]]; then
        ./scripts/feeds install -f -ap sqm_scripts_nss
    fi 
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria naiveproxy \
        shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-plugin tuic-client chinadns-ng ipt2socks tcping \
        trojan-plus simple-obfs shadowsocksr-libev luci-app-passwall alist luci-app-alist smartdns luci-app-smartdns \
        v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm \
        luci-lib-taskd luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky
}

fix_default_set() {
    #修改默认主题
    sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
    #sed -i "s/\.ssid=.*/\.ssid=$SSID_NAME/g" $(find ./package/kernel/mac80211/ -type f -name "mac80211.sh")

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

main() {
    clone_repo
    clean_up
    reset_feeds_conf
    git pull
    update_feeds
    remove_unwanted_packages
    fix_default_set
    fix_miniupmpd
    update_golang
    change_dnsmasq2full
    chk_fullconenat
    fix_mk_def_depends
    install_feeds
}

main "$@"
