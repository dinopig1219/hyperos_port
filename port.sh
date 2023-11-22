#!/bin/bash

# hyperOS_port project

# For A-only and V/A-B (not tested) Devices

# Based on Android 13

# Test Base ROM: A-only Mi 10 (V14.0.4)

# Test Port ROM: Mi14 Pro OS1.0.9-1.0.21


build_user="Bruce Teng"
build_host=$(hostname)

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$PATH

shopt -s expand_aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS detected,setting alias"
    alias sed=gsed
    alias tr=gtr
    alias grep=ggrep
    alias du=gdu
    #alias find=gfind
fi
# 定义颜色输出函数
error() {
    echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$@"\033[0m"
}

yellow() {
    echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$@"\033[0m"
}

blue() {
    echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$@"\033[0m"
}

green() {
	echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$@"\033[0m"
}

# 向 apk 或 jar 文件中替换 smali 代码，不支持资源补丁
# $1: 目标 apk/jar 文件
# $2: 目标 smali 文件
# $3: 被替换值
# $4: 替换值
patch_smali() {
    targetfilefullpath=$(find build/portrom/images -type f -name $1)
    targetfilename=$(basename $targetfilefullpath)
    if [ -f $targetfilefullpath ];then
        yellow "正在修改 $targetfilename"
        foldername=${targetfilename%.*}
        rm -rf tmp/$foldername/
        mkdir -p tmp/$foldername/
        cp -rf $targetfilefullpath tmp/$foldername/
        7z x -y tmp/$foldername/$targetfilename *.dex -otmp/$foldername >/dev/null
        for dexfile in tmp/$foldername/*.dex;do
            smalifname=${dexfile%.*}
            smalifname=$(echo $smalifname | cut -d "/" -f 3)
            java -jar bin/apktool/baksmali.jar d --api ${port_android_sdk} ${dexfile} -o tmp/$foldername/$smalifname 2>&1 || error " Baksmaling 失败"
        done

        targetsmali=$(find tmp/$foldername -type f -name $2)
        if [ -f $targetsmali ];then
            smalidir=$(echo $targetsmali |cut -d "/" -f 3)
            yellow I: 找到目标 $(basename ${targetsmali}) 位于 ${smalidir}.dex 文件
            
            yellow I: 开始patch目标 ${smalidir}
            search_pattern=$3
            repalcement_pattern=$4
            sed -i "s/$search_pattern/$repalcement_pattern/g" $targetsmali
            #rm -rf ${targetfilefullpath}
            java -jar bin/apktool/smali.jar a --api ${port_android_sdk} tmp/$foldername/${smalidir} -o tmp/$foldername/${smalidir}.dex > /dev/null 2>&1 || error " Smaling 失败"
            pushd tmp/$foldername/ >/dev/null || exit
            #macOS上用7z添加文件到apk会提示错误,jar正常
            #fixme
            if [[ "$OSTYPE" == "darwin"* ]];then
                zip -our $targetfilename ${smalidir}.dex > /dev/null 2>&1 || error "修改$targetfilename失败"
            else
                7z a -y -mx0 $targetfilename ${smalidir}.dex  > /dev/null 2>&1 || error "修改$targetfilename失败"
            fi
            popd >/dev/null || exit
            cp -rf tmp/$foldername/$targetfilename ${targetfilefullpath}
            fi
    fi

}

#重新打包apk后会崩，暂不知原因，弃用
#fixme
patch_apk() {
    if [[ $5 == "1" ]];then
        nores="--no-res"
    else
        nores=""
    fi
    apkfile=$(find build/portrom/images -type f -name "$1")
    if [ -f $apkfile ]; then
        mkdir -p tmp/
        apkname=$(basename $apkfile | cut -d "." -f 1)
        bin/apktool/apktool d $nores $apkfile -o tmp/$apkname -f
        targetSmali=$(find tmp/$apkname -type f -name "$2")
        yellow "找到目标$targetSmali patching..."
        if sed -i "s/$3/$4/g" $targetSmali; then 
            yellow "patch $3成功，开始重新打包并替换$apkfile"
             bin/apktool/apktool b tmp/$apkname -o $apkname.apk -f
            cp -Rf $apkname.apk $apkfile
        else
            error "patch失败，检查是否方法已改变"
        fi 
    fi
}

# 移植的分区，可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
#super_list=$(grep "super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
# 检查为本地包还是链接

if [ ! -f "${baserom}" ] && [ "$(echo $baserom |grep http)" != "" ];then
    blue "底包为一个链接，正在尝试下载"
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${baserom}
    baserom=$(basename ${baserom})
    if [ ! -f "${baserom}" ];then
        error "下载错误"
    fi
elif [ -f "${baserom}" ];then
    green "底包: ${baserom}"
else
    error "底包参数错误"
    exit
fi

if [ ! -f "${portrom}" ] && [ "$(echo ${portrom} |grep http)" != "" ];then
    blue "移植包为一个链接，正在尝试下载"
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${portrom}
    portrom=$(basename ${portrom})
    if [ ! -f "${portrom}" ];then
        error "下载错误"
    fi
elif [ -f "${portrom}" ];then
    green "移植包: ${portrom}"
else
    error "移植包参数错误"
    exit
fi

if [ "$(echo $baserom |grep miui_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="YourDevice"
fi


blue "正在检测ROM底包"
if unzip -l ${baserom} | grep -q "payload.bin"; then
    baserom_type="payload"
    super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
elif unzip -l ${baserom} | grep -q "br$";then
    baserom_type="br"
    super_list="vendor mi_ext odm system product system_ext"
    
else
    error "底包中未发现payload.bin以及br文件，请使用MIUI官方包后重试"
    exit
fi

blue "开始检测ROM移植包"
unzip -l ${portrom} |grep "payload.bin" 1>/dev/null 2>&1 ||{ error "目标移植包没有payload.bin，请用MIUI官方包作为移植包"; exit 1; }

green "ROM初步检测通过"

blue "正在清理文件"
for i in ${port_partition};do
    [ -d ./${i} ] && rm -rf ./${i}
done
sudo rm -rf app
sudo rm -rf tmp
sudo rm -rf config
sudo rm -rf build/baserom/
sudo rm -rf build/portrom/
find . -type d -name 'hyperos_*' |xargs rm -rf

green "文件清理完毕"


mkdir -p build/baserom/images/
mkdir -p build/baserom/config/
mkdir -p build/portrom/images/
mkdir -p build/portrom/config/
# 提取分区
if [ ${baserom_type} = 'payload' ];then
    blue "正在提取底包 [payload.bin]"
    unzip ${baserom} payload.bin -d build/baserom > /dev/null 2>&1 ||error "解压底包 [payload.bin] 时出错"
    green "底包 [payload.bin] 提取完毕"
else
    blue "正在提取底包 [new.dat.br]"
    unzip ${baserom} -d build/baserom  > /dev/null 2>&1 || error "解压底包 [new.dat.br]时出错"
    green "底包 [new.dat.br] 提取完毕"
fi

blue "正在提取移植包 [payload.bin]"
unzip ${portrom} payload.bin -d build/portrom  > /dev/null 2>&1 ||error "解压移植包 [payload.bin] 时出错"
green "移植包 [payload.bin] 提取完毕"

if [ ${baserom_type} = 'payload' ];then

    blue "开始分解底包 [payload.bin]"
    payload-dumper-go -o build/baserom/images/ build/baserom/payload.bin >/dev/null 2>&1 ||error "分解底包 [payload.bin] 时出错"
else
    blue "开始分解底包 [new.dat.br]"
        for i in ${super_list}; do
            ${tools_dir}/brotli -d build/baserom/$i.new.dat.br >/dev/null 2>&1
            sudo python3 ${tools_dir}/sdat2img.py build/baserom/$i.transfer.list build/baserom/$i.new.dat build/baserom/images/$i.img >/dev/null 2>&1
            rm -rf $i.new.data.* $i.transfer.list $i.patch.*
        done
fi

for part in system system_dlkm system_ext product product_dlkm mi_ext ;do
    if [[ -f build/baserom/images/${part}.img ]];then 
        if [[ $($tools_dir/gettype -i build/baserom/images/${part}.img) == "ext" ]];then
            pack_type=EXT
            blue "正在分解底包 ${part}.img [ext]"
            sudo python3 bin/imgextractor/imgextractor.py build/baserom/images/${part}.img >/dev/null 2>&1
            blue "分解底包 [${part}.img] 完成"
            mv ${part} build/baserom/images/
            
        elif [[ $($tools_dir/gettype -i build/baserom/images/${part}.img) == "erofs" ]]; then
            pack_type=EROFS
            blue "正在分解底包 ${part}.img [erofs]"
            extract.erofs -x -i build/baserom/images/${part}.img  > /dev/null 2>&1 || error "分解 ${part}.img 失败"
                blue "分解底包 [${part}.img][ext] 完成"
            mv ${part} build/baserom/images/
            
        fi
        mv config/*${part}* build/baserom/config/
    fi
    
done

for image in vendor odm vendor_dlkm odm_dlkm;do
    if [ -f build/baserom/images/${image}.img ];then
        cp -rf build/baserom/images/${image}.img build/portrom/images/${image}.img
    fi
done

# 分解镜像
green 开始提取逻辑分区镜像

for part in ${super_list};do
    if [[ $part =~ ^(vendor|odm|vendor_dlkm|odm_dlkm)$ ]] && [[ -f "build/portrom/images/$part.img" ]]; then
        blue "从底包中提取 [${part}]分区 ..."
        blue "Extracting [${part}] from baserom"
    else
        blue "payload.bin 提取 [${part}] 分区..."
        blue "Extracting [${part}] from payload.bin"
        payload-dumper-go -p ${part} -o build/portrom/images/ build/portrom/payload.bin >/dev/null 2>&1 ||error "提取移植包 [${part}] 分区时出错"
    fi
    if [ -f "${work_dir}/build/portrom/images/${part}.img" ];then
        blue 开始提取 ${part}.img
        
        if [[ $($tools_dir/gettype -i build/portrom/images/${part}.img) == "ext" ]];then
            pack_type=EXT
            python3 bin/imgextractor/imgextractor.py build/portrom/images/${part}.img > /dev/null 2>&1 || error "提取${part}失败"
            mv ${part} build/portrom/images/
            mkdir -p build/portrom/images/${part}/lost+found
            mv config/*${part}* build/portrom/config/
            
            rm -rf build/portrom/images/${part}.img

            green "提取 [${part}] [ext]镜像完毕"
        elif [[ $(gettype -i build/portrom/images/${part}.img) == "erofs" ]];then
            pack_type=EROFS
            green "移植包为 [erofs] 文件系统"
            [ "${repackext4}" = "true" ] && pack_type=EXT
            extract.erofs -x -i build/portrom/images/${part}.img  > /dev/null 2>&1 || error "提取${part}失败"
            mv ${part} build/portrom/images/
            mkdir -p build/portrom/images/${part}/lost+found
            mv config/*${part}* build/portrom/config/
            rm -rf build/portrom/images/${part}.img

            green "提取移植包[${part}] [erofs]镜像完毕"
        fi
        
    fi
done
rm -rf config


# 获取ROM参数

blue "正在获取ROM参数"
# 安卓版本
base_android_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.incremental" |awk 'NR==1' |cut -d '=' -f 2)

#HyperOS版本号获取
port_mios_version_incremental=$(< build/portrom/images/mi_ext/etc/build.prop grep "ro.mi.os.version.incremental" | awk 'NR==1' | cut -d '=' -f 2)
#替换机型代号,比如小米10：UNBCNXM -> UJBCNXM

port_device_code=$(echo $port_mios_version_incremental | cut -d "." -f 5)

if [[ $port_mios_version_incremental == *DEV* ]];then
    yellow "Dev deteced,skip replacing codename"
    port_rom_version=$(echo $port_mios_version_incremental)
else
    base_device_code=U$(echo $base_rom_version | cut -d "." -f 5 | cut -c 2-)
    port_rom_version=$(echo $port_mios_version_incremental | sed "s/$port_device_code/$base_device_code/")
fi
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]"

# MIUI版本
base_miui_version=$(< build/baserom/images/product/etc/build.prop grep "ro.miui.ui.version.code" |awk 'NR==1' |cut -d '=' -f 2)
port_miui_version=$(< build/portrom/images/product/etc/build.prop grep "ro.miui.ui.version.code" |awk 'NR==1' |cut -d '=' -f 2)

green "MIUI版本: 底包为 [${base_miui_version}], 移植包为 [${port_miui_version}]"


# 代号
base_rom_code=$(< build/portrom/images/vendor/build.prop grep "ro.product.vendor.device" |awk 'NR==1' |cut -d '=' -f 2)
port_rom_code=$(< build/portrom/images/product/etc/build.prop grep "ro.product.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]"



baseAospFrameworkResOverlay=$(find build/baserom/images/product -type f -name "AospFrameworkResOverlay.apk")
portAospFrameworkResOverlay=$(find build/portrom/images/product -type f -name "AospFrameworkResOverlay.apk")
if [ -f "${baseAospFrameworkResOverlay}" ] && [ -f "${portAospFrameworkResOverlay}" ];then
    blue "正在替换 [AospFrameworkResOverlay.apk]"
    cp -rf ${baseAospFrameworkResOverlay} ${portAospFrameworkResOverlay}
fi


#baseMiuiFrameworkResOverlay=$(find build/baserom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
#portMiuiFrameworkResOverlay=$(find build/portrom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
#if [ -f ${baseMiuiFrameworkResOverlay} ] && [ -f ${portMiuiFrameworkResOverlay} ];then
#    blue "正在替换 [MiuiFrameworkResOverlay.apk]"
#    cp -rf ${baseMiuiFrameworkResOverlay} ${portMiuiFrameworkResOverlay}
#fi

#baseAospWifiResOverlay=$(find build/baserom/images/product -type f -name "AospWifiResOverlay.apk")
##portAospWifiResOverlay=$(find build/portrom/images/product -type f -name "AospWifiResOverlay.apk")
#if [ -f ${baseAospWifiResOverlay} ] && [ -f ${portAospWifiResOverlay} ];then
#    blue "正在替换 [AospWifiResOverlay.apk]"
#    cp -rf ${baseAospWifiResOverlay} ${portAospWifiResOverlay}
#fi

baseDevicesAndroidOverlay=$(find build/baserom/images/product -type f -name "DevicesAndroidOverlay.apk")
portDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [ -f "${baseDevicesAndroidOverlay}" ] && [ -f "${portDevicesAndroidOverlay}" ];then
    blue "正在替换 [DevicesAndroidOverlay.apk]"
    cp -rf ${baseDevicesAndroidOverlay} ${portDevicesAndroidOverlay}
fi

baseDevicesOverlay=$(find build/baserom/images/product -type f -name "DevicesOverlay.apk")
portDevicesOverlay=$(find build/portrom/images/product -type f -name "DevicesOverlay.apk")
if [ -f "${baseDevicesOverlay}" ] && [ -f "${portDevicesOverlay}" ];then
    blue "正在替换 [DevicesOverlay.apk]"
    cp -rf ${baseDevicesOverlay} ${portDevicesOverlay}
fi

baseMiuiBiometricResOverlay=$(find build/baserom/images/product -type f -name "MiuiBiometricResOverlay.apk")
portMiuiBiometricResOverlay=$(find build/portrom/images/product -type f -name "MiuiBiometricResOverlay.apk")
if [ -f "${baseMiuiBiometricResOverlay}" ] && [ -f "${portMiuiBiometricResOverlay}" ];then
    blue "正在替换 [MiuiBiometricResOverlay.apk]"
    cp -rf ${baseMiuiBiometricResOverlay} ${portMiuiBiometricResOverlay}
fi

# radio lib
# blue "信号相关"
# for radiolib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*radio*");do
#     cp -rf $radiolib build/portrom/images/system/system/lib/
# done

# for radiolib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*radio*");do
#     cp -rf $radiolib build/portrom/images/system/system/lib64/
# done


# audio lib
# blue "音频相关"
# for audiolib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*audio*");do
#     cp -rf $audiolib build/portrom/images/system/system/lib/
# done

# for audiolib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*audio*");do
#     cp -rf $audiolib build/portrom/images/system/system/lib64/
# done

# # bt lib
# blue "蓝牙相关"
# for btlib in $(find build/baserom/images/system/system/lib/ -maxdepth 1 -type f -name "*bluetooth*");do
#     cp -rf $btlib build/portrom/images/system/system/lib/
# done

# for btlib in $(find build/baserom/images/system/system/lib64/ -maxdepth 1 -type f -name "*bluetooth*");do
#     cp -rf $btlib build/portrom/images/system/system/lib64/
# done


# displayconfig id
for display_id_file in $(find build/baserom/images/product/etc/displayconfig/ -type f -name "display_id*.xml");do
    display_id=$(basename $display_id_file)
    blue "Copying display_id $display_id to PortROM"
    cp -rf $(ls -1 build/portrom/images/product/etc/displayconfig/display_id_*.xml | head -n 1) build/portrom/images/product/etc/displayconfig/$display_id 
done

# device_features
blue "Copying device_features"   
rm -rf build/portrom/images/product/etc/device_features/*
cp -rf build/baserom/images/product/etc/device_features/* build/portrom/images/product/etc/device_features/


# MiSound
#baseMiSound=$(find build/baserom/images/product -type d -name "MiSound")
#portMiSound=$(find build/baserom/images/product -type d -name "MiSound")
#if [ -d ${baseMiSound} ] && [ -d ${portMiSound} ];then
#    blue "正在替换 MiSound"
 #   rm -rf ./${portMiSound}/*
 #   cp -rf ./${baseMiSound}/* ${portMiSound}/
#fi

# MusicFX
#baseMusicFX=$(find build/baserom/images/product build/baserom/images/system -type d -name "MusicFX")
#portMusicFX=$(find build/baserom/images/product build/baserom/images/system -type d -name "MusicFX")
#if [ -d ${baseMusicFX} ] && [ -d ${portMusicFX} ];then
#    blue "正在替换 MusicFX"
##    rm -rf ./${portMusicFX}/*
 #   cp -rf ./${baseMusicFX}/* ${portMusicFX}/
#fi

# 人脸
baseMiuiBiometric=$(find build/baserom/images/product/app -type d -name "MiuiBiometric*")
portMiuiBiometric=$(find build/portrom/images/product/app -type d -name "MiuiBiometric*")
if [ -d "${baseMiuiBiometric}" ] && [ -d "${portMiuiBiometric}" ];then
    yellow "Searching and Replacing MiuiBiometric.."
    rm -rf ./${portMiuiBiometric}/*
    cp -rf ./${baseMiuiBiometric}/* ${portMiuiBiometric}/
else
    if [ -d "${baseMiuiBiometric}" ] && [ ! -d "${portMiuiBiometric}" ];then
        blue "MiuiBiometric is missing, copying from base..."
        cp -rf ${baseMiuiBiometric} build/portrom/images/product/app/
    fi
fi


# 修复AOD问题
targetDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [[ -f $targetDevicesAndroidOverlay ]]; then
    mkdir tmp/  
    filename=$(basename $targetDevicesAndroidOverlay)
    yellow "Fixing AOD issue: $filename ..."
    targetDir=$(echo "$filename" | sed 's/\..*$//')
    bin/apktool/apktool d $targetDevicesAndroidOverlay -o tmp/$targetDir -f > /dev/null 2>&1
    search_pattern="com\.miui\.aod\/com\.miui\.aod\.doze\.DozeService"
    replacement_pattern="com\.android\.systemui\/com\.android\.systemui\.doze\.DozeService"
    for xml in $(find tmp/$targetDir -type f -name "*.xml");do
        sed -i "s/$search_pattern/$replacement_pattern/g" $xml
    done
    bin/apktool/apktool b tmp/$targetDir -o tmp/$filename > /dev/null 2>&1 || error "apktool 打包失败"
    yellow "$targetDevicesAndroidOverlay"
    cp -rf tmp/$filename $targetDevicesAndroidOverlay
    rm -rf tmp
fi



# 修复NFC
blue "正在修复/替换 NFC"
yellow "TODO"

#其他机型可能没有default.prop
for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
baseVndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
portVndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${portVndk}" ]; then
    yellow "target apex is missing, copying from baserom"
    cp -rf "${baseVndk}" "build/portrom/images/system_ext/apex/"
fi

#解决开机报错问题
targetVintf=$(find build/portrom/images/system_ext/etc/vintf -type f -name "manifest.xml")
if [ -f "$targetVintf" ]; then
    # Check if the file contains $vndk_version
    if grep -q "<version>$vndk_version</version>" "$targetVintf"; then
        echo "The file already contains the version $vndk_version. Skipping modification."
    else
        # If it doesn't contain $vndk_version, then add it
        ndk_version="<vendor-ndk>\n     <version>$vndk_version</version>\n </vendor-ndk>"
        sed -i "/<\/vendor-ndk>/a$ndk_version" "$targetVintf"
        echo "Version $vndk_version added to $targetVintf"
    fi
else
    echo "File $targetVintf not found."
fi
blue "左侧挖孔灵动岛修复"
patch_smali "MiuiSystemUI.apk" "MIUIStrongToast\$2.smali" "const\/4 v10\, 0x0" "iget-object v10\, v1\, Lcom\/android\/systemui\/toast\/MIUIStrongToast;->mRLLeft:Landroid\/widget\/RelativeLayout;\\n\\tinvoke-virtual {v10}, Landroid\/widget\/RelativeLayout;->getLeft()I\\n\\tmove-result v10\\n\\tint-to-float v10,v10"

#blue "不优雅的方案解决开机软重启问题"
#fixme 
#patch_smali "miui-services.jar" "HysteresisLevelsImpl.smali" "iget v\([0-9]\), v\([0-9]\), Lcom\/android\/server\/display\/DisplayDeviceConfig\$HighBrightnessModeData;->minimumLux:F" "const\/high16 v\1, 0x3f800000"

blue "去除安卓14应用签名限制"
patch_smali "framework.jar" "ApkSignatureVerifier.smali" "const\/4 v0, 0x2" "const\/4 v0, 0x1" 
# 修复软重启

# 主题防恢复
if [ -f build/portrom/images/system/system/etc/init/hw/init.rc ];then
	sed -i '/on boot/a\'$'\n''    chmod 0731 \/data\/system\/theme' build/portrom/images/system/system/etc/init/hw/init.rc
fi

# 删除多余的App
rm -rf build/portrom/images/product/app/MSA
rm -rf build/portrom/images/product/priv-app/MSA
rm -rf build/portrom/images/product/app/mab
rm -rf build/portrom/images/product/priv-app/mab
rm -rf build/portrom/images/product/app/Updater
rm -rf build/portrom/images/product/priv-app/Updater
rm -rf build/portrom/images/product/app/MiuiUpdater
rm -rf build/portrom/images/product/priv-app/MiuiUpdater
rm -rf build/portrom/images/product/app/MIUIUpdater
rm -rf build/portrom/images/product/priv-app/MIUIUpdater
rm -rf build/portrom/images/product/app/MiService
rm -rf build/portrom/images/product/app/MIService
rm -rf build/portrom/images/product/app/SoterService
rm -rf build/portrom/images/product/priv-app/MiService
rm -rf build/portrom/images/product/priv-app/MIService
rm -rf build/portrom/images/product/app/*Hybrid*
rm -rf build/portrom/images/product/priv-app/*Hybrid*
rm -rf build/portrom/images/product/etc/auto-install*
rm -rf build/portrom/images/product/app/AnalyticsCore/*
rm -rf build/portrom/images/product/priv-app/AnalyticsCore/*
rm -rf build/portrom/images/product/data-app/*GalleryLockscreen* >/dev/null 2>&1
mkdir -p app
mv build/portrom/images/product/data-app/*Weather* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*DeskClock* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*Gallery* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*SoundRecorder* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*ScreenRecorder* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*Calculator* app/ >/dev/null 2>&1
mv build/portrom/images/product/data-app/*Calendar* app/ >/dev/null 2>&1
rm -rf build/portrom/images/product/data-app/*
cp -rf app/* build/portrom/images/product/data-app
rm -rf app

rm -rf build/portrom/images/system/verity_key
rm -rf build/portrom/images/vendor/verity_key
rm -rf build/portrom/images/product/verity_key
rm -rf build/portrom/images/system/recovery-from-boot.p
rm -rf build/portrom/images/vendor/recovery-from-boot.p
rm -rf build/portrom/images/product/recovery-from-boot.p
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/com.google.android.apps.nbu*
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/dynamic/com.google.android.apps.nbu*

# build.prop 修改
blue "正在修改 build.prop"
#
#change the locale to English
export LC_ALL=en_US.UTF-8
buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}"
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
    sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}/g" ${i}
    #全局替换device_code
    if [[ $port_mios_version_incremental != *DEV* ]];then
        sed -i "s/$port_device_code/$base_device_code/g" ${i}
    fi
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    sed -i "s/ro.build.host=.*/ro.build.host=${build_host}/g" ${i}
    
done

#sed -i -e '$a\'$'\n''persist.adb.notify=0' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.usb.config=mtp,adb' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.disable_rescue=true' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.miui.extm.enable=0' build/portrom/images/system/system/build.prop


# 屏幕密度修修改
for prop in $(find build/baserom/images/product build/baserom/images/system -type f -name "build.prop");do
    base_rom_density=$(< "$prop" grep "ro.sf.lcd_density" |awk 'NR==1' |cut -d '=' -f 2)
    if [ "${base_rom_density}" != "" ];then
        green "底包屏幕密度值 ${base_rom_density}"
        break 
    fi
done

# 未在底包找到则默认440,如果是其他值可自己修改
[ -z ${base_rom_density} ] && base_rom_density=440

found=0
for prop in $(find build/portrom/images/product build/portrom/images/system -type f -name "build.prop");do
    if grep -q "ro.sf.lcd_density" ${prop};then
        blue "找到ro.fs.lcd_density，替换值为$base_rom_density" 
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" ${prop}
        found=1
    fi
    sed -i "s/persist.miui.density_v2=.*/persist.miui.density_v2=${base_rom_density}/g" ${prop}
done

if [ $found -eq 0  ]; then
        blue "未找到ro.fs.lcd_density，build.prop新建一个值$base_rom_density"
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
echo "ro.millet.netlink=29" >> build/portrom/images/vendor/build.prop

#Fix：Fingerprint issue encountered on OS V1.0.18
echo "vendor.perf.framepacing.enable=false" >> build/portrom/images/vendor/build.prop

#自定义替换
#Devices/机型代码/overaly 按照镜像的目录结构，可直接替换目标。
if [[ -d "devices/${base_rom_code}/overlay" ]]; then
    #targetNFCFolder=$(find build/portrom/images/system/system build/portrom/images/product build/portrom/images/system_ext -type d -name "NQNfcNci*")
    targetCamera=$(find build/portrom/images/system/system build/portrom/images/product build/portrom/images/system_ext -type d -name "MiuiCamera")
    rm -rf $targetCamera
    cp -rfv devices/${base_rom_code}/overlay/* build/portrom/images/
else
    yellow "devices/${base_rom_code}/overlay 未找到"
fi

#添加erofs文件系统fstab
if [ ${pack_type} == "EROFS" ];then
    yellow "检查 vendor fstab.com是否需要添加erofs挂载点"
    if ! grep -q "erofs" build/portrom/images/vendor/etc/fstab.default ; then
               for pname in system odm vendor product mi_ext system_ext; do
                     sed -i "/\/${pname}[[:space:]]\+ext4/{p;s/ext4/erofs/;}" build/portrom/images/vendor/etc/fstab.default
                     added_line=$(sed -n "/\/${pname}[[:space:]]\+erofs/p" build/portrom/images/vendor/etc/fstab.default)
    
                    if [ -n "$added_line" ]; then
                        yellow "添加$pname"
                    else
                        error "添加失败，请检查"
                        exit 1
                        
                    fi
                done
    fi
fi

# 去除avb校验
blue "去除avb校验"
for fstab in $(find build/portrom/images/ -type f -name "fstab.*");do
    blue "Target: $fstab"
    sed -i "s/,avb_keys=.*avbpubkey//g" $fstab
    sed -i "s/,avb=vbmeta_system//g" $fstab
    sed -i "s/,avb=vbmeta_vendor//g" $fstab
    sed -i "s/,avb=vbmeta//g" $fstab
    sed -i "s/,avb//g" $fstab
done

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
		sed -i "s/fileencryption/encryptable/g" $fstab
		sed -i "s/,fileencryption=ice//g" $fstab
	done
fi

for pname in ${port_partition};do
    rm -rf build/portrom/images/${pname}.img
done
echo "${pack_type}">fstype.txt
superSize=$(bash bin/getSuperSize.sh $device_code)
green "Super大小为${superSize}"
green 开始打包镜像
for pname in ${super_list};do
    if [ -d "build/portrom/images/$pname" ];then
        if [[ "$OSTYPE" == "darwin"* ]];then
            thisSize=$(find build/portrom/images/${pname} | xargs stat -f%z | awk ' {s+=$1} END { print s }' )
        else
            thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        fi
        case $pname in
            mi_ext) addSize=4194304 ;;
            odm) addSize=134217728 ;;
            system|vendor|system_ext) addSize=154217728 ;;
            product) addSize=204217728 ;;
            *) addSize=8554432 ;;
        esac
        if [ "$pack_type" = "EXT" ];then
            blue "$pname"为EXT4文件系统多分配大小$addSize
            for fstab in $(find build/portrom/images/${pname}/ -type f -name "fstab.*");do
                #sed -i '/overlay/d' $fstab
                sed -i '/system * erofs/d' $fstab
                sed -i '/system_ext * erofs/d' $fstab
                sed -i '/vendor * erofs/d' $fstab
                sed -i '/product * erofs/d' $fstab
            done
            thisSize=$(echo "$thisSize + $addSize" |bc)
            blue 以[$pack_type]文件系统打包[${pname}.img]大小[$thisSize]
            python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/config/${pname}_fs_config
            python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/config/${pname}_file_contexts
            make_ext4fs -J -T $(date +%s) -S build/portrom/config/${pname}_file_contexts -l $thisSize -C build/portrom/config/${pname}_fs_config -L ${pname} -a ${pname} build/portrom/images/${pname}.img build/portrom/images/${pname}

            if [ -f "build/portrom/images/${pname}.img" ];then
                green "成功以大小 [$thisSize] 打包 [${pname}.img] [${pack_type}] 文件系统"
                #rm -rf build/baserom/images/${pname}
            else
                error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败"
            fi
        else
            
                blue 以[$pack_type]文件系统打包[${pname}.img]
                python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/config/${pname}_fs_config
                python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/config/${pname}_file_contexts
                #sudo perl -pi -e 's/\\@/@/g' build/portrom/config/${pname}_file_contexts
                mkfs.erofs --mount-point ${pname} --fs-config-file build/portrom/config/${pname}_fs_config --file-contexts build/portrom/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}
                if [ -f "build/portrom/images/${pname}.img" ];then
                    green "成功以 [erofs] 文件系统打包 [${pname}.img]"
                    #rm -rf build/portrom/images/${pname}
                else
                    error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败"
                    exit 1
                fi
        fi
        unset fsType
        unset thisSize
    fi
done
rm fstype.txt

# 打包 super.img

if [ "${baserom_type}" = "br" ];then
    blue "打包A-only super.img"
    lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor;do
        if [ -f "build/portrom/images/${pname}.img" ];then
            if [[ "$OSTYPE" == "darwin"* ]];then
               subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
            else
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            fi
            green Super 子分区 [$pname] 大小 [$subsize]
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
else
    blue "打包V-A/B机型 super.img"
    lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

    for pname in ${super_list};do
        if [ -f "build/portrom/images/${pname}.img" ];then
            subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            green Super 子分区 [$pname] 大小 [$subsize]
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
    green 成功打包 super.img
else
    error 无法打包 super.img
    exit 1
fi
for pname in ${super_list};do
    rm -rf build/portrom/images/${pname}.img
done

blue "正在压缩 super.img"
zstd --rm build/portrom/images/super.img -o build/portrom/images/super.zst




mkdir -p out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/

blue "正在生成刷机脚本"
if [ "${baserom_type}" = "br" ];then

    mv -f build/portrom/images/super.zst out/hyperos_${device_code}_${port_rom_version}/
    #firmware
    if [ -d build/baserom/firmware-update ];then
        mkdir -p out/hyperos_${device_code}_${port_rom_version}/firmware-update
        cp -rf build/baserom/firmware-update/*  out/hyperos_${device_code}_${port_rom_version}/firmware-update
    fi
        # disable vbmeta
    for img in $(find out/hyperos_${device_code}_${port_rom_version}/firmware-update -type f -name "vbmeta*.img");do
        python3 bin/patch-vbmeta.py ${img}
    done
    mv -f build/baserom/boot.img out/hyperos_${device_code}_${port_rom_version}/boot_official.img
    cp -rf bin/flash/a-only/update-binary out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/
    cp -rf bin/flash/zstd out/hyperos_${device_code}_${port_rom_version}/META-INF/
    cp devices/$base_rom_code/boot_tv.img out/hyperos_${device_code}_${port_rom_version}/
    sed -i "s/portversion/${port_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary

else
    mkdir -p out/hyperos_${device_code}_${port_rom_version}/images/
    mv -f build/portrom/images/super.zst out/hyperos_${device_code}_${port_rom_version}/images/
    cp -rf bin/flash/vab/update-binary out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/
    cp -rf bin/flash/vab/platform-tools-windows out/hyperos_${device_code}_${port_rom_version}/META-INF/
    cp -rf bin/flash/vab/flash_update.bat out/hyperos_${device_code}_${port_rom_version}/
    cp -rf bin/flash/vab/flash_and_format.bat out/hyperos_${device_code}_${port_rom_version}/
   
    cp -rf bin/flash/zstd out/hyperos_${device_code}_${port_rom_version}/META-INF/
    for fwImg in $(ls out/hyperos_${device_code}_${port_rom_version}/images/ |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
        if [ "$(echo $fwImg |grep vbmeta)" != "" ];then
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot --disable-verity --disable-verification flash "$fwImg"_b images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_update.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot --disable-verity --disable-verification flash "$fwImg"_a images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_update.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot --disable-verity --disable-verification flash "$fwImg"_b images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_and_format.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot --disable-verity --disable-verification flash "$fwImg"_a images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_and_format.bat
            sed -i "/#firmware/a package_extract_file \"images/"$fwImg".img\" \"/dev/block/bootdevice/by-name/"$fwImg"_b\"" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
            sed -i "/#firmware/a package_extract_file \"images/"$fwImg".img\" \"/dev/block/bootdevice/by-name/"$fwImg"_a\"" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        else
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot flash "$fwImg"_b images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_update.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot flash "$fwImg"_a images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_update.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot flash "$fwImg"_b images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_and_format.bat
            sed -i "/rem/a META-INF\\\platform-tools-windows\\\fastboot flash "$fwImg"_a images\/"$fwImg".img" out/hyperos_${device_code}_${port_rom_version}/flash_and_format.bat
            sed -i "/#firmware/a package_extract_file \"images/"$fwImg".img\" \"/dev/block/bootdevice/by-name/"$fwImg"_b\"" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
            sed -i "/#firmware/a package_extract_file \"images/"$fwImg".img\" \"/dev/block/bootdevice/by-name/"$fwImg"_a\"" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        fi
    done

    sed -i "s/portversion/${port_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary

    busybox unix2dos out/hyperos_${device_code}_${port_rom_version}/flash_update.bat
    busybox unix2dos out/hyperos_${device_code}_${port_rom_version}/flash_and_format.bat

fi

find out/hyperos_${device_code}_${port_rom_version} |xargs touch
pushd out/hyperos_${device_code}_${port_rom_version}/ >/dev/null || exit
zip -r hyperos_${device_code}_${port_rom_version}.zip ./*
mv hyperos_${device_code}_${port_rom_version}.zip ../
popd >/dev/null || exit

hash=$(md5sum out/hyperos_${device_code}_${port_rom_version}.zip |head -c 10)
mv out/hyperos_${device_code}_${port_rom_version}.zip out/hyperos_${device_code}_${port_rom_version}_${hash}_${port_android_version}_ROOT_${pack_type}.zip
green "移植完毕"    
green "输出包为 $(pwd)/hyperos_${device_code}_${port_rom_version}_${hash}_${port_android_version}_ROOT_${pack_type}.zip"
