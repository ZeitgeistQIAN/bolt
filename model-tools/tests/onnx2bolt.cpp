// Copyright (C) 2019. Huawei Technologies Co., Ltd. All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), 
// to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE 
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR 
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#include <string>
#include <stdlib.h>
#include "model_tools.h"
#include "model_serialize_deserialize.hpp"
#include "model_optimizer.hpp"
#include "converter.h"
#include "model_print.h"

int main(int argc, char* argv[])
{   
    CHECK_REQUIREMENT(argc >= 3);
    std::string dirStr = argv[1];
    std::string mfnStr = argv[2];

    int removePreprocessOpNum = 0;
    if (argc > 3) {
        removePreprocessOpNum = atoi(argv[3]);
    }

    QuantizationMode qm = NO_Q;
    if (argc > 4) {
        qm = (std::string(argv[4]) == std::string("INT8_Q") ? INT8_Q : NO_Q);
    }
    U32 n = 1;
    U32 c = 3;
    U32 h = 224;
    U32 w = 224;
    if (argc > 5) {
        if (argc < 9) {
            printf("[ERROR] Please provide 4 integers as input NCHW\n");
            return 1;
        }
        n = atoi(argv[5]);
        c = atoi(argv[6]);
        h = atoi(argv[7]);
        w = atoi(argv[8]);
    }
    TensorDesc inputDesc = tensor4df(DT_F32, DF_NCHW, n, c, h, w);

    ModelSpec originalMs;    // fp32
    ModelSpec targetMs;    // fp16
    ModelSpec resultMs;    
    CHECK_STATUS(mt_create_model(&originalMs));
    CHECK_STATUS(mt_create_model(&targetMs));
    CHECK_STATUS(mt_create_model(&resultMs));

    CHECK_STATUS(mt_load_onnx(dirStr.c_str(), mfnStr.c_str(), &originalMs, removePreprocessOpNum, inputDesc));
    print_ms(originalMs);

    ModelSpecOptimizer msOptimizer;
    msOptimizer.suggest();
    msOptimizer.optimize(&originalMs);
    print_ms(originalMs);

    CHECK_STATUS(ms_datatype_converter(&originalMs, &targetMs, F32_to_F16));
    print_ms(targetMs);

    //serialize ms to ./bolt
    std::string modelStorePath;
    switch (qm) {
        case INT8_Q: {
            modelStorePath = std::string(argv[1]) + std::string(argv[2]) + std::string("_int8_q.bolt");
            targetMs.dt = DT_F16_8Q;
            break;
        }
        default: {
            modelStorePath = std::string(argv[1]) + std::string(argv[2]) + std::string("_f16.bolt");
            break;
        }
    }
    CHECK_STATUS(serialize_model_to_file(&targetMs, modelStorePath.c_str()));

    //deserialize ./bolt to ms in memory
    CHECK_STATUS(deserialize_model_from_file(modelStorePath.c_str(), &resultMs));
    print_ms(resultMs);

    CHECK_STATUS(mt_destroy_model(&originalMs));
    CHECK_STATUS(mt_destroy_model(&targetMs));
    CHECK_STATUS(mt_destroy_model(&resultMs));

    return 0;
}

