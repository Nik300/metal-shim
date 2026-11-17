#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  float4 tint_member;
};

struct tint_struct_1 {
  float4 tint_member_1;
};

struct tint_struct_2 {
  float4 tint_member_2 [[color(0)]];
};

struct tint_struct_3 {
  float4 tint_member_3 [[user(locn0)]] [[center_no_perspective]];
};

void v(tint_struct v_1, thread tint_struct_1* const v_2) {
  float4 const v_3 = v_1.tint_member;
  (*v_2).tint_member_1 = v_3;
}

tint_struct_1 v_4(tint_struct v_5) {
  tint_struct_1 v_6 = {};
  (v(v_5, (&v_6)));
  return v_6;
}

fragment tint_struct_2 dawn_entry_point(tint_struct_3 v_8 [[stage_in]]) {
  tint_struct_2 v_9 = {};
  v_9.tint_member_2 = v_4(tint_struct{.tint_member=v_8.tint_member_3}).tint_member_1;
  return v_9;
}
