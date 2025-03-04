#!/bin/bash

# hyperOS_port project

# For A-only and V/A-B (not tested) Devices

# Based on Android 13

# Test Base ROM: A-only Mi 10/PRO/Ultra (MIUI 14 Latset stockrom)

# Test Port ROM: Mi 14/Pro OS1.0.9-1.0.25 Mi 13/PRO OS1.0 23.11.09-23.11.10 DEV


build_user="Dino Pig"
build_host=$(hostname)

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$(pwd)/otatools/bin:$PATH

# Import functions
source functions.sh

shopt -s expand_aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    yellow "检测到Mac，设置alias" "macOS detected,setting alias"
    alias sed=gsed
    alias tr=gtr
    alias grep=ggrep
    alias du=gdu
    alias date=gdate
    #alias find=gfind
fi


check unzip aria2c 7z zip java zipalign python3 zstd bc xmlstarlet

# 移植的分区，可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
#super_list=$(grep "super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
pack_method=$(grep "pack_method" bin/port_config | cut -d '=' -f 2)
nfc_fix_type=$(grep "nfc_fix_type" bin/port_config |cut -d '=' -f 2)
if [[ ${repackext4} == true ]]; then
    pack_type=EXT
fi


# 检查为本地包还是链接
if [ ! -f "${baserom}" ] && [ "$(echo $baserom |grep http)" != "" ];then
    blue "底包为一个链接，正在尝试下载" "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${baserom}
    baserom=$(basename ${baserom} | sed 's/\?t.*//')
    if [ ! -f "${baserom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${baserom}" ];then
    green "底包: ${baserom}" "BASEROM: ${baserom}"
else
    error "底包参数错误" "BASEROM: Invalid parameter"
    exit
fi

if [ ! -f "${portrom}" ] && [ "$(echo ${portrom} |grep http)" != "" ];then
    blue "移植包为一个链接，正在尝试下载"  "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${portrom}
    portrom=$(basename ${portrom} | sed 's/\?t.*//')
    if [ ! -f "${portrom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${portrom}" ];then
    green "移植包: ${portrom}" "PORTROM: ${portrom}"
else
    error "移植包参数错误" "PORTROM: Invalid parameter"
    exit
fi

if [ "$(echo $baserom |grep _multi_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 3)
elif [ "$(echo $baserom |grep miui_)" != "" ] || [ "$(echo $baserom |grep xiaomi.eu_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="YourDevice"
fi

blue "正在检测ROM底包" "Validating BASEROM.."
if unzip -l ${baserom} | grep -q "payload.bin"; then
    baserom_type="payload"
    green "检测到payload.bin文件" "Found payload.bin file"
    super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
elif unzip -l ${baserom} | grep -q "br$";then
    baserom_type="br"
    green "检测到broli文件" "Found broli file"
elif unzip -l ${baserom} | grep -q "images/super.img*"; then
    green "检测到super.img.*文件" "Found super.img.* files"
    is_base_rom_eu=true
else
    error "底包中未发现payload.bin以及br文件，请使用MIUI官方包后重试" "payload.bin/new.br not found, please use HyperOS official OTA zip package."
    exit
fi

blue "开始检测ROM移植包" "Validating PORTROM.."
case "${portrom}" in
    *.zip)
        if unzip -l "${portrom}" | grep -q "payload.bin"; then
            green "检测到payload.bin文件" "Found payload.bin file"
        elif [[ "${portrom}" == *"xiaomi.eu"* ]] && (unzip -l ${baserom} | grep -q "images/super.img*") ; then
            green "检测到super.img.*文件" "Found super.img.* files"
    is_eu_rom=true
else
            error "目标移植包不是有效的ZIP文件，请检查文件格式。" "The target port package is not a valid ZIP file, please check the file format."
            exit
        fi
        ;;
    *.tgz)
        # FIXME: Checking if the .tgz contains super.img is very time-consuming, so just skip it here for now.
        green "跳过检查tgz" "Skip validating tgz file"
        portrom_type="fastboot"
        ;;
    *)
        error "目标移植包不是有效的ZIP或TGZ文件，请检查文件格式。" "The target port package is not a valid ZIP or TGZ file, please check the file format."
        ;;
esac

green "ROM初步检测通过" "ROM validation passed."

if [[ "$portrom" =~ SHENNONG|HOUJI ]]; then
    is_shennong_houji_port=true
else
    is_shennong_houji_port=false
fi

blue "正在清理文件" "Cleaning up.."
for i in ${port_partition};do
    [ -d ./${i} ] && rm -rf ./${i}
done
sudo rm -rf app
sudo rm -rf tmp
sudo rm -rf config
sudo rm -rf build/baserom/
sudo rm -rf build/portrom/
find . -type d -name 'hyperos_*' |xargs rm -rf

green "文件清理完毕" "Files cleaned up."
mkdir -p build/baserom/images/

mkdir -p build/portrom/images/


# 提取分区
if [[ ${baserom_type} == 'payload' ]];then
    blue "正在提取底包 [payload.bin]" "Extracting files from BASEROM [payload.bin]"
    payload-dumper --out build/baserom/images/ $baserom
    green "底包 [payload.bin] 提取完毕" "[payload.bin] extracted."
elif [[ ${baserom_type} == 'br' ]];then
    blue "正在提取底包 [new.dat.br]" "Extracting files from BASEROM [*.new.dat.br]"
    unzip ${baserom} -d build/baserom  > /dev/null 2>&1 || error "解压底包 [new.dat.br]时出错" "Extracting [new.dat.br] error"
    green "底包 [new.dat.br] 提取完毕" "[new.dat.br] extracted."
