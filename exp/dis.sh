#!/bin/zsh
# usage: dis.sh Class selector [count]  — disassemble an ObjC method IMP from the dyld cache via lldb
lldb -b -o 'b exit' -o run \
  -o 'expr -l objc -- (void)dlopen("/System/Library/Extensions/AppleParavirtGPUMetal.bundle/Contents/MacOS/AppleParavirtGPUMetal",2)' \
  -o "expr -l objc -- (uint64_t)(void*)class_getMethodImplementation((Class)objc_getClass(\"$1\"), (SEL)sel_registerName(\"$2\"))" \
  -o "disassemble -c ${3:-80} -s \$0" ./init0 2>&1 | sed -n '/disassemble -c/,$p'
