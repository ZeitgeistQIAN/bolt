#!/bin/bash

device=$1
device_dir=/data/local/tmp/CI/java
core="40"

script_name=$0
script_abs=$(readlink -f "$0")
script_dir=$(dirname $script_abs)
BOLT_ROOT=${script_dir}/..
tmp_dir=${BOLT_ROOT}/tmp
install_dir=${BOLT_ROOT}/install_llvm
current_dir=${PWD}

rm -rf ${tmp_dir}
mkdir  ${tmp_dir}

cd ${tmp_dir}
cp ${install_dir}/include/java/* .
cp ${BOLT_ROOT}/tests/test_api_java.java .
javac BoltResult.java || exit 1
javac BoltModel.java || exit 1
javac test_api_java.java || exit 1
dx --dex --output=test_java_api.jar *.class || exit 1

adb -s ${device} shell mkdir ${device_dir} || exit 1
adb -s ${device} push ${install_dir}/lib/libBoltModel.so ${device_dir}
adb -s ${device} push ${install_dir}/lib/libkernelbin.so ${device_dir}
adb -s ${device} push ${install_dir}/lib/libOpenCL.so ${device_dir}
adb -s ${device} push ./test_java_api.jar ${device_dir}

adb -s ${device} shell "cd ${device_dir} && export LD_LIBRARY_PATH=/apex/com.android.runtime/lib64/bionic:/system/lib64 && dalvikvm -cp ./test_java_api.jar test_api_java ${device}"
adb -s ${device} shell rm ${device_dir}/libBoltModel.so
adb -s ${device} shell rm ${device_dir}/libkernelbin.so
adb -s ${device} shell rm ${device_dir}/libOpenCL.so
adb -s ${device} shell rm ${device_dir}/test_java_api.jar

rm -rf ${tmp_dir}
cd ${current_dir}
