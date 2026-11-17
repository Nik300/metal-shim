#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  float4 tint_member;
  uint tint_member_1;
  float4 tint_member_2;
};

struct tint_struct_1 {
  float4 tint_member_3;
  float4 tint_member_4;
};

struct tint_struct_4 {
  /* 0x0000 */ float4 tint_member_7;
  /* 0x0010 */ float4 tint_member_8;
  /* 0x0020 */ float2 tint_member_9;
  /* 0x0028 */ array<int8_t, 8> tint_pad;
  /* 0x0030 */ float4 tint_member_10;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_6;
};

struct tint_struct_6 {
  /* 0x0000 */ float4 tint_member_14;
  /* 0x0010 */ float4 tint_member_15;
};

struct tint_struct_5 {
  /* 0x0000 */ tint_struct_6 tint_member_13;
  /* 0x0020 */ uint tint_member_16;
  /* 0x0024 */ array<uint, 2> tint_member_17;
  /* 0x002c */ array<int8_t, 4> tint_pad_1;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_5;
  thread uint* tint_member_11;
  const constant tint_struct_5* tint_member_12;
};

struct tint_struct_7 {
  float4 tint_member_18 [[color(0)]] [[index(0)]];
  float4 tint_member_19 [[color(0)]] [[index(1)]];
};

struct tint_struct_8 {
  uint tint_member_20 [[user(locn0)]] [[flat]];
  float4 tint_member_21 [[user(locn1)]] [[center_no_perspective]];
};

void v(tint_struct v_1, thread tint_struct_1* const v_2, tint_struct_2 v_3) {
  (*v_3.tint_member_11) = v_1.tint_member_1;
  float4 const v_4 = v_1.tint_member_2;
  float4 v_5 = float4(1.0f);
  float2 const v_6 = (v_1.tint_member.xy - (*v_3.tint_member_12).tint_member_13.tint_member_14.xy);
  float4 const v_7 = (*v_3.tint_member_5).tint_member_6[(*v_3.tint_member_11)].tint_member_8;
  float2 const v_8 = (*v_3.tint_member_5).tint_member_6[(*v_3.tint_member_11)].tint_member_9;
  float4 const v_9 = (*v_3.tint_member_5).tint_member_6[(*v_3.tint_member_11)].tint_member_10;
  float2 const v_10 = float2(abs(v_8.x));
  float2 const v_11 = (float2(v_9.xy) * ((v_7.xy + v_10) - v_6));
  float2 const v_12 = (float2(v_9.zw) * (v_6 - (v_7.zw - v_10)));
  float2 const v_13 = max(max(v_11, v_12), float2(0.0f));
  float const v_14 = float(saturate((v_10.x * (1.0f - length((v_13 * v_8.y))))));
  float2 const v_15 = float2((v_6 - v_7.xy));
  float4 v_16 = saturate(float4(v_15, float2((v_7.zw - v_6))));
  v_16 = mix(v_16, float4(1.0f), v_9);
  float v_17 = ((((v_14 * v_16.x) * v_16.y) * v_16.z) * v_16.w);
  float v_18 = 0.0f;
  if ((v_8.x < 0.0f)) {
    v_18 = (1.0f - v_17);
  } else {
    v_18 = v_17;
  }
  v_17 = v_18;
  float4 const v_19 = float4(v_17);
  v_5 = (v_5 * v_19.w);
  (*v_2).tint_member_3 = (v_4 * v_5);
  (*v_2).tint_member_4 = v_5;
}

tint_struct_1 v_20(tint_struct v_21, tint_struct_2 v_22) {
  tint_struct_1 v_23 = {};
  (v(v_21, (&v_23), v_22));
  return v_23;
}

fragment tint_struct_7 dawn_entry_point(float4 v_25 [[position]], tint_struct_8 v_26 [[stage_in]], const device tint_struct_3* v_27 [[buffer(1)]], const constant tint_struct_5* v_28 [[buffer(30)]]) {
  thread uint v_29 = 0u;
  tint_struct_2 const v_30 = tint_struct_2{.tint_member_5=v_27, .tint_member_11=(&v_29), .tint_member_12=v_28};
  tint_struct_1 const v_31 = v_20(tint_struct{.tint_member=v_25, .tint_member_1=v_26.tint_member_20, .tint_member_2=v_26.tint_member_21}, v_30);
  tint_struct_7 v_32 = {};
  v_32.tint_member_18 = v_31.tint_member_3;
  v_32.tint_member_19 = v_31.tint_member_4;
  return v_32;
}
