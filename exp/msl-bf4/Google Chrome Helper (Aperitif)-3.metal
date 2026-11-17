#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  float4 tint_member;
  uint tint_member_1;
  float2 tint_member_2;
  float4 tint_member_3;
};

struct tint_struct_1 {
  float4 tint_member_4;
};

struct tint_struct_4 {
  /* 0x0000 */ float4 tint_member_7;
  /* 0x0010 */ float2 tint_member_8;
  /* 0x0018 */ float2 tint_member_9;
  /* 0x0020 */ float4 tint_member_10;
  /* 0x0030 */ float tint_member_11;
  /* 0x0034 */ array<int8_t, 12> tint_pad;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_6;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_5;
  thread uint* tint_member_12;
  sampler tint_member_13;
  texture2d<float, access::sample> tint_member_14;
};

struct tint_struct_5 {
  float4 tint_member_15 [[color(0)]];
};

struct tint_struct_6 {
  uint tint_member_16 [[user(locn0)]] [[flat]];
  float2 tint_member_17 [[user(locn1)]];
  float4 tint_member_18 [[user(locn2)]];
};

float4 v(float2 v_1, float2 v_2, texture2d<float, access::sample> v_3, sampler v_4) {
  return v_3.sample(v_4, (v_1 * v_2), bias(-0.47499999403953552246f));
}

void v_5(tint_struct v_6, thread tint_struct_1* const v_7, tint_struct_2 v_8) {
  (*v_8.tint_member_12) = v_6.tint_member_1;
  float4 const v_9 = (*v_8.tint_member_5).tint_member_6[(*v_8.tint_member_12)].tint_member_10;
  float4 v_10 = 0.0f;
  float4 const v_11 = v(min(max(v_6.tint_member_2, v_9.xy), v_9.zw), (*v_8.tint_member_5).tint_member_6[(*v_8.tint_member_12)].tint_member_9, v_8.tint_member_14, v_8.tint_member_13);
  float const v_12 = (*v_8.tint_member_5).tint_member_6[(*v_8.tint_member_12)].tint_member_11;
  if ((v_12 < 0.0f)) {
    v_10 = float4((v_11.xyz / max(v_11.w, 0.00009999999747378752f)), v_11.w);
  } else {
    float const v_13 = max(v_11.w, (v_12 - 1.0f));
    float const v_14 = max(v_13, (1.0f - v_12));
    v_10 = float4((v_11.xyz * v_14), v_13);
  }
  float4 const v_15 = v_10;
  float4 v_16 = float4(1.0f);
  float2 const v_17 = min(v_6.tint_member_3.xy, v_6.tint_member_3.zw);
  float const v_18 = (min(v_17.x, v_17.y) * v_6.tint_member.w);
  v_16 = float4(float(saturate(v_18)));
  (*v_7).tint_member_4 = (v_15 * v_16);
}

tint_struct_1 v_19(tint_struct v_20, tint_struct_2 v_21) {
  tint_struct_1 v_22 = {};
  (v_5(v_20, (&v_22), v_21));
  return v_22;
}

fragment tint_struct_5 dawn_entry_point(float4 v_24 [[position]], tint_struct_6 v_25 [[stage_in]], const device tint_struct_3* v_26 [[buffer(1)]], sampler v_27 [[sampler(0)]], texture2d<float, access::sample> v_28 [[texture(0)]]) {
  thread uint v_29 = 0u;
  tint_struct_2 const v_30 = tint_struct_2{.tint_member_5=v_26, .tint_member_12=(&v_29), .tint_member_13=v_27, .tint_member_14=v_28};
  tint_struct_5 v_31 = {};
  v_31.tint_member_15 = v_19(tint_struct{.tint_member=v_24, .tint_member_1=v_25.tint_member_16, .tint_member_2=v_25.tint_member_17, .tint_member_3=v_25.tint_member_18}, v_30).tint_member_4;
  return v_31;
}
