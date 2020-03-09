#!/bin/bash

declare CONVERTER

declare BOLT_SUFFIX

declare TASKSET_STR

declare EXECUTOR="classification"

declare CI_PATH="/data/local/tmp/CI"

declare MODEL_TOOLS_EXE_PATH=${CI_PATH}

declare ENGINE_EXE_PATH=${CI_PATH}

declare BOLT_LIB_PATH=${CI_PATH}

declare CAFFE_MODEL_ZOO_PATH="${CI_PATH}/model_zoo/caffe_models/"

declare ONNX_MODEL_ZOO_PATH="${CI_PATH}/model_zoo/onnx_models/"

declare TFLITE_MODEL_ZOO_PATH="${CI_PATH}/model_zoo/tflite_models/"

declare DYNAMIC_MODEL_PATH_PREFIX

declare PHONE_SPECIFICATION

declare TESTING_DATA_PREFIX="${CI_PATH}/testing_data/"

function converter_selection()
{
    if [ "$1" == "caffe" ]
    then
        CONVERTER="caffe2bolt"
        DYNAMIC_MODEL_PATH_PREFIX=$CAFFE_MODEL_ZOO_PATH
        return
    fi

    if [ "$1" == "onnx" ]
    then
        CONVERTER="onnx2bolt"
        DYNAMIC_MODEL_PATH_PREFIX=$ONNX_MODEL_ZOO_PATH
        return
    fi

    if [ "$1" == "tflite" ]
    then
        CONVERTER="tflite2bolt"
        DYNAMIC_MODEL_PATH_PREFIX=$TFLITE_MODEL_ZOO_PATH
        return
    fi

    echo "[ERROR] error to convert model $1"
    exit 1
}

function acc_selection()
{
    if [ "$1" == "fp32" ]
    then
        BOLT_SUFFIX="_f32.bolt"
        return
    fi

    if [ "$1" == "fp16" ]
    then
        BOLT_SUFFIX="_f16.bolt"
        return
    fi

    if [ "$1" == "int8" ]
    then
        BOLT_SUFFIX="_int8_q.bolt"
        return
    fi

    echo "[ERROR] error to process model precision $1"
    exit 1
}

function core_selection()
{
    if [ "$1" == "A55" ]
    then
        TASKSET_STR="CPU_AFFINITY_LOW_POWER"
        return
    fi

    if [ "$1" == "A76" ]
    then
        TASKSET_STR="CPU_AFFINITY_HIGH_PERFORMANCE"
        return
    fi

    echo "[ERROR] error to set affinity setting $1"
    exit 1
}

function device_selection()
{
    if [ "$1" == "cpu" ]
    then
        return
    fi

    if [ "$1" == "gpu" ]
    then
        TASKSET_STR="GPU"
        return
    fi

    echo "[ERROR] error to set device $1"
    exit 1
}

# device id to phone specification
function deviceId_to_phoneSpecification()
{
    if [ "$1" == "E5B0119506000260" ]
    then
        PHONE_SPECIFICATION="810"
        return
    fi

    if [ "$1" == "GCL5T19822000030" ]
    then
        PHONE_SPECIFICATION="990"
        return
    fi

    echo "[ERROR] error to set mobile phone $1"
    exit 1
}


rm -rf ./executable_command_lines.txt
touch ./executable_command_lines.txt

