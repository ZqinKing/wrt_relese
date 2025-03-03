#!/usr/bin/env bash

set -e
set -o errexit
set -o errtrace

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置trap捕获ERR信号
trap 'error_handler' ERR

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="24.x"
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
    mkdir -p $BUILD_DIR/tmp
    echo "1" >$BUILD_DIR/tmp/.build
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
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed" "mihomo" "geoview" "tailscale"
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

    # 临时放一下，清理脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
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
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall alist luci-app-alist smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns \
        adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash luci-app-homeproxy \
        luci-app-amlogic nikki luci-app-nikki tailscale luci-app-tailscale
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
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    if [ -d "$BUILD_DIR/feeds/small8/luci-theme-argon" ]; then
        find "$BUILD_DIR/feeds/small8/luci-theme-argon" -type f -name "cascade*" -exec sed -i 's/--bar-bg/--primary/g' {} \;
    fi

    install -Dm755 "$BASE_PATH/patches/99_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/99_set_argon_primary"

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

fix_miniupmpd() {
    # 从 miniupnpd 的 Makefile 中提取 PKG_HASH 的值
    local PKG_HASH=$(grep '^PKG_HASH:=' "$BUILD_DIR/feeds/packages/net/miniupnpd/Makefile" 2>/dev/null | cut -d '=' -f 2)

    # 检查 miniupnp 版本，并且补丁文件是否存在
    if [[ $PKG_HASH == "fbdd5501039730f04a8420ea2f8f54b7df63f9f04cde2dc67fa7371e80477bbe" && -f "$BASE_PATH/patches/400-fix_nft_miniupnp.patch" ]]; then
        # 使用 install 命令创建目录并复制补丁文件
        install -Dm644 "$BASE_PATH/patches/400-fix_nft_miniupnp.patch" "$BUILD_DIR/feeds/packages/net/miniupnpd/patches/400-fix_nft_miniupnp.patch"
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
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
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
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    if [ -f $ipq_target_path ]; then
        sed -i 's/kmod-qca-nss-drv-eogremgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-gre//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-map-t//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-match//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-mirror//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-pvxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tun6rd//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tunipip6//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-vxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-macsec//g' $ipq_target_path
    fi

    if [ -f $ipq_mk_path ]; then
        sed -i '/kmod-qca-nss-crypto/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-eogremgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-gre/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-map-t/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-match/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-mirror/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tun6rd/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tunipip6/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-macsec/d' $ipq_mk_path

        sed -i 's/cpufreq //g' $ipq_mk_path
    fi
}

update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
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
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"

    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        [ -f "$new_mk" ] && \rm -f "$new_mk"
        curl -L -o "$new_mk" https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile
        \mv -f "$new_mk" "$makefile"
    fi
}

fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}

add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"

    # 删除旧的目录（如果存在）
    rm -rf "$athena_led_dir" 2>/dev/null

    # 克隆最新的仓库
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git "$athena_led_dir"
    # 设置执行权限
    chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
    chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
}

chanage_cpuusage() {
    local luci_dir="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local imm_script1="$BUILD_DIR/package/base-files/files/sbin/cpuusage"

    if [ -f $luci_dir ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" $luci_dir
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' $luci_dir
    fi

    if [ -f "$imm_script1" ]; then
        rm -f "$imm_script1"
    fi

    install -Dm755 "$BASE_PATH/patches/cpuusage" "$BUILD_DIR/target/linux/qualcommax/base-files/sbin/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin/cpuusage"
}

update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ] && [ -f "$tcping_path" ]; then
        \rm -f "$tcping_path"
        curl -L -o "$tcping_path" https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile
    fi
}

set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存请求定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_check 任务
    sed -i '/wireguard_check/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_check 任务，每10分钟执行一次
        echo "*/10 * * * * /sbin/wireguard_check.sh" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

add_wg_chk() {
    local sbin_path="$BUILD_DIR/package/base-files/files/sbin"
    if [[ -d "$sbin_path" ]]; then
        install -Dm755 "$BASE_PATH/patches/wireguard_check.sh" "$sbin_path/wireguard_check.sh"
    fi
}

update_pw_ha_chk() {
    local new_path="$BASE_PATH/patches/haproxy_check.sh"
    local pw_share_dir="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall"
    local pw_ha_path="$pw_share_dir/haproxy_check.sh"
    local ha_lua_path="$pw_share_dir/haproxy.lua"
    local smartdns_lua_path="$pw_share_dir/helper_smartdns_add.lua"
    local rules_dir="$pw_share_dir/rules"

    # 修改 haproxy.lua 文件中的 rise 和 fall 参数
    [ -f "$ha_lua_path" ] && sed -i 's/rise 1 fall 3/rise 3 fall 2/g' "$ha_lua_path"

    # 删除 helper_smartdns_add.lua 文件中的特定行
    [ -f "$smartdns_lua_path" ] && sed -i '/force-qtype-SOA 65/d' "$smartdns_lua_path"

    # 从 chnlist 文件中删除特定的域名
    sed -i '/\.bing\./d' "$rules_dir/chnlist"
    sed -i '/microsoft/d' "$rules_dir/chnlist"
    sed -i '/msedge/d' "$rules_dir/chnlist"
    sed -i '/github/d' "$rules_dir/chnlist"
}