elif [[ ${is_base_rom_eu} == true ]];then
    blue "正在提取底包 [super.img]" "Extracting files from BASETROM [super.img]"
    unzip ${baserom} 'images/*' -d build/baserom >  /dev/null 2>&1 ||error "解压移植包 [super.img] 时出错"  "Extracting [super.img] error"
    blue "合并super.img* 到super.img" "Merging super.img.* into super.img"
    simg2img build/baserom/images/super.img.* build/baserom/images/super.img
    rm -rf build/baserom/images/super.img.*
    mv build/baserom/images/super.img build/baserom/super.img
    green "底包 [super.img] 提取完毕" "[super.img] extracted."
    mv build/baserom/images/boot.img build/baserom/
    mkdir -p build/baserom/firmware-update
    mv build/baserom/images/* build/baserom/firmware-update
    if [[ -f build/baserom/firmware-update/cust.img.0 ]];then
        simg2img build/baserom/firmware-update/cust.img.* build/baserom/firmware-update/cust.img
        rm -rf build/baserom/firmware-update/cust.img.*
    fi
fi

if [[ ${is_eu_rom} == true ]];then
    blue "正在提取移植包 [super.img]" "Extracting files from PORTROM [super.img]"
    unzip ${portrom} 'images/super.img.*' -d build/portrom >  /dev/null 2>&1 ||error "解压移植包 [super.img] 时出错"  "Extracting [super.img] error"
    blue "合并super.img* 到super.img" "Merging super.img.* into super.img"
    simg2img build/portrom/images/super.img.* build/portrom/images/super.img
    rm -rf build/portrom/images/super.img.*
    mv build/portrom/images/super.img build/portrom/super.img
    green "移植包 [super.img] 提取完毕" "[super.img] extracted."
elif [[ ${portrom_type} == "fastboot" ]];then
    blue "正在提取移植包 [super.img]" "Extracting files from PORTROM [super.img]"
    mkdir -p tmp/image
    tar -xzf ${portrom} -C tmp/image  ||error "解压移植包 [super.img] 时出错"  "Extracting [super.img] error"
    superimg=$(find tmp -type f -name "super.img")
    mv ${superimg} build/portrom/images/super.img.sparse
    simg2img build/portrom/images/super.img.sparse build/portrom/super.img
    rm -rf build/portrom/images/super.img.sparse
    green "移植包 [super.img] 提取完毕" "[super.img] extracted."
else
    blue "正在提取移植包 [payload.bin]" "Extracting files from PORTROM [payload.bin]"
    payload-dumper --partitions system,product,system_ext,mi_ext --out build/portrom/images/ $portrom
    green "移植包 [payload.bin] 提取完毕" "[payload.bin] extracted."
fi

if [[ ${is_base_rom_eu} == true ]];then
    blue "开始分解底包 [super.img]" "Unpacking BASEROM [super.img]"
    super_list=$(python3 bin/lpunpack.py --info build/baserom/super.img | grep "super:" | awk '{ print $5 }')
    for i in ${super_list}; do
        if [[ $i == *_a ]];then
            i=${i%_a}
            python3 bin/lpunpack.py -p ${i}_a build/baserom/super.img build/baserom/images >/dev/null 2>&1
            mv build/baserom/images/${i}_a.img build/baserom/images/${i}.img 
        else
            python3 bin/lpunpack.py -p ${i} build/baserom/super.img build/baserom/images >/dev/null 2>&1
        fi
    done
    super_list=$(echo $super_list | sed 's/_a//g')

elif [[ ${baserom_type} == 'br' ]];then
    super_list=$(cat build/baserom/dynamic_partitions_op_list | grep "add " | awk '{ print $2 }')
    blue "开始分解底包 [new.dat.br]" "Unpacking BASEROM[new.dat.br]"
        for i in ${super_list}; do 
            ${tools_dir}/brotli -d build/baserom/$i.new.dat.br >/dev/null 2>&1
            sudo python3 ${tools_dir}/sdat2img.py build/baserom/$i.transfer.list build/baserom/$i.new.dat build/baserom/images/$i.img >/dev/null 2>&1
            rm -rf build/baserom/$i.new.dat* build/baserom/$i.transfer.list build/baserom/$i.patch.*
        done
fi

source_img_type=$($tools_dir/gettype -i build/baserom/images/system.img)

if [[ $source_img_type == "erofs" ]] && [[ $repackext4 != true ]];then
    pack_type="EROFS"
else
    pack_type="EXT"
fi

for part in system system_dlkm system_ext product product_dlkm mi_ext ;do
    extract_partition build/baserom/images/${part}.img build/baserom/images    
done

# Move those to portrom folder. We need to pack those imgs into final port rom
for image in vendor odm vendor_dlkm odm_dlkm;do
    if [ -f build/baserom/images/${image}.img ];then
        mv -f build/baserom/images/${image}.img build/portrom/images/${image}.img

        # Extracting vendor at first, we need to determine which super parts to pack from Baserom fstab. 
        extract_partition build/portrom/images/${image}.img build/portrom/images/

    fi
done

# Extract the partitions list that need to pack into the super.img
super_list=$(sed '/^#/d;/^\//d;/overlay/d;/^$/d' build/portrom/images/vendor/etc/fstab.qcom \
                | awk '{ print $1}' | sort | uniq)

# 分解镜像
green "开始提取逻辑分区镜像" "Starting extract portrom partition from img"
for part in ${super_list};do
# Skip already extraced parts from BASEROM
    if [[ ! -d build/portrom/images/${part} ]]; then
        if [[ ${is_eu_rom} == true ]];then
            blue "PORTROM super.img 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM super.img"
            blue "lpunpack.py PORTROM super.img ${part}_a"
            python3 bin/lpunpack.py -p ${part}_a build/portrom/super.img build/portrom/images 
            mv build/portrom/images/${part}_a.img build/portrom/images/${part}.img
        elif [[ ${portrom_type} == "fastboot" ]];then
            blue "PORTROM super.img 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM super.img"
            blue "lpunpack.py PORTROM super.img ${part}_a"
            python3 bin/lpunpack.py -p ${part}_a build/portrom/super.img build/portrom/images 
            mv build/portrom/images/${part}_a.img build/portrom/images/${part}.img
        fi
    extract_partition "${work_dir}/build/portrom/images/${part}.img" "${work_dir}/build/portrom/images/"
    else
        yellow "跳过从PORTORM提取分区[${part}]" "Skip extracting [${part}] from PORTROM"
    fi
done
rm -rf config

blue "正在获取ROM参数" "Fetching ROM build prop."

# 安卓版本
base_android_version=$(< build/baserom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.incremental" |awk 'NR==1' |cut -d '=' -f 2)

#HyperOS版本号获取
port_mios_version_incremental=$(< build/portrom/images/mi_ext/etc/build.prop grep "ro.mi.os.version.incremental" | awk 'NR==1' | cut -d '=' -f 2)
#替换机型代号,比如小米10：UNBCNXM -> UJBCNXM

port_device_code=$(echo $port_mios_version_incremental | cut -d "." -f 5)

if [[ $port_android_version == "14" ]];then
    base_device_code=U$(echo $base_rom_version | cut -d "." -f 5 | cut -c 2-)
elif [[ $port_android_version == "15" ]];then
    base_device_code=V$(echo $base_rom_version | cut -d "." -f 5 | cut -c 2-)
fi
if [[ $port_mios_version_incremental == *DEV* ]];then
    yellow "检测到开发板，跳过修改版本代码" "Dev deteced,skip replacing codename"
    port_rom_version="$(echo $port_mios_version_incremental)"
else
    port_rom_version=$(echo $port_mios_version_incremental | sed "s/$port_device_code/$base_device_code/")
fi
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]" "ROM Version: BASEROM: [${base_rom_version}], PORTROM: [${port_rom_version}] "

# 代号
#base_rom_code=$(< build/portrom/images/vendor/build.prop grep "ro.product.vendor.device" |awk 'NR==1' |cut -d '=' -f 2)
base_rom_code=$(basename build/baserom/images/product/etc/device_features/*.xml .xml)
port_rom_code=$(< build/portrom/images/product/etc/build.prop grep "ro.product.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]" "Device Code: BASEROM: [${base_rom_code}], PORTROM: [${port_rom_code}]"

port_release_codename=$(< build/portrom/images/system/system/build.prop grep "ro.build.version.release_or_codename" | awk 'NR=1' | cut -d '=' -f 2)
if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi

baseAospFrameworkResOverlay=$(find build/baserom/images/product -type f -name "AospFrameworkResOverlay.apk")
portAospFrameworkResOverlay=$(find build/portrom/images/product -type f -name "AospFrameworkResOverlay.apk")
if [ -f "${baseAospFrameworkResOverlay}" ] && [ -f "${portAospFrameworkResOverlay}" ];then
    blue "正在替换 [AospFrameworkResOverlay.apk]" "Replacing [AospFrameworkResOverlay.apk]" 
    cp -rf ${baseAospFrameworkResOverlay} ${portAospFrameworkResOverlay}
fi


baseMiuiFrameworkResOverlay=$(find build/baserom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
portMiuiFrameworkResOverlay=$(find build/portrom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
if [ -f "${baseMiuiFrameworkResOverlay}" ] && [ -f "${portMiuiFrameworkResOverlay}" ];then
    blue "正在替换 [MiuiFrameworkResOverlay.apk]" "Replacing [MiuiFrameworkResOverlay.apk]" 
    cp -rf ${baseMiuiFrameworkResOverlay} ${portMiuiFrameworkResOverlay}
fi

baseAospWifiResOverlay=$(find build/baserom/images/product -type f -name "AospWifiResOverlay.apk")
portAospWifiResOverlay=$(find build/portrom/images/product -type f -name "AospWifiResOverlay.apk")
if [ -f ${baseAospWifiResOverlay} ] && [ -f ${portAospWifiResOverlay} ];then
    blue "正在替换 [AospWifiResOverlay.apk]"
    cp -rf ${baseAospWifiResOverlay} ${portAospWifiResOverlay}
fi

baseDevicesAndroidOverlay=$(find build/baserom/images/product -type f -name "DevicesAndroidOverlay.apk")
portDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [ -f "${baseDevicesAndroidOverlay}" ] && [ -f "${portDevicesAndroidOverlay}" ];then
    blue "正在替换 [DevicesAndroidOverlay.apk]" "Replacing [DevicesAndroidOverlay.apk]"
    cp -rf ${baseDevicesAndroidOverlay} ${portDevicesAndroidOverlay}
fi

baseDevicesOverlay=$(find build/baserom/images/product -type f -name "DevicesOverlay.apk")
portDevicesOverlay=$(find build/portrom/images/product -type f -name "DevicesOverlay.apk")
if [ -f "${baseDevicesOverlay}" ] && [ -f "${portDevicesOverlay}" ];then
    blue "正在替换 [DevicesOverlay.apk]" "Replacing [DevicesOverlay.apk]"
    cp -rf ${baseDevicesOverlay} ${portDevicesOverlay}
fi

baseSettingsRroDeviceHideStatusBarOverlay=$(find build/baserom/images/product -type f -name "SettingsRroDeviceHideStatusBarOverlay.apk")
portSettingsRroDeviceHideStatusBarOverlay=$(find build/portrom/images/product -type f -name "SettingsRroDeviceHideStatusBarOverlay.apk")
if [ -f "${baseSettingsRroDeviceHideStatusBarOverlay}" ] && [ -f "${portSettingsRroDeviceHideStatusBarOverlay}" ];then
    blue "正在替换 [SettingsRroDeviceHideStatusBarOverlay.apk]" "Replacing [SettingsRroDeviceHideStatusBarOverlay.apk]"
    cp -rf ${baseSettingsRroDeviceHideStatusBarOverlay} ${portSettingsRroDeviceHideStatusBarOverlay}
fi

baseMiuiBiometricResOverlay=$(find build/baserom/images/product -type f -name "MiuiBiometricResOverlay.apk")
portMiuiBiometricResOverlay=$(find build/portrom/images/product -type f -name "MiuiBiometricResOverlay.apk")
if [ -f "${baseMiuiBiometricResOverlay}" ] && [ -f "${portMiuiBiometricResOverlay}" ];then
    blue "正在替换 [MiuiBiometricResOverlay.apk]" "Replacing [MiuiBiometricResOverlay.apk]"
    cp -rf ${baseMiuiBiometricResOverlay} ${portMiuiBiometricResOverlay}
fi

# displayconfig id
rm -rf build/portrom/images/product/etc/displayconfig/display_id*.xml
cp -rf build/baserom/images/product/etc/displayconfig/display_id*.xml build/portrom/images/product/etc/displayconfig/


# device_features
blue "Copying device_features"   
rm -rf build/portrom/images/product/etc/device_features/*
cp -rf build/baserom/images/product/etc/device_features/* build/portrom/images/product/etc/device_features/

#device_info
if [[ ${is_eu_rom} == "true" ]];then
    cp -rf build/baserom/images/product/etc/device_info.json build/portrom/images/product/etc/device_info.json
fi
#baseMiSound=$(find build/baserom/images/product -type d -name "MiSound")
#portMiSound=$(find build/portrom/images/product -type d -name "MiSound")
#if [ -d "${baseMiSound}" ] && [ -d "${portMiSound}" ];then
#   blue "正在替换 MiSound" "Replacing stock MiSound"
#   rm -rf ./${portMiSound}/*
#   cp -rf ./${baseMiSound}/* ${portMiSound}/
#fi

# 人脸
baseMiuiBiometric=$(find build/baserom/images/product/app -type d -name "*Biometric*")
portMiuiBiometric=$(find build/portrom/images/product/app -type d -name "*Biometric*")
if [ -d "${baseMiuiBiometric}" ] && [ -d "${portMiuiBiometric}" ];then
    yellow "查找MiuiBiometric" "Searching and Replacing MiuiBiometric.."
    rm -rf ./${portMiuiBiometric}/*
    cp -rf ./${baseMiuiBiometric}/* ${portMiuiBiometric}/
else
    if [ -d "${baseMiuiBiometric}" ] && [ ! -d "${portMiuiBiometric}" ];then
        blue "未找到MiuiBiometric，替换为原包" "MiuiBiometric is missing, copying from base..."
        cp -rf ${baseMiuiBiometric} build/portrom/images/product/app/
    fi
fi

# 修复AOD问题
targetDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [[ -f "${targetDevicesAndroidOverlay}" ]]; then
    mkdir tmp/  
    filename=$(basename $targetDevicesAndroidOverlay)
    yellow "修复息屏和屏下指纹问题" "Fixing AOD issue: $filename ..."
    targetDir=$(echo "$filename" | sed 's/\..*$//')
    bin/apktool/apktool d $targetDevicesAndroidOverlay -o tmp/$targetDir -f > /dev/null 2>&1
    search_pattern="com\.miui\.aod\/com\.miui\.aod\.doze\.DozeService"
    replacement_pattern="com\.android\.systemui\/com\.android\.systemui\.doze\.DozeService"
    for xml in $(find tmp/$targetDir -type f -name "*.xml");do
        sed -i "s/$search_pattern/$replacement_pattern/g" $xml
    done
    bin/apktool/apktool b tmp/$targetDir -o tmp/$filename > /dev/null 2>&1 || error "apktool 打包失败" "apktool mod failed"
    cp -rf tmp/$filename $targetDevicesAndroidOverlay
    rm -rf tmp
fi

# Fix boot up frame drop issue. 
targetAospFrameworkResOverlay=$(find build/portrom/images/product -type f -name "AospFrameworkResOverlay.apk")

if [[ -f "${targetAospFrameworkResOverlay}" ]]; then
    
    if [[ ! -d tmp ]]; then
     mkdir tmp
    fi
    filename=$(basename $targetAospFrameworkResOverlay)
    yellow "Change defaultPeakRefreshRate: $filename ..."
    targetDir=$(echo "$filename" | sed 's/\..*$//')
    bin/apktool/apktool d $targetAospFrameworkResOverlay -o tmp/$targetDir -f > /dev/null 2>&1

    for xml in $(find tmp/$targetDir -type f -name "integers.xml");do
        # magic: Change DefaultPeakRefrshRate to 60 
        xmlstarlet ed -L -u "//integer[@name='config_defaultPeakRefreshRate']/text()" -v 60 $xml
    done
    if [[ $port_android_version == "15" ]]; then
        blue "Fix VanillaIceCream brightness" 
        for xml in $(find tmp/$targetDir -type f -name "*.xml");do
            sed -i "s/config_screenBrightnessDim\"/config_screenBrightnessDim_hyper\"/g" $xml
            sed -i "s/config_screenBrightnessSettingDefault\"/config_screenBrightnessSettingDefault_hyper\"/g" $xml
            sed -i "s/config_screenBrightnessSettingMaximum\"/config_screenBrightnessSettingMaximum_hyper\"/g" $xml
            sed -i "s/config_screenBrightnessSettingMinimum\"/config_screenBrightnessSettingMinimum_hyper\"/g" $xml 
        done 
    fi
    bin/apktool/apktool b tmp/$targetDir -o tmp/$filename > /dev/null 2>&1 || error "apktool 打包失败" "apktool mod failed"
    cp -rf tmp/$filename $targetAospFrameworkResOverlay
fi

sourceMiuiFrameworkTelephonyResOverlay=$(find build/baserom/images/product -type f -name "MiuiFrameworkTelephonyResOverlay.apk")
targetMiuiFrameworkTelephonyResOverlay=$(find build/portrom/images/product -type f -name "MiuiFrameworkTelephonyResOverlay.apk")
if [ -f "${sourceMiuiFrameworkTelephonyResOverlay}" ] && [ -f "${targetMiuiFrameworkTelephonyResOverlay}" ];then
    cp -rfv $sourceMiuiFrameworkTelephonyResOverlay $targetMiuiFrameworkTelephonyResOverlay
elif [ -f "${sourceMiuiFrameworkTelephonyResOverlay}" ] && [ ! -f "${targetMiuiFrameworkTelephonyResOverlay}" ];then
    cp -rfv $sourceMiuiFrameworkTelephonyResOverlay build/portrom/images/product/overlay/
elif [ ! -f "{$sourceMiuiFrameworkTelephonyResOverlay}" ] && [ -f "${targetMiuiFrameworkTelephonyResOverlay}" ];then
    rm -rfv $targetMiuiFrameworkTelephonyResOverlay
fi

#其他机型可能没有default.prop
for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
base_vndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
port_vndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${port_vndk}" ]; then
    yellow "apex不存在，从原包复制" "target apex is missing, copying from baserom"
    cp -rf "${base_vndk}" "build/portrom/images/system_ext/apex/"
fi

if [ $(grep -c "sm8250" "build/portrom/images/vendor/build.prop") -ne 0 ]; then
    ## Fix the drop frame issus
    echo "ro.surface_flinger.enable_frame_rate_override=false" >> build/portrom/images/vendor/build.prop
    echo "ro.vendor.display.mode_change_optimize.enable=true" >> build/portrom/images/vendor/build.prop
   if [[ $port_android_version == "15" ]];then
          {
            echo " ro.miui.affinity.sfui=4-7"
            echo "ro.miui.affinity.sfre=4-7" 
            echo "ro.miui.affinity.sfuireset=4-7" 
            echo "persist.sys.miui_animator_sched.bigcores=4-7"
            echo "persist.sys.miui_animator_sched.big_prime_cores=4-7"
            echo "persist.vendor.display.miui.composer_boost=4-7"
        }  >> build/portrom/images/product/etc/build.prop
	
   else
    sed -i "s/persist.sys.miui_animator_sched.bigcores=.*/persist.sys.miui_animator_sched.bigcores=4-6/" build/portrom/images/product/etc/build.prop
    sed -i "s/persist.sys.miui_animator_sched.big_prime_cores=.*/persist.sys.miui_animator_sched.big_prime_cores=4-7/" build/portrom/images/product/etc/build.prop

    {
        echo "persist.sys.miui.sf_cores=4-7"
        echo "persist.sys.minfree_def=73728,92160,110592,154832,482560,579072" 
        echo "persist.sys.minfree_6g=73728,92160,110592,258048,663552,903168" 
        echo "persist.sys.minfree_8g=73728,92160,110592,387072,1105920,1451520"
        echo "persist.vendor.display.miui.composer_boost=4-7"
    }  >> build/portrom/images/product/etc/build.prop


    fi
