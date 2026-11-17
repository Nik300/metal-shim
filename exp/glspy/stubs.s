# One 16-byte stub per GLIFunctionDispatch slot: r11 = slot index, then the common counter, then the original.
    .text
    .globl _glspy_stubs
    .p2align 4
_glspy_stubs:
    .set i, 0
    .rept 1400
    .p2align 4
    .byte 0x41, 0xbb
    .long i
    .byte 0xe9
    .long _glspy_common - . - 4
    .set i, i+1
    .endr

    .p2align 4
_glspy_common:
    push %rdi
    push %rsi
    push %rdx
    push %rcx
    push %r8
    push %r9
    push %r11
    sub $128, %rsp
    movdqu %xmm0, 0(%rsp)
    movdqu %xmm1, 16(%rsp)
    movdqu %xmm2, 32(%rsp)
    movdqu %xmm3, 48(%rsp)
    movdqu %xmm4, 64(%rsp)
    movdqu %xmm5, 80(%rsp)
    movdqu %xmm6, 96(%rsp)
    movdqu %xmm7, 112(%rsp)
    mov %r11, %rdi
    call _glspy_count
    movdqu 0(%rsp), %xmm0
    movdqu 16(%rsp), %xmm1
    movdqu 32(%rsp), %xmm2
    movdqu 48(%rsp), %xmm3
    movdqu 64(%rsp), %xmm4
    movdqu 80(%rsp), %xmm5
    movdqu 96(%rsp), %xmm6
    movdqu 112(%rsp), %xmm7
    add $128, %rsp
    pop %r11
    pop %r9
    pop %r8
    pop %rcx
    pop %rdx
    pop %rsi
    pop %rdi
    movq _glspy_orig@GOTPCREL(%rip), %rax
    jmp *(%rax,%r11,8)
