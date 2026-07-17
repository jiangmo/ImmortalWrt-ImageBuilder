#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
source shell/switch_repository.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
IMAGEBUILDER_PROFILE="$PROFILE"
CUSTOM_BOARD_NAME=""
CUSTOM_KERNEL_PIPE=""
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
  # 下载 run 文件仓库
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
  # 添加架构优先级信息
  sed -i '1i\
  arch aarch64_generic 10\n\
  arch aarch64_cortex-a53 15' repositories.conf
fi


# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
echo "查看repositories.conf信息——————"
cat repositories.conf
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
      | grep "browser_download_url.*ipk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest ipk: $URL"
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
            CUSTOM_DTB="/home/build/immortalwrt/custom-dtb/rk3399-dg3399.dtb"
            IMAGEBUILDER_PROFILE="friendlyarm_nanopc-t4"
            CUSTOM_KERNEL_PIPE="kernel-bin | lzma | fit lzma $CUSTOM_DTB"
            ;;
        boocax)
            CUSTOM_BOARD_NAME="boocax"
            CUSTOM_DTB="/home/build/immortalwrt/custom-dtb/rk3399-boocax.dtb"
            IMAGEBUILDER_PROFILE="friendlyarm_nanopc-t4"
            CUSTOM_KERNEL_PIPE="kernel-bin | lzma | fit lzma $CUSTOM_DTB"
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

if [ -n "$CUSTOM_KERNEL_PIPE" ]; then
    make image PROFILE=$IMAGEBUILDER_PROFILE KERNEL="$CUSTOM_KERNEL_PIPE" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
else
    make image PROFILE=$IMAGEBUILDER_PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE
fi

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

rename_custom_rockchip_images

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