while IFS= read -r line; do
    strs_arr=()
    index=0
    for i in $(echo $line| tr "-" "\n")
    do
        strs_arr[$index]=$i;
        let index+=1
    done

    commind_line=""

    DL_FRAMEWORK=${strs_arr[1]}
    converter_selection $DL_FRAMEWORK

    core_selection ${strs_arr[5]}

    acc_selection ${strs_arr[6]}

    device_selection ${strs_arr[7]}

    # define model converter param
    MODEL_NAME=${strs_arr[0]}

    EXECUTOR="classification"
    if [ "$MODEL_NAME" == "tinybert" ]
    then
        EXECUTOR="tinybert"
    fi
    if [ "$MODEL_NAME" == "nmt" ]
    then
        EXECUTOR="nmt"
    fi

    REMOVE_OP_NUM="0"
    if [ "$DL_FRAMEWORK" == "onnx" ]
    then
        REMOVE_OP_NUM=${strs_arr[12]}
    fi

    COMPILER=${strs_arr[3]}
    TESTING_DATA_PATH=$TESTING_DATA_PREFIX${strs_arr[9]}
    ORIGINAL_PARAM=${strs_arr[11]}
    MODEL_PATH=$DYNAMIC_MODEL_PATH_PREFIX$MODEL_NAME"/"
    EXECUTE_PARAM=
    BOLT_MODEL_PATH=$MODEL_PATH$MODEL_NAME$BOLT_SUFFIX
    for i in $(echo $ORIGINAL_PARAM| tr "+" "\n")
    do
        EXECUTE_PARAM=$EXECUTE_PARAM" ""$i"
    done

    mt_command_line=
    if [ "$DL_FRAMEWORK" == "caffe" ]
    then
	mt_command_line="."${MODEL_TOOLS_EXE_PATH}/${COMPILER}"/bin/"$CONVERTER" "$MODEL_PATH" "$MODEL_NAME
    fi
    if [ "$DL_FRAMEWORK" == "onnx" ]
    then
        mt_command_line="."${MODEL_TOOLS_EXE_PATH}/${COMPILER}"/bin/"$CONVERTER" "$MODEL_PATH" "$MODEL_NAME" "$REMOVE_OP_NUM
    fi

    if [ ${strs_arr[6]} == "fp32" ]
    then
        mt_command_line=$mt_command_line" FP32"
    fi
    if [ ${strs_arr[6]} == "fp16" ]
    then
        mt_command_line=$mt_command_line" FP16"
    fi
    if [ ${strs_arr[6]} == "int8" ]
    then
        mt_command_line=$mt_command_line" INT8_Q"
    fi

    engine_command_line="."${ENGINE_EXE_PATH}/${COMPILER}"/bin/"$EXECUTOR" "$BOLT_MODEL_PATH" "$TESTING_DATA_PATH" "$EXECUTE_PARAM" "$TASKSET_STR

    mt_command_line="export LD_LIBRARY_PATH=${BOLT_LIB_PATH}/${COMPILER}/lib && "$mt_command_line
    engine_command_line="export LD_LIBRARY_PATH=${BOLT_LIB_PATH}/${COMPILER}/lib && "$engine_command_line

    ADB_COMMAND_PREFIX="adb -s ${strs_arr[4]} shell"

    adb_command_line=$ADB_COMMAND_PREFIX" \""$mt_command_line"\" > mt_result.txt && "$ADB_COMMAND_PREFIX" \""$engine_command_line"\" > engine_result.txt"

    echo  "$adb_command_line" >> ./executable_command_lines.txt
done < "./final_combinations.txt"

rm -r ./report.csv
touch ./report.csv
outline_index=0