install_opkg_distfeeds() {
    # 只处理aarch64
    if ! grep -q "nss-packages" "$BUILD_DIR/feeds.conf.default"; then
        return
    fi
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        install -Dm755 "$BASE_PATH/patches/99-distfeeds.conf" "$distfeeds_conf"

        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}

update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}

fix_compile_vlmcsd() {
    local dir="$BUILD_DIR/feeds/packages/net/vlmcsd"
    local patch_src="$BASE_PATH/patches/001-fix_compile_with_ccache.patch"
    local patch_dest="$dir/patches"

    if [ -d "$dir" ]; then
        mkdir -p "$patch_dest"
        cp -f "$patch_src" "$patch_dest"
    fi
}

update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
        git clone "$repo_url" "$target_dir"
    fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

# 更新版本
update_package() {
    local dir="$BUILD_DIR/feeds/$1"
    local mk_path="$dir/Makefile"
    if [ -d "${mk_path%/*}" ] && [ -f "$mk_path" ]; then
        # 提取repo
        local PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*tar\.gz" $mk_path | awk -F"/" '{print $(NF - 2) "/" $(NF -1 )}')
        if [ -z $PKG_REPO ]; then
            return 1
        fi
        local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease|not)) | first | .tag_name")
        local PKG_HASH=$(curl -sL "https://codeload.github.com/$PKG_REPO/tar.gz/$PKG_VER" | sha256sum | cut -b -64)

        # 删除PKG_VER开头的v
        PKG_VER=${PKG_VER#v}

        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' $mk_path
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' $mk_path
    fi
}

update_lucky() {
    local mk_dir="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ -d "${mk_dir%/*}" ] && [ -f "$mk_dir" ]; then
        sed -i '/Build\/Prepare/ a\	[ -f $(TOPDIR)/../patches/lucky_Linux_$(LUCKY_ARCH).tar.gz ] && install -Dm644 $(TOPDIR)/../patches/lucky_Linux_$(LUCKY_ARCH).tar.gz $(PKG_BUILD_DIR)/$(PKG_NAME)_$(PKG_VERSION)_Linux_$(LUCKY_ARCH).tar.gz' "$mk_dir"
        sed -i '/wget/d' "$mk_dir"
    fi
}

# 添加系统升级时的备份信息
function add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/lucky/
EOF
    fi
}

# 更新启动顺序
function update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

function optimize_smartDNS() {
    local smartdns_custom="$BUILD_DIR/feeds/small8/smartdns/conf/custom.conf"
    local smartdns_patch="$BUILD_DIR/feeds/small8/smartdns/patches/010_change_start_order.patch"
    install -Dm644 "$BASE_PATH/patches/010_change_start_order.patch" "$smartdns_patch"

    # 检查配置文件所在的目录和文件是否存在
    if [ -d "${smartdns_custom%/*}" ] && [ -f "$smartdns_custom" ]; then
        # 优化配置选项：
        # serve-expired-ttl: 缓存有效期(单位：小时)，默认值影响DNS解析速度
        # serve-expired-reply-ttl: 过期回复TTL
        # max-reply-ip-num: 最大IP数
        # dualstack-ip-selection-threshold: IPv6优先的阈值
        # server: 配置上游DNS
        echo "优化SmartDNS配置"
        cat >"$smartdns_custom" <<'EOF'
serve-expired-ttl 7200
serve-expired-reply-ttl 5
max-reply-ip-num 3
dualstack-ip-selection-threshold 15
server 223.5.5.5 -bootstrap-dns
EOF
    fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
    fi
}

main() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    update_homeproxy
    fix_default_set
    fix_miniupmpd
    update_golang
    change_dnsmasq2full
    chk_fullconenat
    fix_mk_def_depends
    add_wifi_default_set
    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    fix_build_for_openssl
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    chanage_cpuusage
    update_tcping
    add_wg_chk
    add_ax6600_led
    set_custom_task
    update_pw_ha_chk
    install_opkg_distfeeds
    update_nss_pbuf_performance
    set_build_signature
    fix_compile_vlmcsd
    update_nss_diag
    update_menu_location
    fix_compile_coremark
    update_dnsmasq_conf
    # update_lucky
    add_backup_info_to_sysupgrade
    optimize_smartDNS
    update_mosdns_deconfig
    install_feeds
    update_package "small8/sing-box"
    update_script_priority
}

main "$@"
