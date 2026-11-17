; ModuleID = 'air'
source_filename = "vs_depth"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64_v28-apple-macosx26.7.0"

%struct.U = type { <4 x float>, float, [12 x i8] }

; Function Attrs: mustprogress nofree norecurse nosync nounwind readnone willreturn
define <{ <4 x float>, <4 x float>, <2 x float> }> @vs_depth(<2 x float> %in.0, <4 x float> %in.1, %struct.U addrspace(2)* nocapture noundef readonly align 16 dereferenceable(32) "air-buffer-no-alias" %u) local_unnamed_addr #0 {
entry:
  %vecinit = shufflevector <2 x float> %in.0, <2 x float> poison, <4 x i32> <i32 0, i32 1, i32 undef, i32 undef>
  %depth = getelementptr inbounds %struct.U, %struct.U addrspace(2)* %u, i64 0, i32 1
  %0 = load float, float addrspace(2)* %depth, align 16, !tbaa !24, !alias.scope !29
  %1 = insertelement <4 x float> %vecinit, float 1.000000e+00, i64 3
  %vecinit3 = insertelement <4 x float> %1, float %0, i64 2
  %2 = insertvalue <{ <4 x float>, <4 x float>, <2 x float> }> undef, <4 x float> %vecinit3, 0
  %3 = insertvalue <{ <4 x float>, <4 x float>, <2 x float> }> %2, <4 x float> zeroinitializer, 1
  %4 = insertvalue <{ <4 x float>, <4 x float>, <2 x float> }> %3, <2 x float> zeroinitializer, 2
  ret <{ <4 x float>, <4 x float>, <2 x float> }> %4
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind readnone willreturn "approx-func-fp-math"="true" "frame-pointer"="all" "min-legal-vector-width"="128" "no-builtins" "no-infs-fp-math"="true" "no-nans-fp-math"="true" "no-signed-zeros-fp-math"="true" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "unsafe-fp-math"="true" }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}
!air.version = !{!9}
!air.language_version = !{!10}
!air.compile_options = !{!11, !12, !13}
!air.vertex = !{!14}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{i32 7, !"air.max_device_buffers", i32 31}
!3 = !{i32 7, !"air.max_constant_buffers", i32 31}
!4 = !{i32 7, !"air.max_threadgroup_buffers", i32 31}
!5 = !{i32 7, !"air.max_textures", i32 128}
!6 = !{i32 7, !"air.max_read_write_textures", i32 8}
!7 = !{i32 7, !"air.max_samplers", i32 16}
!8 = !{!"Apple metal version 32023.886 (metalfe-32023.886.1)"}
!9 = !{i32 2, i32 8, i32 0}
!10 = !{!"Metal", i32 4, i32 0, i32 0}
!11 = !{!"air.compile.denorms_disable"}
!12 = !{!"air.compile.fast_math_enable"}
!13 = !{!"air.compile.framebuffer_fetch_enable"}
!14 = !{<{ <4 x float>, <4 x float>, <2 x float> }> (<2 x float>, <4 x float>, %struct.U addrspace(2)*)* @vs_depth, !15, !19}
!15 = !{!16, !17, !18}
!16 = !{!"air.position", !"air.arg_type_name", !"float4", !"air.arg_name", !"pos"}
!17 = !{!"air.vertex_output", !"generated(5colorDv4_f)", !"air.arg_type_name", !"float4", !"air.arg_name", !"color"}
!18 = !{!"air.vertex_output", !"generated(2uvDv2_f)", !"air.arg_type_name", !"float2", !"air.arg_name", !"uv"}
!19 = !{!20, !21, !22}
!20 = !{i32 0, !"air.vertex_input", !"air.location_index", i32 0, i32 1, !"air.arg_type_name", !"float2", !"air.arg_name", !"pos"}
!21 = !{i32 1, !"air.vertex_input", !"air.location_index", i32 1, i32 1, !"air.arg_type_name", !"float4", !"air.arg_name", !"color", !"air.arg_unused"}
!22 = !{i32 2, !"air.buffer", !"air.buffer_size", i32 32, !"air.location_index", i32 1, i32 1, !"air.read", !"air.address_space", i32 2, !"air.struct_type_info", !23, !"air.arg_type_size", i32 32, !"air.arg_type_align_size", i32 16, !"air.arg_type_name", !"U", !"air.arg_name", !"u"}
!23 = !{i32 0, i32 16, i32 0, !"float4", !"tint", i32 16, i32 4, i32 0, !"float", !"depth"}
!24 = !{!25, !28, i64 16}
!25 = !{!"_ZTS1U", !26, i64 0, !28, i64 16}
!26 = !{!"omnipotent char", !27, i64 0}
!27 = !{!"Simple C++ TBAA"}
!28 = !{!"float", !26, i64 0}
!29 = !{!30}
!30 = distinct !{!30, !31, !"air-alias-scope-arg(2)"}
!31 = distinct !{!31, !"air-alias-scopes(vs_depth)"}