fi
# props from k60
echo "persist.vendor.mi_sf.optimize_for_refresh_rate.enable=1" >> build/portrom/images/vendor/build.prop
echo "ro.vendor.mi_sf.ultimate.perf.support=true"  >> build/portrom/images/vendor/build.prop

#echo "debug.sf.set_idle_timer_ms=1100" >> build/portrom/images/vendor/build.prop

#echo "ro.surface_flinger.set_touch_timer_ms=200" >> build/portrom/images/vendor/build.prop

# https://source.android.com/docs/core/graphics/multiple-refresh-rate
echo "ro.surface_flinger.use_content_detection_for_refresh_rate=false" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_touch_timer_ms=0" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_idle_timer_ms=0" >> build/portrom/images/vendor/build.prop

#解决开机报错问题
targetVintf=$(find build/portrom/images/system_ext/etc/vintf -type f -name "manifest.xml")
if [ -f "$targetVintf" ]; then
    # Check if the file contains $vndk_version
    if grep -q "<version>$vndk_version</version>" "$targetVintf"; then
        yellow "${vndk_version}已存在，跳过修改" "The file already contains the version $vndk_version. Skipping modification."
    else
        # If it doesn't contain $vndk_version, then add it
        ndk_version="<vendor-ndk>\n     <version>$vndk_version</version>\n </vendor-ndk>"
        sed -i "/<\/vendor-ndk>/a$ndk_version" "$targetVintf"
        yellow "添加成功" "Version $vndk_version added to $targetVintf"
    fi
else
    blue "File $targetVintf not found."
fi

if [[ ${port_rom_code} == "sheng" ]] || [[ ${port_android_version} == "15" ]];then
    blue "Skip StrongToast UI fix"
elif [[ ${port_rom_code} == "houji" ]] || [[ ${port_rom_code} == "shennong" ]] ;then
    blue "左侧挖孔灵动岛修复" "StrongToast UI fix"
    patch_smali "MiuiSystemUI.apk" "MIUIStrongToast\$2.smali" "const\/4 v7\, 0x0" "iget-object v7\, v1\, Lcom\/android\/systemui\/toast\/MIUIStrongToast;->mRLLeft:Landroid\/widget\/RelativeLayout;\\n\\tinvoke-virtual {v7}, Landroid\/widget\/RelativeLayout;->getLeft()I\\n\\tmove-result v7\\n\\tint-to-float v7,v7"
else
blue "左侧挖孔灵动岛修复" "StrongToast UI fix"
    patch_smali "MiuiSystemUI.apk" "MIUIStrongToast\$2.smali" "const\/4 v9\, 0x0" "iget-object v9\, v1\, Lcom\/android\/systemui\/toast\/MIUIStrongToast;->mRLLeft:Landroid\/widget\/RelativeLayout;\\n\\tinvoke-virtual {v9}, Landroid\/widget\/RelativeLayout;->getLeft()I\\n\\tmove-result v9\\n\\tint-to-float v9,v9"
fi

