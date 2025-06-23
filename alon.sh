# !/bin/base 
sed i "/src-git alon /d; 1 src-git alon https://github.com/xiealon/openwrt-packages;${CONFIG_REPO}" feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds uninstall $(grep Package ./feeds/alon.index | awk -F: ':' '(print $2)')
./scripts/feeds install -p alon -a
