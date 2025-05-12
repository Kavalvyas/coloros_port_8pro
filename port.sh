#!/bin/bash

# ColorOS_port project

# For A-only and V/A-B (not tested) Devices

# Based on Android 14 

# Test Base ROM: OnePlus 8T (ColorOS_14.0.0.600)

# Test Port ROM: OnePlus 12 (ColorOS_14.0.0.810), OnePlus ACE3V(ColorOS_14.0.1.621) Realme GT Neo5 240W(RMX3708_14.0.0.800)

build_user="Bruce Teng"
build_host=$(hostname)

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$(pwd)/otatools/bin/:$PATH

# Import functions
source functions.sh

check unzip aria2c 7z zip java python3 zstd bc xmlstarlet

# 可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
super_list=$(grep "possible_super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
super_extended=$(grep "super_extended" bin/port_config |cut -d '=' -f 2)
pack_method=$(grep "pack_method" bin/port_config | cut -d '=' -f 2)
if [[ ${repackext4} == true ]]; then
    pack_type=EXT
else
    pack_type=EROFS
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

if [ "$(echo $baserom |grep ColorOS_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="op8t"
fi

blue "正在检测ROM底包" "Validating BASEROM.."
if unzip -l ${baserom} | grep -q "payload.bin"; then
    baserom_type="payload"
elif unzip -l ${baserom} | grep -q "br$";then
    baserom_type="br"
else
    error "底包中未发现payload.bin以及br文件，请使用ColorOS官方包后重试" "payload.bin/new.br not found, please use  ColorOS official OTA zip package."
    exit
fi

blue "开始检测ROM移植包" "Validating PORTROM.."
if unzip -l ${portrom} | grep  -q "payload.bin"; then
    green "ROM初步检测通过" "ROM validation passed."
else
    error "目标移植包没有payload.bin，请用MIUI官方包作为移植包" "payload.bin not found, please use ColorOS official OTA zip package."
fi

green "ROM初步检测通过" "ROM validation passed."

blue "正在清理文件" "Cleaning up.."
for i in ${port_partition};do
    [ -d ./${i} ] && rm -rf ./${i}
done
rm -rf app
rm -rf tmp
rm -rf config
rm -rf build/baserom/
rm -rf build/portrom/
find . -type d -name 'ColorOS_*' |xargs rm -rf

green "文件清理完毕" "Files cleaned up."
mkdir -p build/baserom/images/

mkdir -p build/portrom/images/

mkdir tmp 
export TMPDIR=$work_dir/tmp/
# 提取分区
if [[ ${baserom_type} == 'payload' ]];then
    blue "正在提取底包 [payload.bin]" "Extracting files from BASEROM [payload.bin]"
    payload-dumper --out build/baserom/images/ $baserom
    green "底包 [payload.bin] 提取完毕" "[payload.bin] extracted."
elif [[ ${baserom_type} == 'br' ]];then
    blue "正在提取底包 [new.dat.br]" "Extracting files from BASEROM [*.new.dat.br]"
    unzip ${baserom} -d build/baserom  > /dev/null 2>&1 || error "解压底包 [new.dat.br]时出错" "Extracting [new.dat.br] error"
    green "底包 [new.dat.br] 提取完毕" "[new.dat.br] extracted."
    blue "开始分解底包 [new.dat.br]" "Unpacking BASEROM[new.dat.br]"
    for file in build/baserom/*; do
        filename=$(basename -- "$file")
        extension="${filename##*.}"
        name="${filename%.*}"

        if [[ $name =~ [0-9] ]];then
            new_name=$(echo "$name" | sed 's/[0-9]\+\(\.[^0-9]\+\)/\1/g')
            new_name=$(echo "$new_name" | sed 's/\.\./\./g')
            new_filename=$new_name.$extension

            mv -fv $file build/baserom/$new_filename 
        fi
    done
    for i in ${super_list}; do 
        ${tools_dir}/brotli -d build/baserom/$i.new.dat.br >/dev/null 2>&1
        python3 ${tools_dir}/sdat2img.py build/baserom/$i.transfer.list build/baserom/$i.new.dat build/baserom/images/$i.img >/dev/null 2>&1
        rm -rf build/baserom/$i.new.dat* build/baserom/$i.transfer.list build/baserom/$i.patch.*
    done
fi
blue "正在提取移植包 [payload.bin]" "Extracting files from PORTROM [payload.bin]"
	payload-dumper --partitions ${port_partition} --out build/portrom/images/ $portrom
    green "移植包 [payload.bin] img提取完毕" "[payload.bin] imgs extracted."



for part in system product system_ext my_product my_manifest ;do
    extract_partition build/baserom/images/${part}.img build/baserom/images    
done

# Move those to portrom folder. We need to pack those imgs into final port rom
for image in vendor odm my_company my_preload;do
    if [ -f build/baserom/images/${image}.img ];then
        mv -f build/baserom/images/${image}.img build/portrom/images/${image}.img

        # Extracting vendor at first, we need to determine which super parts to pack from Baserom fstab. 
        extract_partition build/portrom/images/${image}.img build/portrom/images/

    fi
done

# Extract the partitions list that need to pack into the super.img
#super_list=$(sed '/^#/d;/^\//d;/overlay/d;/^$/d;/\^loop/d' build/portrom/images/vendor/etc/fstab.qcom \
#                | awk '{ print $1}' | sort | uniq)

# 分解镜像
green "开始提取逻辑分区镜像" "Starting extract portrom partition from img"
for part in ${super_list};do
# Skip already extraced parts from BASEROM
    if [[ ! -d build/portrom/images/${part} ]]; then
        blue "提取 [${part}] 分区..." "Extracting [${part}]"

        #payload-dumper-go -p ${part} -o build/portrom/images/ build/portrom/payload.bin > /dev/null 2>&1 || error "提取移植包 [${part}] 分区时出错" "Extracting partition [${part}] error."
        extract_partition "${work_dir}/build/portrom/images/${part}.img" "${work_dir}/build/portrom/images/"
        rm -rf ${work_dir}/build/baserom/images/${part}.img
    else
        yellow "跳过从PORTORM提取分区[${part}]" "Skip extracting [${part}] from PORTROM"
    fi
done
rm -rf config

blue "正在获取ROM参数" "Fetching ROM build prop."

# 安卓版本
base_android_version=$(< build/baserom/images/system/system/build.prop grep "ro.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/baserom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(<  build/baserom/images/my_manifest/build.prop grep "ro.build.display.ota" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 2-)
port_rom_version=$(<  build/portrom/images/my_manifest/build.prop grep "ro.build.display.ota" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 2-)
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]" "ROM Version: BASEROM: [${base_rom_version}], PORTROM: [${port_rom_version}] "

#ColorOS版本号获取

base_device_code=$(< build/baserom/images/my_manifest/build.prop grep "ro.oplus.version.my_manifest" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 1)
port_device_code=$(< build/portrom/images/my_manifest/build.prop grep "ro.oplus.version.my_manifest" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 1)

green "机型代号: 底包为 [${base_device_code}], 移植包为 [${port_device_code}]" "Device Code: BASEROM: [${base_device_code}], PORTROM: [${port_device_code}]"
# 代号
base_product_device=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.device" |awk 'NR==1' |cut -d '=' -f 2)
port_product_device=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.device" |awk 'NR==1' |cut -d '=' -f 2)
green "Product机型: 底包为 [${base_product_device}], 移植包为 [${port_product_device}]" "Product Device: BASEROM: [${base_product_device}], PORTROM: [${port_product_device}]"

base_product_name=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.name" |awk 'NR==1' |cut -d '=' -f 2)
port_product_name=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "Product名称: 底包为 [${base_product_name}], 移植包为 [${port_product_name}]" "Product Name: BASEROM: [${base_product_name}], PORTROM: [${port_product_name}]"

base_product_model=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.model" |awk 'NR==1' |cut -d '=' -f 2)
port_product_model=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.model" |awk 'NR==1' |cut -d '=' -f 2)
green "Product型号: 底包为 [${base_product_model}], 移植包为 [${port_product_model}]" "Product Model: BASEROM: [${base_product_model}], PORTROM: [${port_product_model}]"

base_market_name=$(< build/portrom/images/odm/build.prop grep "ro.vendor.oplus.market.name" |awk 'NR==1' |cut -d '=' -f 2)
port_market_name=$(grep -r --include="*.prop"  --exclude-dir="odm" "ro.vendor.oplus.market.name" build/portrom/images/ | head -n 1 | awk "NR==1" | cut -d "=" -f2)

green "市场名称: 底包为 [${base_market_name}], 移植包为 [${port_market_name}]" "Market Name: BASEROM: [${base_market_name}], PORTROM: [${port_market_name}]"

base_my_product_type=$(< build/baserom/images/my_product/build.prop grep "ro.oplus.image.my_product.type" |awk 'NR==1' |cut -d '=' -f 2)
port_my_product_type=$(< build/portrom/images/my_product/build.prop grep "ro.oplus.image.my_product.type" |awk 'NR==1' |cut -d '=' -f 2)

green "my_product类型: 底包为 [${base_my_product_type}], 移植包为 [${port_my_product_type}]" "My_Product Type: BASEROM: [${base_my_product_type}], PORTROM: [${port_my_product_type}]"

target_display_id=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.display.id" |awk 'NR==1' |cut -d '=' -f 2 | sed "s/$port_device_code/$base_device_code/g")

target_display_id_show=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.display.id.show" |awk 'NR==1' |cut -d '=' -f 2 | sed "s/$port_device_code/$base_device_code/g")

base_vendor_brand=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.vendor.brand" |awk 'NR==1' |cut -d '=' -f 2)
port_vendor_brand=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.vendor.brand" |awk 'NR==1' |cut -d '=' -f 2)

base_device_family=$(< build/baserom/images/my_product/build.prop grep "ro.build.device_family" |awk 'NR==1' |cut -d '=' -f 2)
target_device_family=$(< build/portrom/images/my_product/build.prop grep "ro.build.device_family" |awk 'NR==1' |cut -d '=' -f 2)

# Security Patch Date
portrom_version_security_patch=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.version.security_patch" |awk 'NR==1' |cut -d '=' -f 2 )
port_oplusrom_version=$(< build/portrom/images/my_product/build.prop grep "ro.build.version.oplusrom.confidential" |awk 'NR==1' |cut -d '=' -f 2 )

#regionmark=$(< build/portrom/images/my_bigball/etc/region/build.prop grep "ro.vendor.oplus.regionmark" |awk 'NR==1' |cut -d '=' -f 2)
regionmark=$(find build/portrom/images/ -name build.prop -exec grep -m1 "ro.vendor.oplus.regionmark=" {} \; -quit | cut -d '=' -f2)


if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi

if [[ ! -f build/portrom/images/system/system/bin/app_process32 ]]; then
    blue "64bit only protrom detected. Pathcing 32bit "
    sed -i "s/ro.system.product.cpu.abilist=.*/ro.system.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi/g" build/portrom/images/system/system/build.prop
    sed -i "s/ro.system.product.cpu.abilist32=.*/ro.system.product.cpu.abilist32=armeabi-v7a,armeabi/g" build/portrom/images/system/system/build.prop

    cp -rfv devices/32-libs/* build/portrom/images/
fi

if [[ -f devices/${base_product_device}/config ]];then
   source devices/${base_product_device}/config
fi
rm -rf build/portrom/images/my_manifest
cp -rf build/baserom/images/my_manifest build/portrom/images/
cp -rf build/baserom/images/config/my_manifest_* build/portrom/images/config/
#sed -i "s/ro.build.display.id=.*/ro.build.display.id=${target_display_id}/g" build/portrom/images/my_manifest/build.prop
sed -i "s/ro.build.display.id.show=.*/ro.build.display.id.show=${target_display_id_show}/g" build/portrom/images/my_manifest/build.prop
sed -i '/ro.build.version.release=/d' build/portrom/images/my_manifest/build.prop
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
sed -i "s/ro.build.version.security_patch=.*/ro.build.version.security_patch=${portrom_version_security_patch}/g" build/portrom/images/my_manifest/build.prop



old_face_unlock_app=$(find build/baserom/images/my_product -name "OPFaceUnlock.apk")
if [[ ! -d tmp ]];then
    mkdir -p tmp/
fi

 mkdir -p tmp/services/
 cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.jar
framework_res=$(find build/portrom/images/ -type f -name "framework-res.apk")
extra_args=""

if [[ -f $framework_res ]];then
    extra_args="-framework $framework_res"
fi

java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services 
smalis=("ScanPackageUtils")
methods=("--assertMinSignatureSchemeIsValid")

for (( i=0; i<${#smalis[@]}; i++ )); do
    smali="${smalis[i]}"
    method="${methods[i]}"
    
    target_file=$(find tmp/services -type f -name "${smali}.smali")
    echo "smali is $smali"
    echo "target_file is $target_file"
    if [[ -f $target_file ]]; then
        for single_method in $method; do
            python3 bin/patchmethod.py $target_file $single_method && echo "${target_file} patched successfully"
        done
    fi
done

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
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } && blue "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)
if [[ ${base_device_family} == "OPSM8250" ]] ; then
    blue "修复ColorOS15/OxygenOS15 人脸识解锁问题" "COS15/OOS15: Fix Face Unlock for SM8250"
    #pushd tmp/services
    #patch -p1 < ${work_dir}/devices/${base_product_device}/0001-face-unlock-fix-for-op8t.patch
    #popd
	if [[ -f devices/common/face_unlock_fix_common.zip ]];then
        rm -rf build/portrom/images/vendor/overlay/*
        unzip -o devices/common/face_unlock_fix_common.zip -d ${work_dir}/build/portrom/images/
        
    fi
	
    if [[ -f $old_face_unlock_app ]]; then
        unzip -o ${work_dir}/devices/${base_product_device}/face_unlock_fix.zip -d ${work_dir}/build/portrom/images/
        rm -rf build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal@1.0.so
        rm -rf build/portrom/images/odm/bin/hw/vendor.oneplus.faceunlock.hal@1.0-service
        rm -rf build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so
        rm -rf build/portrom/images/odm/etc/vintf/manifest/manifest_opfaceunlock.xml
        rm -rf build/portrom/images/odm/etc/init/vendor.oneplus.faceunlock.hal@1.0-service.rc
        rm -rf build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal@1.0.so
        rm -rf build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so


    fi
fi
java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o tmp/services_patched.jar > /dev/null 2>&1
cp -rf tmp/services_patched.jar build/portrom/images/system/system/framework/services.jar


if [[ ${base_android_version} == 13 ]] && [[ ${port_android_version} == 14 ]];then
    if [[ -f devices/common/a13_base_fix.zip ]];then
        unzip -o devices/common/a13_base_fix.zip -d ${work_dir}/build/portrom/images/
        rm -rfv build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger@1.0-service \
            build/portrom/images/odm/bin/hw/vendor.oplus.hardware.wifi@1.1-service \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.felica@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.midas@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.wifi@1.1-service-qcom.rc \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_charger.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_felica.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_midas.xml \
            build/portrom/images/odm/etc/vintf/manifest/oplus_wifi_service_device.xml \
            build/portrom/images/odm/framework/vendor.oplus.hardware.wifi-V1.1-java.jar \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0-impl.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.wifi@1.1.so \
            build/portrom/images/odm/overlay/CarrierConfigOverlay.*.apk
    fi
fi

if [[ ${port_android_version} == 15 ]];then

    if [[ ${base_device_family} == "OPSM8250" ]] && [[ ${base_android_version} != 13 ]] && [[ ${port_android_version} == 15 ]];then
        unzip -o devices/common/ril_fix_sm8250.zip -d ${work_dir}/build/portrom/images/
    elif [[ ${base_device_family} == "OPSM8350" ]];then
        unzip -o devices/common/ril_fix_sm8350.zip -d ${work_dir}/build/portrom/images/
        rm -rf build/portrom/images/odm/lib/libmindroid-app.so \
            build/portrom/images/odm/lib/libmindroid-framework.so \
            build/portrom/images/odm/lib/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib/vendor.oplus.hardware.subsys-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys-V1-ndk_platform.so
    fi

    if [[ ${base_android_version} == 14 ]]; then
    charger_v3=$(find build/portrom/images/odm/bin/hw/ -type f -name "vendor.oplus.hardware.charger-V3-service")
        if [[ -f $charger_v3 ]];then
        unzip -o devices/common/charger-v6-update.zip -d ${work_dir}/build/portrom/images/
        rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger-V3-service \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger-V3-service.rc \
            build/portrom/images/odm/lib/vendor.oplus.hardware.charger-V3-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.charger-V3-ndk_platform.so
        fi
    fi
fi

if [[ ${base_android_version} == 13 ]] && [[ ${port_android_version} == 15 ]];then
    #Ril Fix
    unzip -o devices/common/ril_fix_a13_to_a15.zip -d ${work_dir}/build/portrom/images/

    rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger@1.0-service \
        build/portrom/images/odm/bin/hw/vendor.oplus.hardware.wifi@1.1-service \
        build/portrom/images/odm/etc/init/vendor.oneplus.faceunlock.hal@1.0-service.rc \
        build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger@1.0-service.rc \
        build/portrom/images/odm/etc/init/vendor.oplus.hardware.felica@1.0-service.rc \
        build/portrom/images/odm/etc/init/vendor.oplus.hardware.midas@1.0-service.rc \
        build/portrom/images/odm/etc/init/vendor.oplus.hardware.wifi@1.1-service-qcom.rc \
        build/portrom/images/odm/etc/vintf/manifest/manifest_opfaceunlock.xml \
        build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_charger.xml \
        build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_cryptoeng_hidl.xml \
        build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_felica.xml \
        build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_midas.xml \
        build/portrom/images/odm/etc/vintf/manifest/oplus_wifi_service_device.xml \
        build/portrom/images/odm/framework/vendor.oplus.hardware.wifi-V1.1-java.jar \
        build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal@1.0.so \
        build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so \
        build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal@1.0.so \
        build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so \
        build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0-impl.so \
        build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0.so \
        build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
        build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys-V1-ndk_platform.so \
        build/portrom/images/odm/lib64/vendor.oplus.hardware.wifi@1.1.so
    #Nfc Fix
    unzip -o devices/common/nfc_fix_for_a13.zip -d ${work_dir}/build/portrom/images/
    rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.nfc@1.0-service \
        build/portrom/images/odm/etc/init/vendor.oplus.hardware.nfc@1.0-service.rc \
        build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_nfc.xml \
        build/portrom/images/odm/lib/vendor.oplus.hardware.nfc@1.0.so
    if [[ -d devices/common/a13_blobs_update ]];then
    # Fix Privacy related features(App lock、App hide)
        cp -rf devices/common/a13_blobs_update/odm/bin/hw/vendor.oplus.hardware.cryptoeng@1.0-service build/portrom/images/odm/bin/hw/
        cp -rf devices/common/a13_blobs_update/odm/lib64/vendor.oplus.hardware.commondcs-V1-ndk_platform.so build/portrom/images/odm/lib64
    fi
fi
yellow "删除多余的App" "Debloating..." 
# List of apps to be removed

debloat_apps=("HeartRateDetect")
#kept_apps=("Clock" "FileManager" "KeKeThemeSpace" "SogouInput" "Weather" "Calendar")
#kept_apps=("BackupAndRestore" "Calculator2" "Calendar" "Clock" "FileManager" "OppoNote2" "OppoWeather2" "UPTsmService" "Music")
kept_apps=()
if [[ $super_extended == "false" ]] && [[ $pack_method == "stock" ]] && [[ -f build/baserom/images/reserve.img ]]; then
    #extract_partition "${work_dir}/build/baserom/images/reserve.img" "${work_dir}/build/baserom/images/"
    #if [[ -f ext/del-app-ksu-module/system/product/app/* ]];then
    ##    rm -rf ext/del-app-ksu-module/system/product/app/*
    #fi
    #ext_moudle_app_folder="ext/del-app-ksu-module/system/product/app"
    for delapp in $(find build/portrom/images/ -maxdepth 3 -path "*/del-app/*" -type d);do
        
        app_name=$(basename "$delapp")

        # Check if the app is in kept_apps, skip if true
        if [[ " ${kept_apps[@]} " =~ " ${app_name} " ]]; then
            echo "Skipping kept app: $app_name"
        continue
        fi
        #mv -fv $delapp ${ext_moudle_app_folder}/
        rm -rfv $delapp 
    done 

elif [[ $super_extended == "false" ]] && [[ $base_product_model == "KB2000" ]];then
    for delapp in $(find build/portrom/images/ -maxdepth 3 -path "*/del-app/*" -type d ); do
        app_name=$(basename ${delapp})
        
        keep=false
        for kept_app in "${kept_apps[@]}"; do
            if [[ $app_name == *"$kept_app"* ]]; then
                keep=true
                break
            fi
        done
        
        if [[ $keep == false ]]; then
            debloat_apps+=("$app_name")
        fi

    done
    for debloat_app in "${debloat_apps[@]}"; do
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done
elif [[ $super_extended == "false" ]] && [[ $base_product_model == "KB200"* ]];then
    debloat_apps=("Facebook" "YTMusic" "GoogleHome" "Videos_del" "Drive_del" "ConsumerIRApp" "YouTube" "Gmail2" "Maps" "Wellbeing")
    for debloat_app in "${debloat_apps[@]}"; do
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done
    rm -rfv build/portrom/images/my_stock/del-app/*
elif [[ $super_extended == "false" ]] && [[ $base_product_model == "LE2101" ]];then
    debloat_apps=("Facebook" "YTMusic" "GoogleHome" "Videos_del" "Drive_del" "ConsumerIRApp" "YouTube" "Gmail2" "Maps")
for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rf "$app_dir"
    fi
done
  rm -rfv build/portrom/images/my_stock/del-app/*
fi
rm -rf build/portrom/images/product/etc/auto-install*
rm -rf build/portrom/images/system/verity_key
rm -rf build/portrom/images/vendor/verity_key
rm -rf build/portrom/images/product/verity_key
rm -rf build/portrom/images/system/recovery-from-boot.p
rm -rf build/portrom/images/vendor/recovery-from-boot.p
rm -rf build/portrom/images/product/recovery-from-boot.p

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
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    #全局替换device_code
    sed -i "s/$port_device_code/$base_device_code/g" ${i}
    sed -i "s/$port_product_model/$base_product_model/g" ${i}
    sed -i "s/$port_product_name/$base_product_name/g" ${i}
    sed -i "s/$port_my_product_type/$base_my_product_type/g" ${i}
    sed -i "s/$port_market_name/$base_market_name/g" ${i}
    sed -i "s/$port_product_device/$base_product_device/g" ${i}
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    sed -i "s/ro.build.display.id=.*/ro.build.display.id=${target_display_id}/g" ${i}
    sed -i "s/ro.oplus.radio.global_regionlock.enabled=.*/ro.oplus.radio.global_regionlock.enabled=false/g" ${i}
    sed -i "s/persist.sys.radio.global_regionlock.allcheck=.*/persist.sys.radio.global_regionlock.allcheck=false/g" ${i}
    sed -i "s/ro.oplus.radio.checkservice=.*/ro.oplus.radio.checkservice=false/g" ${i}
done

#sed -i -e '$a\'$'\n''persist.adb.notify=0' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.usb.config=mtp,adb' build/portrom/images/system/system/build.prop
#sed -i -e '$a\'$'\n''persist.sys.disable_rescue=true' build/portrom/images/system/system/build.prop

base_rom_density=$(grep "ro.sf.lcd_density" --include="*.prop" -r build/baserom/images/my_product | head -n 1 | cut -d "=" -f2)
[ -z ${base_rom_density} ] && base_rom_density=480

if grep -q "ro.sf.lcd_density" build/portrom/images/my_product/build.prop ;then
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" build/portrom/images/my_product/build.prop
else
        echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/my_product/build.prop
    fi

# fix bootloop
if [[ -f build/baserom/images/my_product/etc/extension/sys_game_manager_config.json ]];then
cp -rf build/baserom/images/my_product/etc/extension/sys_game_manager_config.json build/portrom/images/my_product/etc/extension/
else
    rm -rf build/portrom/images/my_product/etc/extension/sys_game_manager_config.json
fi

if [[ ! -f build/baserom/images/my_product/etc/extension/sys_graphic_enhancement_config.json ]];then
    rm -rf build/portrom/images/my_product/etc/extension/sys_graphic_enhancement_config.json
else
    cp -rf build/baserom/images/my_product/etc/extension/sys_graphic_enhancement_config.json build/portrom/images/my_product/etc/extension/
fi
if [[ $(cat build/baserom/images/my_product/build.prop | grep "ro.oplus.audio.effect.type" | cut -d "=" -f 2) == "dolby" ]] ;then
   blue "修复杜比音效+多应用音量调节 SM8250/SM8350" "Fix Dolby + App Specific volume adjustment for SM8250/SM8350"
    #cp $source_dolby_lib build/portrom/images/system_ext/lib64/
    #cp build/baserom/images/my_product/etc/permissions/oplus.product.features_dolby_stereo.xml build/portrom/images/my_product/etc/permissions/oplus.product.features_dolby_stereo.xml
    unzip -o devices/common/dolby_fix.zip -d build/portrom/images/ 
fi

# Fix wechat/whatsapp volume isue
cp -rf build/baserom/images/my_product/etc/audio*.xml build/portrom/images/my_product/etc/
cp -rf build/baserom/images/my_product/etc/default_volume_tables.xml build/portrom/images/my_product/etc/
if [[ -d build/baserom/images/my_product/etc/breenospeech2 ]];then
    cp -rf build/baserom/images/my_product/etc/breenospeech2/* build/portrom/images/my_product/etc/breenospeech2/
fi
rm -rf build/portrom/images/my_product/etc/fusionlight_profile/*
cp -rf build/baserom/images/my_product/etc/fusionlight_profile/*  build/portrom/images/my_product/etc/fusionlight_profile/
# Fix game audio issue on 15.0.2 (13t)
sed -i "/ro.oplus.audio.*/d" build/portrom/images/my_product/build.prop
remove_prop "persist.oplus.software.audio.right_volume_key"
remove_prop "persist.oplus.software.alertslider.location"

update_prop_from_base

sed -i "s/persist.sys.oplus.anim_level=.*/persist.sys.oplus.anim_level=1/g" build/portrom/images/my_product/build.prop

remove_prop "ro.oplus.resolution"
remove_prop "ro.oplus.display.wm_size_resolution_switch.support"
remove_prop "ro.density.screenzoom"
remove_prop "ro.oplus.resolution"
remove_prop "ro.oplus.density.qhd_default"
remove_prop "ro.oplus.density.fhd_default"
remove_prop "ro.oplus.key.actionbutton"
remove_prop "ro.oplus.audio.support.foldingmode"
remove_prop "ro.config.fold_disp"
remove_prop "persist.oplus.display.fold.support"
remove_prop "ro.oplus.haptic"
# OnePlus 8T: Fix OpSynergy crash 
remove_prop "persist.sys.oplus.wlan.atpc.qcom_use_iw"
cp -rf build/baserom/images/my_product/app/com.oplus.vulkanLayer build/portrom/images/my_product/app/
cp -rf build/baserom/images/my_product/app/com.oplus.gpudrivers.sm8250.api30 build/portrom/images/my_product/app/

   mkdir -p tmp/etc/permissions/
   mv -fv build/portrom/images/my_product/etc/permissions/* tmp/etc/permissions/
   cp -rf build/baserom/images/my_product/etc/permissions/*.xml build/portrom/images/my_product/etc/permissions/
   find tmp/etc/permissions/ -type f \( -name "multimedia*.xml" -o -name "*privapp*permissions*.xml" -o -name "*google*.xml" \) -exec cp -fv {} build/portrom/images/my_product/etc/permissions/ \;

if [[ $regionmark != "CN" ]];then
   sed -i "/com.android.contacts/d" build/portrom/images/my_stock/etc/config/app_v2.xml
   sed -i "/com.android.incallui/d" build/portrom/images/my_stock/etc/config/app_v2.xml
   sed -i "/com.android.mms/d" build/portrom/images/my_stock/etc/config/app_v2.xml
fi

cp -rf build/baserom/images/my_product/etc/permissions/*.xml build/portrom/images/my_product/etc/permissions/
cp -rf build/baserom/images/my_product/etc/extension/*.xml build/portrom/images/my_product/etc/extension/
cp -rf  build/baserom/images/my_product/etc/refresh_rate_config.xml build/portrom/images/my_product/etc/refresh_rate_config.xml
cp -rf  build/baserom/images/my_product/non_overlay build/portrom/images/my_product/non_overlay

cp -rf  build/baserom/images/my_product/etc/sys_resolution_switch_config.xml build/portrom/images/my_product/etc/sys_resolution_switch_config.xml

cp -rf build/baserom/images/my_product/etc/permissions/com.oplus.sensor_config.xml build/portrom/images/my_product/etc/permissions/
# add_feature "com.android.systemui.support_media_show" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature "oplus.software.support_blockable_animation" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

add_feature "oplus.software.support_quick_launchapp" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

#Reno 12 Feature 
add_feature 'os.personalization.wallpaper.live.ripple.enable" args="boolean:true' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "os.personalization.flip.agile_window.enable" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

#修复切换屏幕色彩模式软重启
remove_feature "oplus.software.display.wcg_2.0_support"

#echo "ro.surface_flinger.supports_background_blur=1" >> build/portrom/images/my_product/build.prop
#echo "ro.surface_flinger.media_panel_bg_blur=1" >> build/portrom/images/my_product/build.prop

add_feature 'com.coloros.colordirectservice.cm_enable" args="boolean:true' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature 'os.graphic.gallery.os15_secrecy" args="boolean:true' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature "oplus.software.support.zoom.multi_mode" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

add_feature "com.oplus.smartsidebar.space.roulette.support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.smartsidebar.space.roulette.bootreg" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.infocollection.screen.recognition" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

remove_feature "com.android.settings.processor_detail_gen2"
remove_feature "com.android.settings.processor_detail"
remove_feature "os.charge.settings.wirelesscharge.support"
remove_feature "com.oplus.battery.wireless.charging.notificate"
remove_feature "os.charge.settings.wirelesscharging.power"
remove_feature "os.charge.settings.wirelesschargingcoil.position"
remove_feature "oplus.power.onwirelesscharger.support"
remove_feature "os.charge.settings.batterysettings.batteryhealth"
cp -rf  build/baserom/images/my_product/vendor/etc/* build/portrom/images/my_product/vendor/etc/

 # Camera
cp -rf  build/baserom/images/my_product/etc/camera/* build/portrom/images/my_product/etc/camera

old_camera_app=$(find build/baserom/images/my_product -type f -name "OnePlusCamera.apk")
if [[ -f $old_camera_app ]];then
    cp -rfv $(dirname "$old_camera_app")* build/portrom/images/my_product/priv-app/
    if [ ! -d build/portrom/images/my_product/priv-app/etc/permissions/ ];then
        mkdir -p build/portrom/images/my_product/priv-app/etc/permissions/
    fi
    cp -rfv  build/baserom/images/my_product/priv-app/etc/permissions/*   build/portrom/images/my_product/priv-app/etc/permissions/
    new_camera=$(find build/portrom/images/my_product -type f -name "OplusCamera.apk")
    if [[ -f $new_camera ]]; then
        rm -rfv $(dirname $new_camera)
    fi
else
   echo "ro.vendor.oplus.camera.isSupportExplorer=1" >> build/portrom/images/my_product/build.prop
fi

base_oplus_camera_dir=$(find build/baserom/images/my_product -type d -name "OplusCamera")
port_oplus_camera_dir=$(find build/portrom/images/my_product -type d -name "OplusCamera")

if [[ -d "${base_oplus_camera_dir}" ]] && [[ -d "${port_oplus_camera_dir}" ]];then
    rm -rf "$port_oplus_camera_dir"/* 
    cp -rf "$base_oplus_camera_dir"/* "$port_oplus_camera_dir"/
    cp -rf build/baserom/images/my_product/product_overlay/framework/* build/portrom/images/my_product/product_overlay/framework/
else
  rm -rf build/portrom/images/my_product/product_overlay/framework/*
  cp -rf build/baserom/images/my_product/product_overlay/* build/portrom/images/my_product/product_overlay/
fi

base_scanner_app=$(find build/baserom/images/ -type d -name "OcrScanner")
target_scanner_app=$(find build/portrom/images/ -type d -name "OcrScanner")
if [[ -n $base_scanner_app ]] && [[ -n $target_scanner_app ]];then
    blue "替换原版扫一扫" "Replacing Stock OrcScanner"
    rm -rfv $target_scanner_app/*
    cp -rfv $base_scanner_app $target_scanner_app
fi

if [[ ${base_device_family} == "OPSM8250" ]]; then
  camera_optimize_file=$(find build/portrom/images/ -type f -name "sys_camera_optimize_config.xml")
  # Fix wechat /alipay scan crash issue
   if [[ -f $camera_optimize_file ]]; then
      rm -f $camera_optimize_file
   fi
fi
sourceOvoiceManagerService=$(find build/baserom/images/my_product -type d -name "OVoiceManagerService")
if [[ -d "$sourceOvoiceManagerService" ]];then
    targetOvoiceManagerService=$(find build/portrom/images/my_product -type d -name "OVoiceManagerService")
    if [[ -d "$targetOvoiceManagerService" ]];then
       # rm -rfv $targetOvoiceManagerService/* 
        cp -rfv $sourceOvoiceManagerService/* $targetOvoiceManagerService/
    else
        cp -rfv $sourceOvoiceManagerService build/portrom/images/my_product/priv-app/
    fi
fi

if [[ ${base_product_device} == "OnePlus8T" ]];then 
    # Voice_trigger for OnePlus 8T
    add_feature "oplus.software.audio.voice_wakeup_support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
    add_feature "oplus.software.audio.voice_wakeup_3words_support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
    #add_feature "oplus.software.speechassist.oneshot.support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
    unzip -o ${work_dir}/devices/common/voice_trigger_fix.zip -d ${work_dir}/build/portrom/images/
fi


cp -rf build/baserom/images/my_product/etc/Multimedia_*.xml build/portrom/images/my_product/etc/


if [[ -f "tmp/etc/permissions/multimedia_privapp-permissions-oplus.xml" ]];then
    cp -rfv tmp/etc/permissions/multimedia_*.xml build/portrom/images/my_product/etc/permissions/
fi



for file in $(find build/baserom/images/my_product/etc/ -type f -name "OVMS_*");do
    if [[ -f "$file" ]];then
        cp -rfv $file build/portrom/images/my_product/etc/
    fi
done

# bootanimation
rm -rf build/portrom/images/my_product/media/*
cp -rf build/baserom/images/my_product/media/* build/portrom/images/my_product/media/

rm -rf build/portrom/images/my_product/res/*
cp -rf build/baserom/images/my_product/res/* build/portrom/images/my_product/res/

rm -rf build/portrom/images/my_product/vendor/*
cp -rf build/baserom/images/my_product/vendor/* build/portrom/images/my_product/vendor/
rm -rf  build/portrom/images/my_product/overlay/*"${port_my_product_type}".apk
for overlay in $(find build/baserom/images/ -type f -name "*${base_my_product_type}*".apk);do
    cp -rf $overlay build/portrom/images/my_product/overlay/
done

super_computing=$(find build/portrom/images/my_product -name "string_super_computing*")
if [[ ! -f $super_computing ]];then
    cp -rf devices/common/super_computing/* build/portrom/images/my_product/etc/
fi

baseCarrierConfigOverlay=$(find build/baserom/images/ -type f -name "CarrierConfigOverlay*.apk")
portCarrierConfigOverlay=$(find build/portrom/images/ -type f -name "CarrierConfigOverlay*.apk")
if [ -f "${baseCarrierConfigOverlay}" ] && [ -f "${portCarrierConfigOverlay}" ];then
    blue "正在替换 [CarrierConfigOverlay.apk]" "Replacing [CarrierConfigOverlay.apk]"
    rm -rf ${portCarrierConfigOverlay}
    cp -rf ${baseCarrierConfigOverlay} $(dirname ${portCarrierConfigOverlay})
else
    cp -rf ${baseCarrierConfigOverlay} build/portrom/images/my_product/overlay/
fi


# RealmeUI 独占功能

add_feature "com.oplus.gesture.camera_space_gesture_support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.gesture.intelligent_perception" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.eyeprotect.ai_intelligent_eye_protect_support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.android.systemui.aod_notification_infor_text" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.android.settings.network_access_permission" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature 'com.oplus.mediacontroller.fluidConfig" args="String:{&quot;statusbar_enable_default&quot;:1}' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "oplus.software.audio.media_control" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
add_feature "com.oplus.smartsidebar.space.roulette.bootreg" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature "os.charge.settings.longchargeprotection.ai" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.gesture.intelligent_perception" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.battery.support.gt_open_gamecenter" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.android.settings.device_rm" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "oplus.software.support.gt.mode" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
add_feature "oplus.software.support.gt.mode" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml

add_feature "feature.support.game.AI_PLAY" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "feature.hottouch.anim.support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "com.oplus.exserviceui.feature_zoom_drag" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml


#add_feature 'space_roulette_switch" value="1" category="secure' build/portrom/images/my_product/etc/extension/config_product_com.android.providers.settings.xml

add_feature "oplus.software.support.zoom.open_wechat_mimi_program"  build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml
add_feature "oplus.software.support.zoom.center_exit" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml

add_feature "oplus.software.support.zoom.game_enter" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml

add_feature "ooplus.software.coolex.support" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml

add_feature "oplus.gpu.controlpanel.support" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml

add_feature "oplus.software.display.game.dapr_enable"   build/portrom/images/my_product/etc/permissions/oplus.product.features_gameeco_unique.xml

add_feature "oplus.software.display.eyeprotect_game_support" build/portrom/images/my_product/etc/permissions/oplus.product.display_features.xml


add_feature "com.oplus.smartsidebar.space.roulette.support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
#patch_smartsidecar

#add_feature "oplus.software.display.eyeprotect_paper_texture_support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

#add_feature "oplus.software.display.reduce_brightness_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
#add_feature "oplus.software.display.reduce_brightness_rm_manual" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

#add_feature "oplus.software.display.brightness_memory_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
#add_feature "oplus.software.display.sec_max_brightness_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

{
    echo "persist.lowbrightnessthreshold=0"
    echo "persist.sys.renderengine.maxLuminance=500"
    #echo "ro.oplus.display.brightness.min_settings.rm=1,1,25,4.0,0"
    echo "ro.oplus.display.peak.brightness.duration_time=15"
    echo "ro.oplus.display.peak.brightness.effect_interval_time=1800000"
    echo "ro.oplus.display.peak.brightness.effect_times_every_day=2"
    echo "ro.display.brightness.thread.priority=true"

} >> build/portrom/images/my_product/build.prop

# 强光模式选项开关
add_feature "oplus.software.display.manual_hbm.support" build/portrom/images/my_product/etc/permissions/oplus.product.display_features.xml
echo "ro.oplus.display.sell_mode.max_normal_nit=800" >> build/portrom/images/my_product/build.prop

add_feature "com.oplus.software.support.mini_capsule" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature "android.hardware.biometrics.face"  build/portrom/images/my_product/etc/permissions/android.hardware.fingerprint.xml

remove_feature "oplus.software.display.origin_roundcorner_support"
add_feature "oplus.software.display.smart_color_temperature_rhythm_health_support" build/portrom/images/my_product/etc/permissions/oplus.product.display_features.xml

#人声突显
add_feature "oplus.hardware.audio.voice_isolation_support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
add_feature "oplus.hardware.audio.voice_denoise_support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml


add_feature "oplus.software.radio.networkless_support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

# add_feature "com.oplus.humming_bird_enable" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature "com.oplus.mediaturbo.service" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

# removed from PKJ110_15.0.1.401
add_feature 'com.oplus.note.aigc.ai_rewrtie.support" args="boolean:true' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

add_feature 'com.oplus.mediaturbo.tencent_meeting" args="boolean:true'  build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
add_feature  "oplus.software.directservice.finger_flashnotes_enable" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

if grep -q "oplus.software.audio.alert_slider"  build/portrom/images/my_product/etc/permissions/* ;then
    add_feature "oplus.software.audio.alert_slider" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
fi

#  add for multi-application volume adjustment (OnePlus 8/8Pro Android 13 require this)
add_feature "oplus.software.multi_app.volume.adjust.support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

#直播助手
add_feature "com.oplus.mediaturbo.game_live" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

#护眼提醒
add_feature "oplus.software.display.ai_eyeprotect_v1_support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

#点击屏幕唤醒息屏
add_feature "oplus.aod.wakebyclick.support" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

#区域截图
add_feature 'com.oplus.screenrecorder.area_record" args="boolean:true' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

remove_feature "oplus.power.wirelesschgwhenwired.support"

remove_feature "oplus.software.vibration_ring_mute"
remove_feature  "oplus.software.vibration_alarm_clock"
remove_feature  "oplus.software.vibration_ringtone"
remove_feature  "oplus.software.vibration_threestage_key"

if [[ -d build/baserom/images/my_product/etc/vibrator ]];then
    rm -rfv build/portrom/images/my_product/etc/vibrator
    cp -rfv build/baserom/images/my_product/etc/vibrator build/portrom/images/my_product/etc/
fi

remove_feature "oppo.common.support.curved.display"

remove_feature "oplus.feature.largescreen"
remove_feature "oplus.feature.largescreen.land"
remove_feature "oplus.software.audio.audioeffect_support"
remove_feature "oplus.software.audio.audiox_support"

remove_feature "oppo.breeno.three.words.support"

remove_feature "oplus.software.vibrator_qcom_lmvibrator"
remove_feature "oplus.hardware.vibrator_style_switch"
remove_feature "oplus.software.vibrator_luxunvibrator"
remove_feature "oplus.software.palmprint_non_unify"
remove_feature "oplus.software.palmprint_v1"
remove_feature "oplus.software.palmprint"
remove_feature "os.charge.settings.wirelesscharge.support"
remove_feature "com.oplus.battery.wireless.charging.notificate"
remove_feature "os.charge.settings.wirelesscharging.power"
remove_feature "os.charge.settings.wirelesschargingcoil.position"
remove_feature "oplus.power.onwirelesscharger.support"

sourceAONService=$(find build/baserom/images/my_product -type d -name "AONService")

if [[ -d "$sourceAONService" ]];then
    targetAONService=$(find build/portrom/images/my_product -type d -name "AONService")
    if [[ -d "$targetAONService" ]];then
        rm -rfv $targetAONService/* 
        cp -rfv $sourceAONService/* $targetAONService/
    else
        cp -rfv $sourceAONService build/portrom/images/my_product/app/
    fi
	
	add_feature "oplus.software.aon_pay_qrcode_enable" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
	remove_feature "oplus.software.aon_sensorhub_enable" 

fi

#自定义替换

#Devices/机型代码/overlay 按照镜像的目录结构，可直接替换目标。
if [[ -d "devices/${base_product_device}/overlay" ]]; then
    cp -rf devices/${base_product_device}/overlay/* build/portrom/images/
else
    yellow "devices/${base_product_device}/overlay 未找到" "devices/${base_product_device}/overlay not found" 
fi

for zip in $(find devices/${base_product_device}/ -name "*.zip"); do
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
            cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_ksu.img
            patch_kernel_to_bootimg "$kernel_file" "$dtb_file" "boot_ksu.img"
            blue "生成内核boot_boot_ksu.img完毕" "New boot_ksu.img generated"
        elif [[ "$anykernel_dir" == *"-noksu"* ]]; then
            cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_noksu.img
            patch_kernel_to_bootimg "$kernel_file" "$dtb_file" "boot_noksu.img"
            blue "生成内核boot_noksu.img" "New boot_noksu.img generated"
        else
            cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_custom.img
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
if [[ $super_extended == true ]];then
    superSize=$(bash bin/getSuperSize.sh "others")
elif [[ $base_product_model == "LE2101" ]]; then
	# OnePlus 9R In is totally diff than OnePlus 9R CN
    superSize=$(bash bin/getSuperSize.sh OnePlus8T)
else
superSize=$(bash bin/getSuperSize.sh $base_product_device)
fi

green "Super大小为${superSize}" "Super image size: ${superSize}"
green "开始打包镜像" "Packing super.img"
for pname in ${super_list};do
    if [ -d "build/portrom/images/$pname" ];then
        if [[ "$OSTYPE" == "darwin"* ]];then
            thisSize=$(find build/portrom/images/${pname} | xargs stat -f%z | awk ' {s+=$1} END { print s }' )
        else
            thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        fi
        blue 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
        python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config
        python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts
        #sudo perl -pi -e 's/\\@/@/g' build/portrom/images/config/${pname}_file_contexts
        mkfs.erofs -zlz4hc,9 --mount-point ${pname} --fs-config-file build/portrom/images/config/${pname}_fs_config --file-contexts build/portrom/images/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}
        if [ -f "build/portrom/images/${pname}.img" ];then
            green "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
            #rm -rf build/portrom/images/${pname}
        else
            error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
            exit 1
        fi
        unset fsType
        unset thisSize
    fi
done
rm fstype.txt
rom_version=$(cat build/portrom/images/my_manifest/build.prop | grep "ro.build.display.id=" |  awk 'NR==1' | cut -d "=" -f2 | cut -d "(" -f1)
for img in $(find build/baserom/ -type f -name "vbmeta*.img");do
    python3 bin/patch-vbmeta.py ${img} > /dev/null 2>&1
done
if [[ -f devices/${base_product_device}/tz.img ]]; then
  cp -rfv devices/${base_product_device}/tz.img build/baserom/images/
fi

if [[ -f devices/${base_product_device}/keymaster.img ]]; then
  cp -rfv devices/${base_product_device}/keymaster.img build/baserom/images/
fi

if [[ $is_ab_device == true ]]; then
    if [[ ! -f build/portrom/images/my_preload.img ]];then
        cp -rfv devices/common/my_preload_empty.img build/portrom/images/my_preload.img
    fi
    if [[ ! -f build/portrom/images/my_company.img ]];then
        cp -rfv devices/common/my_company_empty.img build/portrom/images/my_company.img
    fi
fi 
pack_timestamp=$(date +"%m%d%H%M")
if [[ $pack_method == "stock" ]];then
    rm -rf out/target/product/${base_product_device}/
    mkdir -p out/target/product/${base_product_device}/IMAGES
    mkdir -p out/target/product/${base_product_device}/META
    for part in SYSTEM SYSTEM_EXT PRODUCT VENDOR ODM; do
        mkdir -p out/target/product/${base_product_device}/$part
    done
    mv -fv build/portrom/images/*.img out/target/product/${base_product_device}/IMAGES/
    if [[ -d build/baserom/firmware-update ]];then
        bootimg=$(find build/baserom/ -name "boot.img")
        cp -rf $bootimg out/target/product/${base_product_device}/IMAGES/
    else
        if [[ -f build/baserom/images/init_boot-kernelsu.img ]];then
            mv build/baserom/images/init_boot-kernelsu.img build/baserom/images/init_boot.img
        fi
        mv -fv build/baserom/images/*.img out/target/product/${base_product_device}/IMAGES/
    fi

    if [[ -d devices/${base_product_device} ]];then

        ksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_ksu.img")
        dtbo_file=$(find devices/$base_product_device/ -type f -name "*dtbo_ksu.img")
        if [ -n "$ksu_bootimg_file" ];then
            mv -fv $ksu_bootimg_file out/target/product/${base_product_device}/IMAGES/boot.img
            mv -fv $dtbo_file out/target/product/${base_product_device}/IMAGES/dtbo.img
        else
            spoof_bootimg out/target/product/${base_product_device}/IMAGES/boot.img
        fi
    fi
    rm -rf out/target/product/${base_product_device}/META/ab_partitions.txt
    rm -rf out/target/product/${base_product_device}/META/update_engine_config.txt
    rm -rf out/target/product/${base_product_device}/target-file.zip
    for part in out/target/product/${base_product_device}/IMAGES/*.img; do
        partname=$(basename "$part" .img)
        echo $partname >> out/target/product/${base_product_device}/META/ab_partitions.txt
        if echo $super_list | grep -q -w "$partname"; then
            super_list_info+="$partname "
            otatools/bin/map_file_generator $part ${part%.*}.map
        fi
    done 
    rm -rf out/target/product/${base_product_device}/META/dynamic_partitions_info.txt
    let groupSize=superSize-1048576
    {
        echo "super_partition_size=$superSize"
        echo "super_partition_groups=qti_dynamic_partitions"
        echo "super_qti_dynamic_partitions_group_size=$groupSize"
        echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
        echo "virtual_ab=true"
        echo "virtual_ab_compression=true"
    } >> out/target/product/${base_product_device}/META/dynamic_partitions_info.txt

    {
        #echo "default_system_dev_certificate=key/testkey"
        echo "recovery_api_version=3"
        echo "fstab_version=2"
        echo "ab_update=true"
     } >> out/target/product/${base_product_device}/META/misc_info.txt
    
    {
        echo "PAYLOAD_MAJOR_VERSION=2"
        echo "PAYLOAD_MINOR_VERSION=8"
    } >> out/target/product/${base_product_device}/META/update_engine_config.txt

    if [[ "$is_ab_device" == false ]];then
        sed -i "/ab_update=true/d" out/target/product/${base_product_device}/META/misc_info.txt
        {
            echo "blockimgdiff_versions=3,4"
            echo "use_dynamic_partitions=true"
            echo "dynamic_partition_list=$super_list_info"
            echo "super_partition_groups=qti_dynamic_partitions"
            echo "super_qti_dynamic_partitions_group_size=$superSize"
            echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
            echo "board_uses_vendorimage=true"
            echo "cache_size=402653184"

        } >> out/target/product/${base_product_device}/META/misc_info.txt
        mkdir -p out/target/product/${base_product_device}/OTA/bin
        for part in MY_PRODUCT MY_BIGBALL MY_CARRIER MY_ENGINEERING MY_HEYTAP MY_MANIFEST MY_REGION MY_STOCK;do
            mkdir -p out/target/product/${base_product_device}/$part
        done

        if [[ -f devices/${base_product_device}/OTA/bin/updater ]];then
            cp -rf devices/${base_product_device}/OTA/bin/updater out/target/product/${base_product_device}/OTA/bin
        else
            cp -rf devices/common/non-ab/OTA/updater out/target/product/${base_product_device}/OTA/bin
        fi
        if [[ -d build/baserom/firmware-update ]];then
            cp -rf build/baserom/firmware-update out/target/product/${base_product_device}/
        elif find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \) | grep -q .; then
            for firmware in $(find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \));do
                mv  -rfv $firmware out/target/product/${base_product_device}/firmware-update
            done
            bootimg=$(find build/baserom/ -name "boot.img")
            dtboimg=$(find build/baserom/images -name "dtbo.img")
            vbmetaimg=$(find build/baserom/ -name "vbmeta.img")
            vmbeta_systemimg=$(find build/baserom/ -name "vbmeta_sytem.img")
            cp -rf $bootimg out/target/product/${base_product_device}/IMAGES/
            cp -rf $dtboimg out/target/product/${base_product_device}/firmware-update
            cp -rf $vbmetaimg out/target/product/${base_product_device}/firmware-update
            cp -rf $vmbeta_systemimg out/target/product/${base_product_device}/firmware-update
        fi

        if [[ -d build/baserom/storage-fw ]];then
            cp -rf build/baserom/storage-fw out/target/product/${base_product_device}/
            cp -rf build/baserom/ffu_tool out/target/product/${base_product_device}/storage-fw
        fi
        export OUT=$(pwd)/out/target/product/${base_product_device}/
        if [[ -f devices/${base_product_device}/releasetools.py ]];then
            cp -rf devices/${base_product_device}/releasetools.py out/target/product/${base_product_device}/META/
        else
            cp -rf devices/common/releasetools.py out/target/product/${base_product_device}/META/
        fi

        mkdir -p out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        if [[ -f devices/${base_product_device}/recovery.fstab ]];then
            cp -rf devices/${base_product_device}/recovery.fstab out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        else
            cp -rf devices/common/recovery.fstab out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        fi
    fi
    declare -A prop_paths=(
    ["system"]="SYSTEM"
    ["product"]="PRODUCT"
    ["system_ext"]="SYSTEM_EXT"
    ["vendor"]="VENDOR"
    ["my_manifest"]="ODM"
    
    )

    for dir in "${!prop_paths[@]}"; do
        prop_file=$(find "build/portrom/images/$dir" -type f -name "build.prop" -not -path "*/system_dlkm/*" -not -path "*/odm_dlkm/*" -print -quit)
        if [ -n "$prop_file" ]; then
            cp "$prop_file" "out/target/product/${base_product_device}/${prop_paths[$dir]}/"
        fi
    done
  
    pushd otatools
    export PATH=$(pwd)/bin/:$PATH
    ./bin/ota_from_target_files ${work_dir}/out/target/product/${base_product_device}/ ${work_dir}/out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip
    popd
    ziphash=$(md5sum out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip |head -c 10)
    mv -f out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip out/ota_full-${rom_version}-${port_product_model}-${pack_timestamp}-$regionmark-${portrom_version_security_patch}-${ziphash}.zip
	blue "打包完成： out/ota_full-${rom_version}-${port_product_model}-${pack_timestamp}-$regionmark-${portrom_version_security_patch}-${ziphash}.zip"
else
    # 打包 super.img
    if [[ $is_ab_device = "false" ]];then
        blue "打包A-only机型 super.img" "Packing super.img for A-only device"
        lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
        for pname in ${super_list};do
            if [ -f "build/portrom/images/${pname}.img" ];then
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
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
    if [[ ${port_vendor_brand} == "realme" ]];then
        os_type="RealmeUI"
    else
    os_type="ColorOS"
    fi
    rom_version=$(cat build/portrom/images/my_manifest/build.prop | grep "ro.build.display.id=" |  awk 'NR==1' | cut -d "=" -f2 | cut -d "(" -f1)

    blue "正在压缩 super.img" "Comprising super.img"
    zstd build/portrom/images/super.img -o build/portrom/super.zst

    blue "正在生成刷机脚本" "Generating flashing script"

    mkdir -p out/${os_type}_${rom_version}/META-INF/com/google/android/   
    mkdir -p out/${os_type}_${rom_version}/firmware-update
    cp -rf bin/flash/platform-tools-windows out/${os_type}_${rom_version}/
    cp -rf bin/flash/windows_flash_script.bat out/${os_type}_${rom_version}/
    cp -rf bin/flash/mac_linux_flash_script.sh out/${os_type}_${rom_version}/
    cp -rf bin/flash/zstd out/${os_type}_${rom_version}/META-INF/
    mv -f build/portrom/*.zst out/${os_type}_${rom_version}/

    cp -rf bin/flash/update-binary out/${os_type}_${rom_version}/META-INF/com/google/android/

    if [[ $is_ab_device = "false" ]];then
        mv -f build/baserom/firmware-update/*.img out/${os_type}_${rom_version}/firmware-update
        for fwimg in $(ls out/${os_type}_${rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"xbl"* ]] || [[ $fwimg == *"dtbo"* ]] ;then
                # Warning: If wrong xbl img has been flashed, it will cause phone hard brick, so we just skip it with fastboot mode.
                continue

            elif [[ ${fwimg} == "BTFM" ]];then
                part="bluetooth"
            elif [[ ${fwimg} == "cdt_engineering" ]];then
                part="engineering_cdt"
            elif [[ ${fwimg} == "BTFM" ]];then
                part="bluetooth"
            elif [[ ${fwimg} == "dspso" ]];then
                part="dsp"
            elif [[ ${fwimg} == "keymaster64" ]];then
                part="keymaster"
            elif [[ ${fwimg} == "qupv3fw" ]];then
                part="qupfw"
            elif [[ ${fwimg} == "static_nvbk" ]];then
                part="static_nvbk"
            else
                part=${fwimg}                
            fi

            sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe flash "${part}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
        done
        sed -i "/_b/d" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/_a//g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i '/^REM SET_ACTION_SLOT_A_BEGIN/,/^REM SET_ACTION_SLOT_A_END/d' out/${os_type}_${rom_version}/windows_flash_script.bat

    else
        mv -f build/baserom/images/*.img out/${os_type}_${rom_version}/firmware-update
        for fwimg in $(ls out/${os_type}_${rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"xbl"* ]] || [[ $fwimg == *"dtbo"* ]] || [[ $fwimg == *"reserve"* ]] || [[ $fwimg == *"boot"* ]];then
                rm -rfv out/${os_type}_${rom_version}/firmware-update/*reserve*
                # Warning: If wrong xbl img has been flashed, it will cause phone hard brick, so we just skip it with fastboot mode.
                continue
            elif [[ $fwimg == "mdm_oem_stanvbk" ]] || [[ $fwimg == "spunvm" ]] ;then
                sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
            elif [ "$(echo ${fwimg} |grep vbmeta)" != "" ];then
                sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
            else
                sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\platform-tools-windows\\\fastboot.exe flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
            fi
        done
    fi

    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/windows_flash_script.bat
    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary

    sed -i "s/portversion/${port_rom_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary

    busybox unix2dos out/${os_type}_${rom_version}/windows_flash_script.bat

    #disable vbmeta
    for img in $(find out/${os_type}_${rom_version}/ -type f -name "vbmeta*.img");do
        python3 bin/patch-vbmeta.py ${img} > /dev/null 2>&1
    done

    ksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_ksu.img")
    nonksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_noksu.img")
    custom_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_custom.img")

    if [[ -f $nonksu_bootimg_file ]];then
        nonksubootimg=$(basename "$nonksu_bootimg_file")
        mv -f $nonksu_bootimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_noksu.img out/${os_type}_${rom_version}/firmware-update/dtbo_noksu.img
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
    else
        bootimg=$(find build/baserom/ out/${os_type}_${rom_version} -name "boot.img")
        mv -f $bootimg out/${os_type}_${rom_version}/boot_official.img
    fi

    if [[ -f "$ksu_bootimg_file" ]];then
        ksubootimg=$(basename "$ksu_bootimg_file")
        mv -f $ksu_bootimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_ksu.img out/${os_type}_${rom_version}/firmware-update/dtbo_ksu.img
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        
    elif [[ -f "$custom_bootimg_file" ]];then
        custombootimg=$(basename "$custom_botimg_file")
        mv -f $custom_botimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_custom.img out/${os_type}_${rom_version}/firmware-update/dtbo_custom.img
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        
    fi

    find out/${os_type}_${rom_version} |xargs touch
    pushd out/${os_type}_${rom_version}/ >/dev/null || exit
    zip -r ${os_type}_${rom_version}.zip ./*
    mv ${os_type}_${rom_version}.zip ../
    popd >/dev/null || exit
    pack_timestamp=$(date +"%m%d%H%M")
    hash=$(md5sum out/${os_type}_${rom_version}.zip |head -c 10)
    if [[ $pack_type == "EROFS" ]];then
        pack_type="ROOT_"${pack_type}
    fi
    mv out/${os_type}_${rom_version}.zip out/${os_type}_${rom_version}_${hash}_${port_product_model}_${pack_timestamp}_${pack_type}.zip
    green "移植完毕" "Porting completed"    
    green "输出包路径：" "Output: "
    green "$(pwd)/out/${os_type}_${rom_version}_${hash}_${port_product_model}_${pack_timestamp}_${pack_type}.zip"
fi