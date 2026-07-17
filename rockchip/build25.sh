#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方APK软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
IMAGEBUILDER_PROFILE="$PROFILE"
CUSTOM_BOARD_NAME=""
CUSTOM_BOARD_MODEL=""
CUSTOM_KERNEL_PIPE=""
CUSTOM_WIFI_PACKAGES=""
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/apk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 拷贝 run/arm64 下所有 run 文件和apk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  # 解压并拷贝apk到packages目录
  sh shell/apk-prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories信息——————"
cat repositories
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    # Download latest openclash Client
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*apk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest apk: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    # Download mihomo
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    mkdir -p files/usr/bin
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
fi

prepare_custom_rockchip_board() {
    case "$PROFILE" in
        dg3399)
            CUSTOM_BOARD_NAME="dg3399"
            CUSTOM_BOARD_MODEL="DG3399"
            CUSTOM_DTB="/home/build/immortalwrt/custom-dtb/rk3399-dg3399.dtb"
            IMAGEBUILDER_PROFILE="friendlyarm_nanopc-t4"
            CUSTOM_KERNEL_PIPE="kernel-bin | lzma | fit lzma $CUSTOM_DTB"
            CUSTOM_WIFI_PACKAGES="-brcmfmac-firmware-4356-sdio -brcmfmac-nvram-4356-sdio -brcmfmac-firmware-43430a0-sdio cypress-firmware-43430-sdio brcmfmac-nvram-43430-sdio"
            ;;
        boocax)
            CUSTOM_BOARD_NAME="boocax"
            CUSTOM_BOARD_MODEL="BOOCAX"
            CUSTOM_DTB="/home/build/immortalwrt/custom-dtb/rk3399-boocax.dtb"
            IMAGEBUILDER_PROFILE="friendlyarm_nanopc-t4"
            CUSTOM_KERNEL_PIPE="kernel-bin | lzma | fit lzma $CUSTOM_DTB"
            CUSTOM_WIFI_PACKAGES=""
            ;;
        *)
            echo "⚪️ 当前 profile 使用 ImageBuilder 原生配置: $PROFILE"
            return
            ;;
    esac

    echo "✅ 当前选择自定义 Rockchip 板子: $CUSTOM_BOARD_NAME"
    echo "✅ ImageBuilder 打包 profile 映射为: $IMAGEBUILDER_PROFILE"

    if [ ! -f "$CUSTOM_DTB" ]; then
        echo "❌ 未找到自定义设备树: $CUSTOM_DTB"
        exit 1
    fi

    echo "✅ 自定义设备树大小: $(stat -c%s "$CUSTOM_DTB") bytes"
    echo "✅ 自定义 KERNEL 打包管线: $CUSTOM_KERNEL_PIPE"
    if [ -n "$CUSTOM_WIFI_PACKAGES" ]; then
        echo "✅ 自定义板型 WiFi 软件包调整: $CUSTOM_WIFI_PACKAGES"
    fi
}

install_dg3399_wifi_firmware_links() {
    if [ "$CUSTOM_BOARD_NAME" != "dg3399" ]; then
        return
    fi

    mkdir -p /home/build/immortalwrt/files/lib/firmware/brcm
    ln -sf brcmfmac43430-sdio.AP6212.txt /home/build/immortalwrt/files/lib/firmware/brcm/brcmfmac43430-sdio.txt
    ln -sf brcmfmac43430-sdio.AP6212.txt "/home/build/immortalwrt/files/lib/firmware/brcm/brcmfmac43430-sdio.friendlyarm,nanopc-t4.txt"
    echo "✅ 已预置 dg3399 AP6212 WiFi NVRAM 兼容链接"
}

install_custom_board_model_override() {
    if [ -z "$CUSTOM_BOARD_NAME" ]; then
        return
    fi

    mkdir -p /home/build/immortalwrt/files/etc/init.d
    mkdir -p /home/build/immortalwrt/files/etc/rc.d

    cat > /home/build/immortalwrt/files/etc/init.d/custom-board-model << EOF
#!/bin/sh /etc/rc.common

START=05

start() {
    mkdir -p /tmp/sysinfo
    echo "$CUSTOM_BOARD_MODEL" > /tmp/sysinfo/model
    echo "$CUSTOM_BOARD_NAME" > /tmp/sysinfo/board_name
}
EOF

    chmod +x /home/build/immortalwrt/files/etc/init.d/custom-board-model
    ln -sf ../init.d/custom-board-model /home/build/immortalwrt/files/etc/rc.d/S05custom-board-model
    echo "✅ 已安装自定义板型显示覆盖: $CUSTOM_BOARD_MODEL ($CUSTOM_BOARD_NAME)"
}

rename_custom_rockchip_images() {
    if [ -z "$CUSTOM_BOARD_NAME" ]; then
        return
    fi

    IMAGE_DIR="/home/build/immortalwrt/bin/targets/rockchip/armv8"
    if [ ! -d "$IMAGE_DIR" ]; then
        return
    fi

    find "$IMAGE_DIR" -maxdepth 1 -type f -name "*nanopc-t4*" | while IFS= read -r image; do
        renamed=$(echo "$image" | sed "s/nanopc-t4/$CUSTOM_BOARD_NAME/g; s/friendlyarm_//g")
        echo "✅ 重命名镜像: $image -> $renamed"
        mv "$image" "$renamed"
    done
}

prepare_custom_rockchip_board
install_dg3399_wifi_firmware_links
install_custom_board_model_override

BUILD_PACKAGES="$PACKAGES $CUSTOM_WIFI_PACKAGES"
echo "✅ 最终软件包参数:"
echo "$BUILD_PACKAGES"

if [ -n "$CUSTOM_KERNEL_PIPE" ]; then
    make image PROFILE=$IMAGEBUILDER_PROFILE KERNEL="$CUSTOM_KERNEL_PIPE" PACKAGES="$BUILD_PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
else
    make image PROFILE=$IMAGEBUILDER_PROFILE PACKAGES="$BUILD_PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
fi

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

rename_custom_rockchip_images

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
