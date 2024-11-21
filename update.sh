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
    git reset --hard origin/$REPO_BRANCH
    git clean -f -d
    git pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
}

update_feeds() {
    # 删除注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"

    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    # 添加bpf.mk解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    # 更新 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
        "luci-app-openclash" "luci-app-mihomo"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2tcp" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed" "mihomo"
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
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-plugin tuic-client \
        chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev luci-app-passwall \
        alist luci-app-alist smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns adguardhome \
        luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash mihomo \
        luci-app-mihomo luci-app-homeproxy
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

remove_something_nss_kmod() {
    local ipq_target_path="$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk"
    if [ -f $ipq_target_path ]; then
        sed -i 's/kmod-qca-nss-drv-eogremgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-gre//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-pvxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-vxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-mirror//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tun6rd//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tunipip6//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-macsec//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-match//g' $ipq_target_path
    fi
}

remove_affinity_script() {
    local affinity_script_path="$BUILD_DIR/target/linux/qualcommax/ipq60xx/base-files/etc/init.d/set-irq-affinity"
    if [ -d "$(dirname "$affinity_script_path")" ]; then
        [ -f "$affinity_script_path" ] && \rm -f "$affinity_script_path"
    fi
}

fix_build_for_openssl() {
    local makefile="$BUILD_DIR/package/libs/openssl/Makefile"

    if [[ -f "$makefile" ]]; then
        if ! grep -qP "^CONFIG_OPENSSL_SSL3" "$makefile"; then
            sed -i '/^ifndef CONFIG_OPENSSL_SSL3/i CONFIG_OPENSSL_SSL3 := y' "$makefile"
        fi
    fi
}

update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        local hash=$(sha256sum "$makefile" | awk '{print $1}')
        if [[ "$hash" == "4a598084f928696e9f029a3de9abddfef0fc4aae53445f858b39792661acd350" ]]; then
            \cp -f "$BASE_PATH/patches/ath11k_fw.mk" "$makefile"
        fi
    fi
}

fix_mkpkg_format_invalid() {
    if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
        sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
    fi
    if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
        sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
    fi
    if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
        sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
    fi
    if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
        sed -i 's/PKG_VERSION:=0\.1\.26-3/PKG_VERSION:=0\.1\.26/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=3/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
    fi
    if [ -f $BUILD_DIR/feeds/small8/luci-app-passwall/Makefile ]; then
        sed -i 's/PKG_VERSION:=4\.78-4/PKG_VERSION:=4\.78/g' $BUILD_DIR/feeds/small8/luci-app-passwall/Makefile
        sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=4/g' $BUILD_DIR/feeds/small8/luci-app-passwall/Makefile
    fi
    if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
        sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
    fi
}

add_ax6600_led() {
    local target_dir="$BUILD_DIR/target/linux/qualcommax/ipq60xx/base-files"
    local initd_dir="$target_dir/etc/init.d"
    local sbin_dir="$target_dir/sbin"

    if [ -d "$(dirname "$target_dir")" ] && [ -d "$initd_dir" ]; then
        \cp -f "$BASE_PATH/patches/start_screen" "$initd_dir/start_screen"
        mkdir -p "$sbin_dir"
        \cp -f "$BASE_PATH/patches/ax6600_led" "$sbin_dir"
        \cp -f "$BASE_PATH/patches/cpuusage" "$sbin_dir"
    fi
}

chanage_cpuusage() {
    local luci_dir="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    if [ -f $luci_dir ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : \"top -n1 | awk \\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\'\"#g" $luci_dir
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' $luci_dir
    fi
}

tcping_support_ipv6() {
    local tcping_dir="$BUILD_DIR/feeds/small8/tcping/patches"
    local patch_file="$BASE_PATH/patches/0001-Support-ipv6.patch"

    if [ -d "$BUILD_DIR/feeds/small8/tcping" ] && [ -f "$patch_file" ]; then
        mkdir -p "$tcping_dir"
        \cp -f "$patch_file" "$tcping_dir/"
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
    remove_something_nss_kmod
    remove_affinity_script
    fix_build_for_openssl
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    chanage_cpuusage
    tcping_support_ipv6
    install_feeds
    add_ax6600_led
}

main "$@"