if [[ ${is_eu_rom} == "true" ]];then
    patch_smali "miui-services.jar" "SystemServerImpl.smali" ".method public constructor <init>()V/,/.end method" ".method public constructor <init>()V\n\t.registers 1\n\tinvoke-direct {p0}, Lcom\/android\/server\/SystemServerStub;-><init>()V\n\n\treturn-void\n.end method" "regex"
else 
    if [[ ! -d tmp ]];then
        mkdir -p tmp/
    fi
    blue "开始移除 Android 签名校验" "Disalbe Android 14 Apk Signature Verfier"
    mkdir -p tmp/services/
    cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.jar
    
    java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services  > /dev/null 2>&1
    target_method='getMinimumSignatureSchemeVersionForTargetSdk' 
    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(echo "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } &&    blue "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)
    
    target_canJoinSharedUserId_method='canJoinSharedUserId' 
    find tmp/services/ -type f -name "ReconcilePackageUtils.smali" | while read smali_file; do
        cp -rfv $smali_file tmp/
        method_line=$(grep -n "$target_canJoinSharedUserId_method" "$smali_file" | cut -d ':' -f 1)

        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')

        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")

        replace_with_command="const/4 v${register_number}, 0x1"

        { sed -i "${method_line},${move_result_end_line}d" "$smali_file" && sed -i "${method_line}i\\${replace_with_command}" "$smali_file"; }
    done
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o tmp/services_patched.jar > /dev/null 2>&1
    cp -rf tmp/services_patched.jar build/portrom/images/system/system/framework/services.jar
    
fi

# 主题防恢复
if [ -f build/portrom/images/system/system/etc/init/hw/init.rc ];then
	sed -i '/on boot/a\'$'\n''    chmod 0731 \/data\/system\/theme' build/portrom/images/system/system/etc/init/hw/init.rc
fi


if [[ ${is_eu_rom} == true ]];then
    rm -rf build/portrom/images/product/app/Updater
    baseXGoogle=$(find build/baserom/images/product/ -type d -name "HotwordEnrollmentXGoogleHEXAGON*")
    portXGoogle=$(find build/portrom/images/product/ -type d -name "HotwordEnrollmentXGoogleHEXAGON*")
    if [ -d "${baseXGoogle}" ] && [ -d "${portXGoogle}" ];then
        yellow "查找并替换HotwordEnrollmentXGoogleHEXAGON_WIDEBAND.apk" "Searching and Replacing HotwordEnrollmentXGoogleHEXAGON_WIDEBAND.apk.."
        rm -rf ./${portXGoogle}/*
       cp -rf ./${baseXGoogle}/* ${portXGoogle}/
    else
        if [ -d "${baseXGoogle}" ] && [ ! -d "${portXGoogle}" ];then
            blue "未找到HotwordEnrollmentXGoogleHEXAGON_WIDEBAND.apk，替换为原包" "HotwordEnrollmentXGoogleHEXAGON_WIDEBAND.apk is missing, copying from base..."
            cp -rf ${baseXGoogle} build/portrom/images/product/priv-app/
        fi
    fi
else
    yellow "删除多余的App" "Debloating..." 
    # List of apps to be removed
    debloat_apps=("MSA" "mab" "Updater" "MiuiUpdater" "MiService" "MIService" "SoterService" "Hybrid" "AnalyticsCore")

    for debloat_app in "${debloat_apps[@]}"; do
        # Find the app directory
        app_dir=$(find build/portrom/images/product -type d -name "*$debloat_app*")
        
        # Check if the directory exists before removing
        if [[ -d "$app_dir" ]]; then
            yellow "删除目录: $app_dir" "Removing directory: $app_dir"
            rm -rf "$app_dir"
        fi
    done
    rm -rf build/portrom/images/product/etc/auto-install*
    rm -rf build/portrom/images/product/data-app/*GalleryLockscreen* >/dev/null 2>&1
    mkdir -p tmp/app
    kept_data_apps=("MIUISecurityManager" "MIUIThemeStore" "DownloadProviderUi" "VirtualSim" "ThirdAppAssistant" "GameCenter" "Video" "Weather" "DeskClock" "Gallery" "SoundRecorder" "ScreenRecorder" "Calculator" "CleanMaster" "Calendar" "Compass" "Notes" "MediaEditor" "Scanner" "SpeechEngine" "wps-lite")
    for app in "${kept_data_apps[@]}"; do
        mv build/portrom/images/product/data-app/*"${app}"* tmp/app/ >/dev/null 2>&1
        done

    rm -rf build/portrom/images/product/data-app/*
    cp -rf tmp/app/* build/portrom/images/product/data-app
    rm -rf tmp/app
    rm -rf build/portrom/images/system/verity_key
    rm -rf build/portrom/images/vendor/verity_key
    rm -rf build/portrom/images/product/verity_key
    rm -rf build/portrom/images/system/recovery-from-boot.p
    rm -rf build/portrom/images/vendor/recovery-from-boot.p
    rm -rf build/portrom/images/product/recovery-from-boot.p
    rm -rf build/portrom/images/product/media/theme/miui_mod_icons/com.google.android.apps.nbu*
    rm -rf build/portrom/images/product/media/theme/miui_mod_icons/dynamic/com.google.android.apps.nbu*
fi
# build.prop 修改
blue "正在修改 build.prop" "Modifying build.prop"
#
#change the locale to English
export LC_ALL=en_US.UTF-8
buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}" "modifying ${i}"
    sed -i "s/ro.build.date=.*/ro.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.build.date.utc=.*/ro.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.odm.build.date=.*/ro.odm.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.odm.build.date.utc=.*/ro.odm.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.vendor.build.date=.*/ro.vendor.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system.build.date=.*/ro.system.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system.build.date.utc=.*/ro.system.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.product.build.date=.*/ro.product.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.product.build.date.utc=.*/ro.product.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system_ext.build.date=.*/ro.system_ext.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc=${buildUtc}/g" ${i}
   
    sed -i "s/ro.product.device=.*/ro.product.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.product.name=.*/ro.product.product.name=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.odm.device=.*/ro.product.odm.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.vendor.device=.*/ro.product.vendor.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system.device=.*/ro.product.system.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.board=.*/ro.product.board=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system_ext.device=.*/ro.product.system_ext.device=${base_rom_code}/g" ${i}
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    #全局替换device_code
    if [[ $port_mios_version_incremental != *DEV* ]];then
        sed -i "s/$port_device_code/$base_device_code/g" ${i}
    fi
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    if [[ ${is_eu_rom} == "true" ]];then
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}_xiaomieu_global/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=xiaomi.eu/g" ${i}

    else
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=${build_host}/g" ${i}
    fi
    sed -i "s/ro.build.characteristics=tablet/ro.build.characteristics=nosdcard/g" ${i}
    sed -i "s/ro.config.miui_multi_window_switch_enable=true/ro.config.miui_multi_window_switch_enable=false/g" ${i}
    sed -i "s/ro.config.miui_desktop_mode_enabled=true/ro.config.miui_desktop_mode_enabled=false/g" ${i}
    sed -i "/ro.miui.density.primaryscale=.*/d" ${i}
    sed -i "/persist.wm.extensions.enabled=true/d" ${i}
done

#sed -i -e '$a\'$'\n''persist.adb.notify=0' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.usb.config=mtp,adb' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.disable_rescue=true' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.miui.extm.enable=0' build/portrom/images/system/system/build.prop

# 屏幕密度修修改
for prop in $(find build/baserom/images/product build/baserom/images/system -type f -name "build.prop");do
    base_rom_density=$(< "$prop" grep "ro.sf.lcd_density" |awk 'NR==1' |cut -d '=' -f 2)
    if [ "${base_rom_density}" != "" ];then
        green "底包屏幕密度值 ${base_rom_density}" "Screen density: ${base_rom_density}"
        break 
    fi
done

# 未在底包找到则默认440,如果是其他值可自己修改
[ -z ${base_rom_density} ] && base_rom_density=440

found=0
for prop in $(find build/portrom/images/product build/portrom/images/system -type f -name "build.prop");do
    if grep -q "ro.sf.lcd_density" ${prop};then
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" ${prop}
        found=1
    fi
    sed -i "s/persist.miui.density_v2=.*/persist.miui.density_v2=${base_rom_density}/g" ${prop}
done

if [ $found -eq 0  ]; then
        blue "未找到ro.fs.lcd_density，build.prop新建一个值$base_rom_density" "ro.fs.lcd_density not found, create a new value ${base_rom_density} "
        echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/product/etc/build.prop
fi

echo "ro.miui.cust_erofs=0" >> build/portrom/images/product/etc/build.prop

#vendorprop=$(find build/portrom/images/vendor -type f -name "build.prop")
#odmprop=$(find build/baserom/images/odm -type f -name "build.prop" |awk 'NR==1')
#if [ "$(< $vendorprop grep "sys.haptic" |awk 'NR==1')" != "" ];then
#    blue "复制 haptic prop 到 odm"
#    < $vendorprop grep "sys.haptic" >>${odmprop}
#fi

#Fix： mi10 boot stuck at the first screen
sed -i "s/persist\.sys\.millet\.cgroup1/#persist\.sys\.millet\.cgroup1/" build/portrom/images/vendor/build.prop

#Fix：Fingerprint issue encountered on OS V1.0.18
echo "vendor.perf.framepacing.enable=false" >> build/portrom/images/vendor/build.prop


# Millet fix
blue "修复Millet" "Fix Millet"

millet_netlink_version=$(grep "ro.millet.netlink" build/baserom/images/product/etc/build.prop | cut -d "=" -f 2)