while IFS= read -r line; do
    rm -rf ./mt_result.txt
    rm -rf ./engine_result.txt
    touch ./mt_result.txt
    touch ./engine_result.txt
    echo "Running_Beginning =====> $line"
    eval "$line"

    MT_RUN_RESULT="MT_RUN_UNKNOWN"

    ENGINE_RUN_RESULT="ENGINE_RUN_UNKNOWN"

    TOP_ONE_ACC=
    TOP_FIVE_ACC=
    MAX_TIME_RESULT=
    MIN_TIME_RESULT=
    AVG_TIME_RESULT=
    MESSAGE="ERROR"

    if cat ./mt_result.txt | grep "$MESSAGE" > /dev/null
    then
        MT_RUN_RESULT="MT_RUN_FAIL"
        echo "Model conversion failed"
        exit 1
    else
        MT_RUN_RESULT="MT_RUN_PASS"
    fi

    if cat ./engine_result.txt | grep "$MESSAGE" > /dev/null
    then
        ENGINE_RUN_RESULT="ENGINE_RUN_FAIL"
        TOP_ONE_ACC="ERROR"
        TOP_FIVE_ACC="ERROR"
        MAX_TIME_RESULT="ERROR"
        MIN_TIME_RESULT="ERROR"
        AVG_TIME_RESULT="ERROR"
        echo "Error during inference"
        exit 1
    else
        ENGINE_RUN_RESULT="ENGINE_RUN_PASS"
        TOP_ONE_ACC=$(grep -I "top1" ./engine_result.txt)
        TOP_FIVE_ACC=$(grep -I "top5" ./engine_result.txt)
        MAX_TIME_RESULT=$(grep -I "max_time" ./engine_result.txt)
        MIN_TIME_RESULT=$(grep -I "min_time" ./engine_result.txt)
        AVG_TIME_RESULT=$(grep -I "avg_time:" ./engine_result.txt)
    fi

    if [[ ${#AVG_TIME_RESULT} < 1 ]]
    then
        echo "Undetected error during Inference"
        exit 1
    fi

    final_arr=()
    inline_index=0
    while IFS= read -r line; do
        index=0
        for i in $(echo $line| tr "-" "\n")
        do
            final_arr[$index]=$i;
            let index+=1
        done

        if [ $outline_index == $inline_index ]
        then
            break
        else
            let inline_index+=1
        fi

    done < "./final_combinations.txt"

    result_line=""

    report_index=0
    deviceId_to_phoneSpecification ${final_arr[4]}
    final_arr[4]=$PHONE_SPECIFICATION
    final_arr[11]=""
    CUR_MODEL_NAME=${final_arr[0]}
    for value in "${final_arr[@]}";
    do
        if [ $report_index == 11 ]
        then
            break
        fi

        if [ $report_index == 0 ]
        then
            result_line=$value
        else
            result_line=$result_line"\t"$value
        fi
        let report_index+=1
    done

    # add segmentation fault check
    SEGMENTATION_FAULT_CHECK=$(grep -I "Segmentation fault" ./mt_result.txt)
    if [[ ${#SEGMENTATION_FAULT_CHECK} > 0 ]]
    then
        MT_RUN_RESULT="MT_SEGMENTATION_FAULT"
        echo "Segmentation fault during model conversion"
        exit 1
    fi

    SEGMENTATION_FAULT_CHECK=$(grep -I "Segmentation fault" ./engine_result.txt)
    if [[ ${#SEGMENTATION_FAULT_CHECK} > 0 ]]
    then
        ENGINE_RUN_RESULT="ENGINE_SEGMENTATION_FAULT"
        echo "Segmentation fault during inference"
        exit 1
    fi

    COMPREHENSIVE_RESULT=$MAX_TIME_RESULT"+"$MIN_TIME_RESULT"+"$AVG_TIME_RESULT"+"$TOP_FIVE_ACC"+"$TOP_ONE_ACC

    if [[ "$CUR_MODEL_NAME" == "tinybert" || "$CUR_MODEL_NAME" == "fingerprint_resnet18" || "$CUR_MODEL_NAME" == "nmt" ]]
    then
        result_line=$result_line"\t"$MT_RUN_RESULT"\t"$ENGINE_RUN_RESULT"\t"$AVG_TIME_RESULT"\n"
    else
        result_line=$result_line"\t"$MT_RUN_RESULT"\t"$ENGINE_RUN_RESULT"\t"$MAX_TIME_RESULT"\t"$MIN_TIME_RESULT"\t"$AVG_TIME_RESULT"\t"$TOP_FIVE_ACC"\t"$TOP_ONE_ACC"\n"
    fi

    echo "Running_Result =====> $result_line"

    printf $result_line >> ./report.csv
    echo " " >> ./report.csv
    let outline_index+=1
    echo " "
    echo " "
done < "./executable_command_lines.txt"

cat ./report.csv

rm -rf ./mt_result.txt
rm -rf ./engine_result.txt
