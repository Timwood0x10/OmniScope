#!/bin/bash
# Batch translate common Chinese patterns in markdown files
FILES=$(find . -name "*.md" -not -path "./.git/*" -not -path "./zig-cache/*" -not -path "*/zh/*" -not -name "*_zh.md" -not -path "./plan/*" | xargs grep -lE '(修复|检测|分析|测试|通过|问题|漏洞|内存|安全|功能|版本|核心|突破|根因|报告|结果|数据|基准|性能|优化|改进|失败|成功|完成|验证|注意|说明|总结|概述|简介)' 2>/dev/null)

for f in $FILES; do
  sed -i '' \
    -e 's/检测到/detected/g' \
    -e 's/检测结果/Detection Results/g' \
    -e 's/检测能力/Detection Capability/g' \
    -e 's/测试文件/Test File/g' \
    -e 's/测试结果/Test Results/g' \
    -e 's/测试通过/Test Passed/g' \
    -e 's/分析结果/Analysis Results/g' \
    -e 's/静态分析/Static Analysis/g' \
    -e 's/内存泄漏/Memory Leak/g' \
    -e 's/内存安全/Memory Safety/g' \
    -e 's/安全问题/Security Issue/g' \
    -e 's/边界违规/Boundary Violation/g' \
    -e 's/FFI 边界/FFI Boundary/g' \
    -e 's/跨语言/Cross-Language/g' \
    -e 's/函数名/Function Name/g' \
    -e 's/函数数量/Function Count/g' \
    -e 's/总函数数/Total Functions/g' \
    -e 's/总问题数/Total Issues/g' \
    -e 's/准确率/Accuracy/g' \
    -e 's/精确度/Precision/g' \
    -e 's/召回率/Recall/g' \
    -e 's/误报率/False Positive Rate/g' \
    -e 's/漏报率/False Negative Rate/g' \
    -e 's/真阳性/True Positive/g' \
    -e 's/假阳性/False Positive/g' \
    -e 's/真阴性/True Negative/g' \
    -e 's/假阴性/False Negative/g' \
    -e 's/注意事项/Notes/g' \
    -e 's/改进建议/Improvement Suggestions/g' \
    -e 's/未来工作/Future Work/g' \
    -e 's/已知限制/Known Limitations/g' \
    -e 's/结论/Conclusion/g' \
    -e 's/总结/Summary/g' \
    -e 's/概述/Overview/g' \
    -e 's/简介/Introduction/g' \
    -e 's/背景/Background/g' \
    -e 's/目标/Objective/g' \
    -e 's/方法/Method/g' \
    -e 's/环境/Environment/g' \
    -e 's/配置/Configuration/g' \
    -e 's/参数/Parameters/g' \
    -e 's/输出/Output/g' \
    -e 's/格式/Format/g' \
    -e 's/最后更新/Last Updated/g' \
    -e 's/修复/Fix/g' \
    -e 's/已修复/Fixed/g' \
    -e 's/核心/Core/g' \
    -e 's/突破/Breakthrough/g' \
    -e 's/根因/Root Cause/g' \
    -e 's/基准/Benchmark/g' \
    -e 's/实际/Actual/g' \
    -e 's/预期/Expected/g' \
    "$f" 2>/dev/null
done
echo "Done: processed $(echo "$FILES" | wc -w | tr -d ' ') files"
