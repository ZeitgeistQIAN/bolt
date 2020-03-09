#!/bin/bash

script_name=$0
script_abs=$(readlink -f "$0")
script_dir=$(dirname $script_abs)

host_bin_dir=""
host_lib_dir=""
excute_on_device=false
use_static_library=true
remove=true
device=""
cpu_mask="2"
device_dir=""
model_zoo_dir=""

print_help() {
    cat <<EOF
Usage: ${script_name} [OPTION]...
Run model_tools test.

Mandatory arguments to long options are mandatory for short options too.
  -h, --help                 display this help and exit.
  -b, --bin <PATH>           run specified program in <PATH>.
  -l, --lib <PATH>           use dynamic library in <PATH>.
  -d, --device <device_id>   run test on device.
  -c, --cpu_mask <mask>      taskset cpu mask(default: 2).
  -p, --path <PATH>          run test on device in specified <PATH>.
  -m, --model_zoo <PATH>     use prepared models in model_zoo(<PATH>/[caffe|onnx|tflite]_models)
  -r, --remove               remove device tmp directory or not
EOF
    exit 1;
}

TEMP=`getopt -o b:c:hl:d:p:r:m: --long bin:cpu_mask:help,lib:device:path:remove:model_zoo \
     -n ${script_name} -- "$@"`
if [ $? != 0 ] ; then echo "[ERROR] terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true ; do
    case "$1" in
        -b|--bin)
            host_bin_dir=$2
            echo "[INFO] run test in ${host_bin_dir}" ;
            shift 2 ;;
        -c|--cpu_mask)
            cpu_mask=$2
            echo "[INFO] CPU mask ${cpu_mask}" ;
            shift 2 ;;
        -l|--lib)
            host_lib_dir=$2
            use_static_library=false
            echo "[INFO] use library in ${host_lib_dir}" ;
            shift 2 ;;
        -d|--device)
            device=$2
            exe_on_device=true
            echo "[INFO] test on device ${device}" ;
            shift 2 ;;
        -m|--model_zoo)
            model_zoo_dir=$2
            echo "[INFO] use model_zoo ${model_zoo_dir}" ;
            shift 2 ;;
        -p|--path)
            device_dir=$2
            echo "[INFO] test on device directory ${device_dir}" ;
            shift 2 ;;
        -r|--remove)
            remove=$2
            echo "[INFO] clear tmp directory ${remove}" ;
            shift 2;;
        -h|--help)
            print_help ;
            shift ;;
        --) shift ;
            break ;;
        *) echo "[ERROR] $1" ; exit 1 ;;
    esac
done

run_command() {
    params=$*

    if [ ${exe_on_device} == true ] ; then
        if [ ${use_static_library} == true ] ; then
            adb -s ${device} shell "cd ${device_dir}/tmp && taskset ${cpu_mask} ./${params} || echo '[FAILURE]'" &> status.txt
        else
            adb -s ${device} shell "cd ${device_dir}/tmp && export LD_LIBRARY_PATH=. && taskset ${cpu_mask} ./${params} || echo '[FAILURE]'" &> status.txt
        fi
    else
        if [ ${use_static_library} == true ] ; then
            cd ${host_bin_dir}/tmp && taskset ${cpu_mask} ${host_bin_dir}/${params} || echo '[FAILURE]' &> status.txt
        else
            export LD_LIBRARY_PATH=${host_lib_dir}:${LD_LIBRARY_PATH} && cd ${host_bin_dir}/tmp && taskset ${cpu_mask} ${host_bin_dir}/${params} || echo '[FAILURE]' &> status.txt
        fi
    fi
    cat status.txt || exit 1
    if [ `grep -c "\[FAILURE\]" status.txt` -ne '0' ] ; then
        exit 1
    fi
    rm status.txt
}

if [ ${exe_on_device}  == true ] ; then
    adb -s ${device} shell "mkdir ${device_dir}"
    adb -s ${device} shell "rm -rf ${device_dir}/tmp"
    adb -s ${device} shell "mkdir ${device_dir}/tmp"
    adb -s ${device} shell "cp -r ${model_zoo_dir}/* ${device_dir}/tmp/"
    adb -s ${device} shell "find ${device_dir}/tmp -name \"*\.bolt\" | xargs rm -rf"
    if [ ${use_static_library} != true ] ; then
        adb -s ${device} push ${host_lib_dir}/libmodel-tools.so ${device_dir}/tmp
        adb -s ${device} push ${host_lib_dir}/libmodel-tools_caffe.so ${device_dir}/tmp
        adb -s ${device} push ${host_lib_dir}/libmodel-tools_onnx.so ${device_dir}/tmp
        adb -s ${device} push ${host_lib_dir}/libmodel-tools_tflite.so ${device_dir}/tmp
    fi
    adb -s ${device} push ${host_bin_dir}/caffe2bolt  ${device_dir}/tmp
    adb -s ${device} push ${host_bin_dir}/onnx2bolt   ${device_dir}/tmp
    adb -s ${device} push ${host_bin_dir}/tflite2bolt ${device_dir}/tmp
else
    mkdir ${host_bin_dir}/tmp
    cp -r ${model_zoo_dir}/* ${host_bin_dir}/tmp/
fi

# caffe model
# INT8
run_command caffe2bolt caffe_models/squeezenet squeezenet INT8_Q
# FP16
run_command caffe2bolt caffe_models/mobilenet_v1 mobilenet_v1 FP16
run_command caffe2bolt caffe_models/mobilenet_v2 mobilenet_v2 FP16
run_command caffe2bolt caffe_models/mobilenet_v3 mobilenet_v3 FP16
run_command caffe2bolt caffe_models/resnet50 resnet50 FP16
run_command caffe2bolt caffe_models/squeezenet squeezenet FP16
run_command caffe2bolt caffe_models/fingerprint_resnet18 fingerprint_resnet18 FP16
run_command caffe2bolt caffe_models/tinybert tinybert FP16
run_command caffe2bolt caffe_models/nmt nmt FP16
# FP32 
run_command caffe2bolt caffe_models/mobilenet_v1 mobilenet_v1 FP32
run_command caffe2bolt caffe_models/mobilenet_v2 mobilenet_v2 FP32
run_command caffe2bolt caffe_models/mobilenet_v3 mobilenet_v3 FP32
run_command caffe2bolt caffe_models/resnet50 resnet50 FP32
run_command caffe2bolt caffe_models/squeezenet squeezenet FP32
run_command caffe2bolt caffe_models/fingerprint_resnet18 fingerprint_resnet18 FP32
run_command caffe2bolt caffe_models/tinybert tinybert FP32
run_command caffe2bolt caffe_models/nmt nmt FP32

# onnx model
# BNN
run_command onnx2bolt onnx_models/birealnet18 birealnet18 FP16
run_command onnx2bolt onnx_models/birealnet18 birealnet18 FP32
# FP16
run_command onnx2bolt onnx_models/ghostnet ghostnet 3 FP16
# FP32                                               
run_command onnx2bolt onnx_models/ghostnet ghostnet 3 FP32

if [ ${remove} == true ] ; then
    if [ ${exe_on_device}  == true ] ; then
        adb -s ${device} shell rm -rf ${device_dir}/tmp
    else
        rm -rf ${host_bin_dir}/tmp
    fi
fi