if [[ -n "$millet_netlink_version" ]]; then
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
else
  blue "原包未发现ro.millet.netlink值，请手动赋值修改(默认为29)" "ro.millet.netlink property value not found, change it manually(29 by default)."
  millet_netlink_version=29
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
fi
# add advanced texture
if ! is_property_exists persist.sys.background_blur_supported build/portrom/images/product/etc/build.prop; then
    echo "persist.sys.background_blur_supported=true" >> build/portrom/images/product/etc/build.prop
    echo "persist.sys.background_blur_version=2" >> build/portrom/images/product/etc/build.prop
else
    sed -i "s/persist.sys.background_blur_supported=.*/persist.sys.background_blur_supported=true/" build/portrom/images/product/etc/build.prop
fi

echo "persist.sys.perf.cgroup8250.stune=true" >> build/portrom/images/product/etc/build.prop

unlock_device_feature "Whether support AI Display"  "bool" "support_AI_display"
unlock_device_feature "device support screen enhance engine"  "bool" "support_screen_enhance_engine"
unlock_device_feature "Whether suppot Android Flashlight Controller"  "bool" "support_android_flashlight"
unlock_device_feature "Whether support SR for image display"  "bool" "support_SR_for_image_display"

unlock_device_feature "whether the device aod need grayscale" "bool" "is_aod_need_grayscale"

unlock_device_feature "whether the device supports aod fullscreen mode" "bool" "support_aod_fullscreen"
unlock_device_feature "whether the device supports aod aon mode" "bool" "support_aod_aon"
# Unlock MEMC; unlocking the screen enhance engine is a prerequisite.
# This feature add additional frames to videos to make content appear smooth and transitions lively.
if  grep -q "ro.vendor.media.video.frc.support" build/portrom/images/vendor/build.prop ;then
    sed -i "s/ro.vendor.media.video.frc.support=.*/ro.vendor.media.video.frc.support=true/" build/portrom/images/vendor/build.prop
else
    echo "ro.vendor.media.video.frc.support=true" >> build/portrom/images/vendor/build.prop
fi
# Game splashscreen speed up
echo "debug.game.video.speed=true" >> build/portrom/images/product/etc/build.prop
echo "debug.game.video.support=true" >> build/portrom/images/product/etc/build.prop

# Enable Xiaomi extm dm_opt feature
echo "persist.miui.extm.dm_opt.enable=true" >> build/portrom/images/product/etc/build.prop

# Unlock Smart fps

maxFps=$(xmlstarlet sel -t -v "//integer-array[@name='fpsList']/item" build/portrom/images/product/etc/device_features/${base_rom_code}.xml | sort -nr | head -n 1)

if [ -z "$maxFps" ]; then
    maxFps=90
fi

unlock_device_feature "whether support fps change " "bool" "support_smart_fps"
unlock_device_feature "smart fps value" "integer" "smart_fps_value" "${maxFps}"

if [[ ${base_rom_code} == "munch" ]];then
    unlock_device_feature "whether support dc backlight " "bool" "support_dc_backlight"
    unlock_device_feature "whether backlight bit switch " "bool" "support_backlight_bit_switch"
fi
patch_smali "PowerKeeper.apk" "DisplayFrameSetting.smali" "unicorn" "umi"
if [[ ${is_eu_rom} == true ]];then
    patch_smali "MiSettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"

else
    patch_smali "MISettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"
fi
# Unlock eyecare mode 
unlock_device_feature "default rhythmic eyecare mode" "integer" "default_eyecare_mode" "2"
unlock_device_feature "default texture for paper eyecare" "integer" "paper_eyecare_default_texture" "0"

# Unlock Celluar Sharing feature
    targetFrameworkExtRes=$(find build/portrom/images/system_ext -type f -name "framework-ext-res.apk")
if [[ -f "${targetFrameworkExtRes}" ]] && [[ ${port_android_version} != "15" ]]; then
    mkdir tmp/  > /dev/null 2>&1 
    java -jar bin/apktool/APKEditor.jar d -i $targetFrameworkExtRes -o tmp/framework-ext-res -f > /dev/null 2>&1
    if grep -r config_celluar_shared_support tmp/framework-ext-res/ ; then  
        
        yellow "开启通信共享功能" "Enable Celluar Sharing feature"
        
        for xml in $(find tmp/framework-ext-res -name "*.xml");do
            sed -i 's|<bool name="config_celluar_shared_support">false</bool>|<bool name="config_celluar_shared_support">true</bool>|g' "$xml"

        done
        #rm -rf tmp
    fi
    filename=$(basename $targetFrameworkExtRes)
    java -jar bin/apktool/APKEditor.jar b -i tmp/framework-ext-res -o tmp/$filename -f> /dev/null 2>&1 || error "apktool 打包失败" "apktool mod failed"
        cp -rf tmp/$filename $targetFrameworkExtRes
fi

targetMiLinkOS2APK=$(find build/portrom -type f -name "MiLinkOS2CN.apk")
if [[ -f "${targetMiLinkOS2APK}" ]];then
    cp -rf $targetMiLinkOS2APK tmp/$(basename $targetMiLinkOS2APK).bak
    java -jar bin/apktool/APKEditor.jar d -i $targetMiLinkOS2APK -o tmp/MiLinkOS2 -f > /dev/null 2>&1
    targetsmali=$(find tmp/MiLinkOS2 -name "HMindManager.smali")
    python3 bin/patchmethod.py -d tmp/MiLinkOS2 -k "isSupportCapability() context == null" -return true
    python3 bin/patchmethod.py $targetsmali J -return true
    java -jar bin/apktool/APKEditor.jar b -i tmp/MiLinkOS2 -o $targetMiLinkOS2APK -f > /dev/null 2>&1

fi

targetMIUIThemeManagerAPK=$(find build/portrom -type f -name "MIUIThemeManager.apk")
if [[ -f "${targetMIUIThemeManagerAPK}" ]];then
    cp -rf $targetMIUIThemeManagerAPK tmp/$(basename $targetMIUIThemeManagerAPK).bak
    java -jar bin/apktool/APKEditor.jar d -i $targetMIUIThemeManagerAPK -o tmp/MIUIThemeManager -f > /dev/null 2>&1
    targetsmali=$(find tmp/ -name "o1t.smali" -path "*/basemodule/utils/*")
    python3 bin/patchmethod.py $targetsmali mcp -return true
    java -jar bin/apktool/APKEditor.jar b -i tmp/MIUIThemeManager -o $targetMIUIThemeManagerAPK -f > /dev/null 2>&1

fi

targetSettingsAPK=$(find build/portrom -type f -name "Settings.apk")
if [[ -f "${targetSettingsAPK}" ]];then
    cp -rf $targetSettingsAPK tmp/$(basename $targetSettingsAPK).bak
    java -jar bin/apktool/APKEditor.jar d -i $targetSettingsAPK -o tmp/Settings -f > /dev/null 2>&1
    targetsmali=$(find tmp/ -type f -path "*/com/android/settings/InternalDeviceUtils.smali")
    python3 bin/patchmethod.py $targetsmali isAiSupported -return true
    java -jar bin/apktool/APKEditor.jar b -i tmp/Settings -o $targetSettingsAPK -f > /dev/null 2>&1
fi

if [[ ${port_rom_code} == "munch_cn" ]];then
    # Add missing camera permission android.permission.TURN_SCREEN_ON
    # this missing permission will cause device stuck on boot with higher custom Camera(eg: 5.2.0.XX) integrated
    sed -i 's|<permission name="android.permission.SYSTEM_CAMERA" />|<permission name="android.permission.SYSTEM_CAMERA" />\n\t\t<permission name="android.permission.TURN_SCREEN_ON" />|' build/portrom/images/product/etc/permissions/privapp-permissions-product.xml

fi

#自定义替换

