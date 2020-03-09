#!/bin/bash

script_name=$0
script_abs=$(readlink -f "$0")
script_dir=$(dirname $script_abs)
bolt_dir=${script_dir}/../

echo "[INFO] compiler $1"

upload_program() {
    host_dir=$1
    device=$2
    device_dir=$3

    adb -s ${device} shell "rm -rf ${device_dir}"
    adb -s ${device} shell "mkdir ${device_dir}"
    adb -s ${device} shell "mkdir ${device_dir}/bin ${device_dir}/lib"
    adb -s ${device} push ${host_dir}/bin ${device_dir}/bin
    for file in `ls ${host_dir}/lib/*.so`
    do
        adb -s ${device} push ${file} ${device_dir}/lib
    done
    adb -s ${device} push ${host_dir}/tools/caffe2bolt ${device_dir}/bin
    adb -s ${device} push ${host_dir}/tools/onnx2bolt ${device_dir}/bin
    adb -s ${device} push ${host_dir}/tools/tflite2bolt ${device_dir}/bin
}

if [[ "$1" == "llvm" ]] || [[ "$1" == "gcc8.3" ]]
then
    host_dir=""
    if [[ "$1" == "llvm" ]]
    then
        host_dir=${bolt_dir}/install_llvm
    fi
    if [[ "$1" == "gcc8.3" ]]
    then
        host_dir=${bolt_dir}/install_gnu
    fi

    device_dir=/data/local/tmp/CI/$1

    # Kirin 810
    upload_program ${host_dir} E5B0119506000260 ${device_dir}

    # Kirin 990
    upload_program ${host_dir} GCL5T19822000030 ${device_dir}
else
    echo "[ERROR] unsupported compiler $1"
fi
