#!/usr/bin/env bash

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

if [[ ! -d $BASE_PATH/immortalwrt-mt798x ]]; then
	git clone https://github.com/padavanonly/immortalwrt-mt798x.git
fi

cd $BASE_PATH/immortalwrt-mt798x
if [[ -f $BASE_PATH/immortalwrt-mt798x/.config ]]; then
	\rm -f $BASE_PATH/immortalwrt-mt798x/.config
fi

status_cfg=$(git status | grep -cE "feeds.conf.default$")
if [[ $status_cfg -eq 1 ]]; then
    git reset HEAD feeds.conf.default
    git checkout feeds.conf.default
fi

\rm -rf ./tmp
\rm -rf ./logs/*

git pull

echo "src-git small8 https://github.com/kenzok8/small-package" >> feeds.conf.default

./scripts/feeds clean
./scripts/feeds update -a

\rm -rf ./feeds/luci/applications/{luci-app-passwall,luci-app-smartdns,luci-app-ddns-go,luci-app-rclone,luci-app-ssr-plus,luci-app-vssr}
\rm -rf ./feeds/luci/themes/luci-theme-argon
\rm -rf ./feeds/packages/net/{haproxy,xray-core,xray-plugin,mosdns,smartdns,ddns-go,dns2tcp,dns2socks}
\rm -rf ./feeds/small8/{ppp,firewall,dae,daed,daed-next,libnftnl,nftables,dnsmasq}

if [[ -d ./feeds/packages/lang/golang ]]; then
	\rm -rf ./feeds/packages/lang/golang
	git clone https://github.com/sbwml/packages_lang_golang -b 22.x ./feeds/packages/lang/golang
fi

./scripts/feeds update -i
./scripts/feeds install -f -ap packages
./scripts/feeds install -f -ap luci
./scripts/feeds install -f -ap routing
./scripts/feeds install -f -ap telephony

./scripts/feeds install -p small8 -f luci-app-adguardhome xray-core xray-plugin dns2tcp dns2socks haproxy \
luci-app-passwall luci-app-mosdns luci-app-smartdns luci-app-ddns-go luci-app-cloudflarespeedtest taskd \
luci-lib-xterm luci-lib-taskd luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-theme-argon