#Add perfect icons
blue "Integrating perfect icons"  
git clone --depth=1 https://github.com/pzcn/Perfect-Icons-Completion-Project.git icons &>/dev/null
for pkg in "$work_dir"/build/portrom/images/product/media/theme/miui_mod_icons/dynamic/*; do
  if [[ -d "$work_dir"/icons/icons/$pkg ]]; then
    rm -rf "$work_dir"/icons/icons/$pkg
  fi
done
rm -rf "$work_dir"/icons/icons/com.xiaomi.scanner
mv "$work_dir"/build/portrom/images/product/media/theme/default/icons "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip
rm -rf "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
mkdir -p "$work_dir"/icons/res
mv "$work_dir"/icons/icons "$work_dir"/icons/res/drawable-xxhdpi
cd "$work_dir"/icons
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip res
cd "$work_dir"/icons/themes/Hyper/
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
cd "$work_dir"/icons/themes/common/
zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
mv "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip "$work_dir"/build/portrom/images/product/media/theme/default/icons
mv "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
rm -rf "$work_dir"/icons
cd "$work_dir"

# Optimize prop from K40s 
if ! is_property_exists ro.miui.surfaceflinger_affinity build/portrom/images/product/etc/build.prop; then
    echo "ro.miui.surfaceflinger_affinity=true" >> build/portrom/images/product/etc/build.prop
fi

#自定义替换

sourceAnimationZIP=$(find build/baserom/images/product -type f -name "bootanimation.zip")
targetAnimationZIP=$(find build/portrom/images/product -type f -name "bootanimation.zip")
cp -rf $sourceAnimationZIP $targetAnimationZIP

if [[ -d "devices/common" ]];then
    commonCamera=$(find devices/common -type f -name "MiuiCamera.apk")
    targetCamera=$(find build/portrom/images/product -type d -name "MiuiCamera")
    targetNQNfcNci=$(find build/portrom/images/system/system build/portrom/images/product build/portrom/images/system_ext -type d -name "NQNfcNci*")

    
    if [[ $nfc_fix_type == "legacy" ]];then
        if [[ -d "${targetNQNfcNci}" ]];then
        rm -rf $targetNQNfcNci
        fi
        find build/portrom/images/ -name "com.nxp.nfc.nq.jar" -type f -delete
        find build/portrom/images/ -name "com.xiaomi.nfc.jar" -type f -delete
        unzip -oq devices/common/nfc_legacy.zip -d build/portrom/images/
    elif [[ $nfc_fix_type == "a14" ]]; then
        unzip -oq devices/common/nfc_a14.zip -d build/portrom/images/
        echo "ro.vendor.nfc.dispatch_optim=1" >> build/portrom/images/vendor/build.prop
    elif [[ ${port_android_version} == "15" ]]; then
        unzip -oq devices/common/nfc_a15.zip -d build/portrom/images/
        echo "ro.vendor.nfc.dispatch_optim=1" >> build/portrom/images/vendor/build.prop
    fi
    if [[ $base_rom_code == "munch" ]] && [[ ${port_android_version} == "15" ]]; then
        sourceCamera=$(find build/baserom/images/ -type f -name "MiuiCamera.apk")
        targetCamera=$(find build/portrom/images/ -type d -name "MiuiCamera")
        cp -rf $sourceCamera $targetCamera/
    else
    
    if [[ ${base_android_version} == "13" ]] && [[ -f "${commonCamera}" ]];then
        yellow "替换相机为10S HyperOS A13 相机，MI10可用, thanks to 酷安 @PedroZ" "Replacing a compatible MiuiCamera.apk verson 4.5.003000.2"
        if [[ -d "${targetCamera}" ]];then
            rm -rf $targetCamera/*
        fi
        cp -rf $commonCamera $targetCamera
    fi
    fi
    
fi

#Devices/机型代码/overaly 按照镜像的目录结构，可直接替换目标。
if [[ -d "devices/${base_rom_code}/overlay" ]]; then
    cp -rf devices/${base_rom_code}/overlay/* build/portrom/images/
else
    yellow "devices/${base_rom_code}/overlay 未找到" "devices/${base_rom_code}/overlay not found" 
fi

for zip in $(find devices/${base_rom_code}/ -name "*.zip"); do
    if unzip -l $zip | grep -q "anykernel.sh" ;then
        blue "检查到第三方内核压缩包 $zip [AnyKernel类型]" "Custom Kernel zip $zip detected [Anykernel]"
        if echo $zip | grep -q ".*-KSU" ; then
          unzip $zip -d tmp/anykernel-ksu/ > /dev/null 2>&1
        elif echo $zip | grep -q ".*-NoKSU" ; then
          unzip $zip -d tmp/anykernel-noksu/ > /dev/null 2>&1
        else
          unzip $zip -d tmp/anykernel/ > /dev/null 2>&1
        fi
    fi
done
for anykernel_dir in tmp/anykernel*; do
    if [ -d "$anykernel_dir" ]; then
        blue "开始整合第三方内核进boot.img" "Start integrating custom kernel into boot.img"
        kernel_file=$(find "$anykernel_dir" -name "Image" -exec readlink -f {} +)
        dtb_file=$(find "$anykernel_dir" -name "dtb" -exec readlink -f {} +)
        dtbo_img=$(find "$anykernel_dir" -name "dtbo.img" -exec readlink -f {} +)
        if [[ "$anykernel_dir" == *"-ksu"* ]]; then
            cp $dtbo_img ${work_dir}/devices/$base_rom_code/dtbo_ksu.img
            patch_kernel_to_bootimg "$kernel_file" "$dtb_file" "boot_ksu.img"
            blue "生成内核boot_boot_ksu.img完毕" "New boot_ksu.img generated"
        elif [[ "$anykernel_dir" == *"-noksu"* ]]; then
            cp $dtbo_img ${work_dir}/devices/$base_rom_code/dtbo_noksu.img
            patch_kernel_to_bootimg "$kernel_file" "$dtb_file" "boot_noksu.img"
            blue "生成内核boot_noksu.img" "New boot_noksu.img generated"
        else
            cp $dtbo_img ${work_dir}/devices/$base_rom_code/dtbo_custom.img
            patch_kernel_to_bootimg "$kernel_file" "$dtb_file" "boot_custom.img"
            blue "生成内核boot_custom.img完毕" "New boot_custom.img generated"
        fi
    fi
    rm -rf $anykernel_dir
done

#添加erofs文件系统fstab
if [ ${pack_type} == "EROFS" ];then
    yellow "检查 vendor fstab.qcom是否需要添加erofs挂载点" "Validating whether adding erofs mount points is needed."
    if ! grep -q "erofs" build/portrom/images/vendor/etc/fstab.qcom ; then
               for pname in system odm vendor product mi_ext system_ext; do
                     sed -i "/\/${pname}[[:space:]]\+ext4/{p;s/ext4/erofs/;s/ro,barrier=1,discard/ro/;}" build/portrom/images/vendor/etc/fstab.qcom
                     added_line=$(sed -n "/\/${pname}[[:space:]]\+erofs/p" build/portrom/images/vendor/etc/fstab.qcom)
    
                    if [ -n "$added_line" ]; then
                        yellow "添加$pname" "Adding mount point $pname"
                    else
                        error "添加失败，请检查" "Adding faild, please check."
                        exit 1
                        
                    fi
                done
    fi
fi

# 去除avb校验
blue "去除avb校验" "Disable avb verification."
disable_avb_verify build/portrom/images/

# data 加密
remove_data_encrypt=$(grep "remove_data_encryption" bin/port_config |cut -d '=' -f 2)
if [ ${remove_data_encrypt} = "true" ];then
    blue "去除data加密"
    for fstab in $(find build/portrom/images -type f -name "fstab.*");do
		blue "Target: $fstab"
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts//g" $fstab
        sed -i "s/,fileencryption=ice//g" $fstab
		sed -i "s/fileencryption/encryptable/g" $fstab
	done
fi

for pname in ${port_partition};do
    rm -rf build/portrom/images/${pname}.img
done
echo "${pack_type}">fstype.txt
superSize=$(bash bin/getSuperSize.sh $device_code)
green "Super大小为${superSize}" "Super image size: ${superSize}"
green "开始打包镜像" "Packing img"


if [ "$pack_type" = "EXT" ];then
    img_free() {
    size_free="$(tune2fs -l build/portrom/images/${i}.img | awk '/Free blocks:/ { print $3 }')"
    size_free="$(echo "$size_free / 4096 * 1024 * 1024" | bc)"
    if [[ $size_free -ge 1073741824 ]]; then
    File_Type=$(awk "BEGIN{print $size_free/1073741824}")G
    elif [[ $size_free -ge 1048576 ]]; then
    File_Type=$(awk "BEGIN{print $size_free/1048576}")MB
    elif [[ $size_free -ge 1024 ]]; then
    File_Type=$(awk "BEGIN{print $size_free/1024}")kb
    elif [[ $size_free -le 1024 ]]; then
    File_Type=${size_free}b
    fi
    blue "${i}.img 剩余空间: $File_Type" "${i}.img remain space: $File_Type"
    }
    for i in ${super_list}; do
        eval "$i"_size_orig=$(sudo du -sb build/portrom/images/$i | awk {'print $1'})
        if [[ "$(eval echo "$"$i"_size_orig")" -lt "1048576" ]]; then
        size=1048576
        elif [[ "$(eval echo "$"$i"_size_orig")" -lt "104857600" ]]; then
        size=$(echo "$(eval echo "$"$i"_size_orig") * 15 / 10 / 4096 * 4096" | bc)
        elif [[ "$(eval echo "$"$i"_size_orig")" -lt "1073741824" ]]; then
        size=$(echo "$(eval echo "$"$i"_size_orig") * 108 / 100 / 4096 * 4096" | bc)
        else
        size=$(echo "$(eval echo "$"$i"_size_orig") * 103 / 100 / 4096 * 4096" | bc)
        fi
        eval "$i"_size=$size
    done
    system_size=$(echo "$system_size * 4096 / 4096 / 4096" | bc)
    vendor_size=$(echo "$vendor_size * 4096 / 4096 / 4096" | bc)
    product_size=$(echo "$product_size * 4096 / 4096 / 4096" | bc)
    odm_size=$(echo "$odm_size * 4096 / 4096 / 4096" | bc)
    system_ext_size=$(echo "$system_ext_size * 4096 / 4096 / 4096" | bc)
    mi_ext_size=$(echo "$mi_ext_size * 4096 / 4096 / 4096" | bc)
    for i in ${super_list}; do
        mkdir -p build/portrom/images/$i/lost+found
        sudo touch -t 200901010000.00 build/portrom/images/$i/lost+found
    done
    for i in ${super_list}; do
        blue "正在生成: $i " "Generating $i"
        python3 bin/fspatch.py build/portrom/images/$i build/portrom/images/config/"$i"_fs_config
        python3 bin/contextpatch.py build/portrom/images/$i build/portrom/images/config/"$i"_file_contexts
        eval "$i"_inode=$(sudo cat build/portrom/images/config/"$i"_fs_config | wc -l)
        eval "$i"_inode=$(echo "$(eval echo "$"$i"_inode") + 8" | bc)
        mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 build/portrom/images/$i.img $(eval echo "$"$i"_size") || false
        if [[ "${ext_rw}" == "true" ]]; then
        e2fsdroid -e -T 1230768000 -C build/portrom/images/config/"$i"_fs_config -S build/portrom/images/config/"$i"_file_contexts -f build/portrom/images/$i -a /$i build/portrom/images/$i.img || false
        else
        e2fsdroid -e -T 1230768000 -C build/portrom/images/config/"$i"_fs_config -S build/portrom/images/config/"$i"_file_contexts -f build/portrom/images/$i -a /$i -s build/portrom/images/$i.img || false
        fi
        if [[ "${ext_rw}" != "true" ]];then
        resize2fs -f -M build/portrom/images/$i.img
        fi
        img_free
        if [[ $i == mi_ext ]]; then
        sudo rm -rf build/portrom/images/$i
        continue
        fi
        size_free=$(tune2fs -l build/portrom/images/$i.img | awk '/Free blocks:/ { print $3}')
        # 第二次打包 (不预留空间)
        if [[ "$size_free" != 0 && "${Readaw}" != "true" ]]; then
        size_free=$(echo "$size_free * 4096" | bc)
        eval "$i"_size=$(du -sb build/portrom/images/$i.img | awk {'print $1'})
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") - $size_free" | bc)
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") * 4096 / 4096 / 4096" | bc)
        sudo rm -rf build/portrom/images/$i.img
        blue "二次生成: $i" "Regenerate $i"
        mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 build/portrom/images/$i.img $(eval echo "$"$i"_size") || false
        if [[ "${ext_rw}" == "true" ]]; then
            e2fsdroid -e -T 1230768000 -C build/portrom/images/config/"$i"_fs_config -S build/portrom/images/config/"$i"_file_contexts -f build/portrom/images/$i -a /$i build/portrom/images/$i.img || false
        else
            e2fsdroid -e -T 1230768000 -C build/portrom/images/config/"$i"_fs_config -S build/portrom/images/config/"$i"_file_contexts -f build/portrom/images/$i -a /$i -s build/portrom/images/$i.img || false
        fi
        resize2fs -f -M build/portrom/images/$i.img
        fi
        #sudo rm -rf build/portrom/images/$i
    done
    
else
    for pname in ${super_list};do
                blue 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
                python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config
                python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts
                #sudo perl -pi -e 's/\\@/@/g' build/portrom/images/config/${pname}_file_contexts
        mkfs.erofs -zlz4hc,9 --mount-point /${pname} --fs-config-file build/portrom/images/config/${pname}_fs_config --file-contexts build/portrom/images/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}
                if [ -f "build/portrom/images/${pname}.img" ];then
                    green "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
                    #rm -rf build/portrom/images/${pname}
                else
                    error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
                    exit 1
    fi
done
fi
rm fstype.txt
os_type="hyperos"
if [[ ${is_eu_rom} == true ]];then
    os_type="xiaomi.eu"
fi

for img in $(find build/baserom/ -type f -name "vbmeta*.img");do
    python3 bin/patch-vbmeta.py ${img} > /dev/null 2>&1
done

if [[ $pack_method == "aosp" ]];then
    rm -rf out/target/product/${base_rom_code}/
    mkdir -p out/target/product/${base_rom_code}/IMAGES
    mkdir -p out/target/product/${base_rom_code}/META
    for part in SYSTEM SYSTEM_EXT PRODUCT VENDOR ODM MI_EXT; do
        mkdir -p out/target/product/${base_rom_code}/$part
    done
    mv -fv build/portrom/images/*.img out/target/product/${base_rom_code}/IMAGES/
    if [[ -d build/baserom/firmware-update ]];then
        bootimg=$(find build/baserom/ -name "boot.img")
        cp -rf $bootimg out/target/product/${base_rom_code}/IMAGES/
    else
        mv -fv build/baserom/images/*.img out/target/product/${base_rom_code}/IMAGES/
    fi

    if [[ -d devices/${base_rom_code} ]];then

        ksu_bootimg_file=$(find devices/$base_rom_code/ -type f -name "*boot_ksu.img")
        dtbo_file=$(find devices/$base_rom_code/ -type f -name "*dtbo_ksu.img")
        if [ -f $ksu_bootimg_file ];then
            mv -fv $ksu_bootimg_file out/target/product/${base_rom_code}/IMAGES/boot.img
            mv -fv $dtbo_file out/target/product/${base_rom_code}/IMAGES/dtbo.img
        fi
    fi
    rm -rf out/target/product/${base_rom_code}/META/ab_partitions.txt
    rm -rf out/target/product/${base_rom_code}/META/update_engine_config.txt
    rm -rf out/target/product/${base_rom_code}/target-file.zip
    for part in out/target/product/${base_rom_code}/IMAGES/*.img; do
        partname=$(basename "$part" .img)
        echo $partname >> out/target/product/${base_rom_code}/META/ab_partitions.txt
        if echo $super_list | grep -q -w "$partname"; then
            super_list_info+="$partname "
            bin/Linux/x86_64/map_file_generator $part ${part%.*}.map
        fi
    done 
    rm -rf out/target/product/${base_rom_code}/META/dynamic_partitions_info.txt
    let groupSize=superSize-1048576
    {
        echo "super_partition_size=$superSize"
        echo "super_partition_groups=qti_dynamic_partitions"
        echo "super_qti_dynamic_partitions_group_size=$groupSize"
        echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
        echo "virtual_ab=true"
        echo "virtual_ab_compression=true"
    } >> out/target/product/${base_rom_code}/META/dynamic_partitions_info.txt

    {
        #echo "default_system_dev_certificate=key/testkey"
        echo "recovery_api_version=3"
        echo "fstab_version=2"
        echo "ab_update=true"
     } >> out/target/product/${base_rom_code}/META/misc_info.txt
    
    {
        echo "PAYLOAD_MAJOR_VERSION=2"
        echo "PAYLOAD_MINOR_VERSION=8"
    } >> out/target/product/${base_rom_code}/META/update_engine_config.txt
    
    if [[ "$is_ab_device" == false ]];then
        sed -i "/ab_update=true/d" out/target/product/${base_rom_code}/META/misc_info.txt
        {
            echo "blockimgdiff_versions=3,4"
            echo "use_dynamic_partitions=true"
            echo "dynamic_partition_list=$super_list_info"
            echo "super_partition_groups=qti_dynamic_partitions"
            echo "super_qti_dynamic_partitions_group_size=$superSize"
            echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
            echo "board_uses_vendorimage=true"
            echo "cache_size=402653184"

        } >> out/target/product/${base_rom_code}/META/misc_info.txt
        recovery_file=$(find build/portrom/ -name "recovery-from-boot.p")
        if [[ -f "${recovery_file}" ]];then
            cp -rfv $recovery_file out/target/product/${base_rom_code}/VENDOR/
        fi
        mkdir -p out/target/product/${base_rom_code}/OTA/bin
        if [[ -f devices/${base_device_code}/OTA/updater ]];then
            cp -rf devices/${base_device_code}/OTA/updater out/target/product/${base_rom_code}/OTA/bin
        else
            cp -rf devices/common/non-ab/OTA/updater out/target/product/${base_rom_code}/OTA/bin
        fi
        if [[ -d build/baserom/firmware-update ]];then
            cp -rf build/baserom/firmware-update out/target/product/${base_rom_code}/
        elif find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \) | grep -q .; then
            for firmware in $(find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \));do
                mv  -rfv $firmware out/target/product/${base_rom_code}/firmware-update
            done
            bootimg=$(find build/baserom/ -name "boot.img")
            dtboimg=$(find build/baserom/images -name "dtbo.img")
            vbmetaimg=$(find build/baserom/images -name "vbmeta.img")
            vmbeta_systemimg=$(find build/baserom/images -name "vbmeta_sytem.img")
            cp -rf $bootimg out/target/product/${base_rom_code}/IMAGES/
            cp -rf $dtboimg out/target/product/${base_rom_code}/firmware-update
            cp -rf $vbmetaimg out/target/product/${base_rom_code}/firmware-update
            cp -rf $vmbeta_systemimg out/target/product/${base_rom_code}/firmware-update
        fi
        export OUT=$(pwd)/out/target/product/${base_rom_code}/
        if [[ -f devices/${base_device_code}/releasetools.py ]];then
            cp -rf devices/${base_device_code}/releasetools.py out/target/product/${base_rom_code}/META/
        else
            cp -rf devices/common/releasetools.py out/target/product/${base_rom_code}/META/
        fi

        mkdir -p out/target/product/${base_rom_code}/RECOVERY/RAMDISK/etc/
        if [[ -f devices/${base_device_code}/recovery.fstab ]];then
            cp -rf devices/${base_device_code}/recovery.fstab out/target/product/${base_rom_code}/RECOVERY/RAMDISK/etc/
        else
            cp -rf devices/common/recovery.fstab out/target/product/${base_rom_code}/RECOVERY/RAMDISK/etc/
        fi
    fi
    declare -A prop_paths=(
    ["system"]="SYSTEM"
    ["product"]="PRODUCT"
    ["system_ext"]="SYSTEM_EXT"
    ["vendor"]="VENDOR"
    ["odm"]="ODM"
    )

    for dir in "${!prop_paths[@]}"; do
        prop_file=$(find "build/portrom/images/$dir" -type f -name "build.prop" -print -quit)
        if [ -n "$prop_file" ]; then
            cp "$prop_file" "out/target/product/${base_rom_code}/${prop_paths[$dir]}/"
        fi
    done
    pushd otatools
    export PATH=${work_dir}/otatools/bin/:$PATH
    ./bin/ota_from_target_files ${work_dir}/out/target/product/${base_rom_code}/ ${work_dir}/out/${base_rom_code}-ota_full_${port_rom_version}-user-${port_android_version}.0.zip
    popd
    ziphash=$(md5sum out/${base_rom_code}-ota_full_${port_rom_version}-user-${port_android_version}.0.zip |head -c 10)
    if [[ ${is_eu_rom} == true ]];then
       rom_code="xiaomi.eu"_$base_rom_code
    else
       rom_code=$base_rom_code
    fi  
    mv -f out/${base_rom_code}-ota_full_${port_rom_version}-user-${port_android_version}.0.zip out/${rom_code}-ota_full-${port_rom_version}-user-${port_android_version}.0-${ziphash}.zip
    green "$(pwd)/out/${rom_code}-ota_full_${port_rom_version}-user-${port_android_version}.0-${ziphash}.zip"

else
# 打包 super.img
if [[ "$is_ab_device" == false ]];then
    blue "打包A-only super.img" "Packing super.img for A-only device"
    lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor;do
        if [ -f "build/portrom/images/${pname}.img" ];then
            if [[ "$OSTYPE" == "darwin"* ]];then
               subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
            else
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            fi
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
else
    blue "打包V-A/B机型 super.img" "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

    for pname in ${super_list};do
        if [ -f "build/portrom/images/${pname}.img" ];then
            subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=build/portrom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
fi
lpmake $lpargs
#echo "lpmake $lpargs"
if [ -f "build/portrom/images/super.img" ];then
    green "成功打包 super.img" "Pakcing super.img done."
else
    error "无法打包 super.img"  "Unable to pack super.img."
    exit 1
fi
#for pname in ${super_list};do
#    rm -rf build/portrom/images/${pname}.img
#done



blue "正在压缩 super.img" "Comprising super.img"
zstd --rm build/portrom/images/super.img -o build/portrom/images/super.zst
mkdir -p out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/


blue "正在生成刷机脚本" "Generating flashing script"

    mkdir -p out/${os_type}_${device_code}_${port_rom_version}/bin/windows/
    mv -f build/portrom/images/super.zst out/${os_type}_${device_code}_${port_rom_version}/
    #firmware
    cp -rf bin/flash/platform-tools-windows/* out/${os_type}_${device_code}_${port_rom_version}/bin/windows/
    cp -rf bin/flash/mac_linux_flash_script.sh out/${os_type}_${device_code}_${port_rom_version}/
    cp -rf bin/flash/windows_flash_script.bat out/${os_type}_${device_code}_${port_rom_version}/

cp -rf bin/flash/update-binary out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/

if [ $is_ab_device == "false" ];then
    sed -i "s/_a//g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    sed -i "s/_a//g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    sed -i "s/_a//g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "/_b/d" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    sed -i "/_b/d" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    sed -i "/_b/d" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i '/^# SET_ACTION_SLOT_A_BEGIN$/,/^# SET_ACTION_SLOT_A_END$/d' out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    sed -i '/^REM SET_ACTION_SLOT_A_BEGIN/,/^REM SET_ACTION_SLOT_A_END/d' out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
fi
        mkdir -p out/${os_type}_${device_code}_${port_rom_version}/firmware-update
# Broli type firmware
if [ -d build/baserom/firmware-update ];then  
        cp -rf build/baserom/firmware-update/*  out/${os_type}_${device_code}_${port_rom_version}/firmware-update
         for fwimg in $(ls out/${os_type}_${device_code}_${port_rom_version}/firmware-update);do
    if [[ ${fwimg} == *"dtbo"* ]] || [[ ${fwimg} == *"cust"* ]]; then
                continue
            elif [[ ${fwimg} == "uefi_sec.mbn" ]];then
                part="uefisecapp"
            elif [[ ${fwimg} == "qupv3fw.elf" ]];then
                part="qupfw"
            elif [[ ${fwimg} == "NON-HLOS.bin" ]];then
                part="modem"
            elif [[ ${fwimg} == "km4.mbn" ]];then
                part="keymaster"
            elif [[ ${fwimg} == "BTFM.bin" ]];then
                part="bluetooth"
            elif [[ ${fwimg} == "dspso.bin" ]];then
                part="dsp"
            else
                part=${fwimg%.*}                
            fi
    if [[ $is_ab_device == "true" ]];then
        sed -i "/# firmware/a fastboot flash ${part}_a firmware-update/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
        sed -i "/# firmware/a fastboot flash ${part}_b firmware-update/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
        sed -i "/REM firmware/a bin\\\windows\\\fastboot.exe flash ${part}_a %~dp0firmware-update\/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "/REM firmware/a bin\\\windows\\\fastboot.exe flash ${part}_b %~dp0firmware-update\/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}\" \"/dev/block/bootdevice/by-name/${part}_a\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}\" \"/dev/block/bootdevice/by-name/${part}_b\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    else
            sed -i "/# firmware/a fastboot flash ${part} firmware-update/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
            sed -i "/REM firmware/a bin\\\windows\\\fastboot.exe flash ${part} %~dp0firmware-update\/${fwimg}" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    fi
    done
# Payload.bin type firmware
else
    cp -f build/baserom/images/*.img out/${os_type}_${device_code}_${port_rom_version}/firmware-update/
    if [[ $is_ab_device = "false" ]];then
        for fwimg in $(ls out/${os_type}_${device_code}_${port_rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"boot"* ]] || [[ $fwimg == *"dtbo"* ]] ;then
                continue
            elif [[ $fwimg == "mdm_oem_stanvbk" ]] || [[ $fwimg == "spunvm" ]] ;then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
            elif [ "$(echo ${fwimg} |grep vbmeta)" != "" ];then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
            else
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
            fi
        done
        sed -i "/_b/d" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/_a//g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i '/^REM SET_ACTION_SLOT_A_BEGIN/,/^REM SET_ACTION_SLOT_A_END/d' out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    else
        for fwimg in $(ls out/${os_type}_${device_code}_${port_rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"dtbo"* ]] || [[ $fwimg == *"reserve"* ]] || [[ $fwimg == *"boot"* ]];then
                continue
            elif [[ $fwimg == "mdm_oem_stanvbk" ]] || [[ $fwimg == "spunvm" ]] ;then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
                sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
            elif [ "$(echo ${fwimg} |grep vbmeta)" != "" ];then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
                sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}_a\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
                sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}_b\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
            else
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
                sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}_a\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
                sed -i "/# firmware/a package_extract_file \"firmware-update/${fwimg}_b\" \"/dev/block/bootdevice/by-name/${part}\"" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
            fi
        done
    fi
    fi

    #disable vbmeta
    for img in $(find out/${os_type}_${device_code}_${port_rom_version}/firmware-update -type f -name "vbmeta*.img");do
        python3 bin/patch-vbmeta.py ${img} > /dev/null 2>&1
    done
    cp -rf bin/flash/zstd out/${os_type}_${device_code}_${port_rom_version}/META-INF/

    ksu_bootimg_file=$(find devices/$base_rom_code/ -type f -name "*boot_ksu.img")
    nonksu_bootimg_file=$(find devices/$base_rom_code/ -type f -name "*boot_noksu.img")
    custom_bootimg_file=$(find devices/$base_rom_code/ -type f -name "*boot_custom.img")
    if [[ -f "${nonksu_bootimg_file}" ]];then
        nonksubootimg=$(basename "$nonksu_bootimg_file")
        mv -f $nonksu_bootimg_file out/${os_type}_${device_code}_${port_rom_version}/
        mv -f  devices/$base_rom_code/dtbo_noksu.img out/${os_type}_${device_code}_${port_rom_version}/firmware-update/dtbo_noksu.img
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    else
            bootimg=$(find out/${os_type}_${device_code}_${port_rom_version} build/baserom/ -name "boot.img" | head -n 1)
            if [ ! -f "${bootimg}" ];then
                bootimg=$(find build/baserom/ -name "boot.img")
            fi
    mv -f $bootimg out/${os_type}_${device_code}_${port_rom_version}/boot_official.img
    fi

    if [[ -f "$ksu_bootimg_file" ]];then
        ksubootimg=$(basename "$ksu_bootimg_file")
        mv -f $ksu_bootimg_file out/${os_type}_${device_code}_${port_rom_version}/
        mv -f  devices/$base_rom_code/dtbo_ksu.img out/${os_type}_${device_code}_${port_rom_version}/firmware-update/dtbo_ksu.img
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    sed -i '/^REM OFFICAL_BOOT_START/,/^REM OFFICAL_BOOT_END/d' out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        
    elif [[ -f "$custom_bootimg_file" ]];then
        custombootimg=$(basename "$custom_botimg_file")
        mv -f $custom_botimg_file out/${os_type}_${device_code}_${port_rom_version}/
        mv -f  devices/$base_rom_code/dtbo_custom.img out/${os_type}_${device_code}_${port_rom_version}/firmware-update/dtbo_custom.img
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
else
    sed -i '/^REM CUSTOM_BOOT_START/,/^REM CUSTOM_BOOT_END/d' out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    fi

    sed -i "s/portversion/${port_rom_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/${os_type}_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/${os_type}_${device_code}_${port_rom_version}/mac_linux_flash_script.sh
    sed -i "s/device_code/${base_rom_code}/g" out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat
    busybox unix2dos out/${os_type}_${device_code}_${port_rom_version}/windows_flash_script.bat

find out/${os_type}_${device_code}_${port_rom_version} |xargs touch
pushd out/${os_type}_${device_code}_${port_rom_version}/ >/dev/null || exit
zip -r ${os_type}_${device_code}_${port_rom_version}.zip ./*
mv ${os_type}_${device_code}_${port_rom_version}.zip ../
popd >/dev/null || exit
pack_timestamp=$(date +"%m%d%H%M")
hash=$(md5sum out/${os_type}_${device_code}_${port_rom_version}.zip |head -c 10)
if [[ $pack_type == "EROFS" ]];then
    pack_type="ROOT_"${pack_type}
    yellow "检测到打包类型为EROFS,请确保官方内核支持，或者在devices机型目录添加有支持EROFS的内核，否者将无法开机！" "EROFS filesystem detected. Ensure compatibility with the official boot.img or ensure a supported boot_tv.img is placed in the device folder."
fi
mv out/${os_type}_${device_code}_${port_rom_version}.zip out/${os_type}_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip
green "移植完毕" "Porting completed"    
green "输出包路径：" "Output: "
green "$(pwd)/out/${os_type}_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip"
fi
