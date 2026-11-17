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
  /* 0x0020 */ float tint_member_10;
  /* 0x0024 */ array<int8_t, 12> tint_pad;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_6;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_5;
  thread uint* tint_member_11;
  sampler tint_member_12;
  texture2d<float, access::sample> tint_member_13;
};

struct tint_struct_5 {
  float4 tint_member_14 [[color(0)]];
};

struct tint_struct_6 {
  uint tint_member_15 [[user(locn0)]] [[flat]];
  float2 tint_member_16 [[user(locn1)]];
  float4 tint_member_17 [[user(locn2)]];
};

void v(tint_struct v_1, thread tint_struct_1* const v_2, tint_struct_2 v_3) {
  (*v_3.tint_member_11) = v_1.tint_member_1;
  float4 v_4 = 0.0f;
  float4 const v_5 = v_3.tint_member_13.sample(v_3.tint_member_12, v_1.tint_member_2, bias(-0.47499999403953552246f));
  float const v_6 = (*v_3.tint_member_5).tint_member_6[(*v_3.tint_member_11)].tint_member_10;
  if ((v_6 < 0.0f)) {
    v_4 = float4((v_5.xyz / max(v_5.w, 0.00009999999747378752f)), v_5.w);
  } else {
    float const v_7 = max(v_5.w, (v_6 - 1.0f));
    float const v_8 = max(v_7, (1.0f - v_6));
    v_4 = float4((v_5.xyz * v_8), v_7);
  }
  float4 const v_9 = v_4;
  float4 v_10 = float4(1.0f);
  float2 const v_11 = min(v_1.tint_member_3.xy, v_1.tint_member_3.zw);
  float const v_12 = (min(v_11.x, v_11.y) * v_1.tint_member.w);
  v_10 = float4(float(saturate(v_12)));
  (*v_2).tint_member_4 = (v_9 * v_10);
}

tint_struct_1 v_13(tint_struct v_14, tint_struct_2 v_15) {
  tint_struct_1 v_16 = {};
  (v(v_14, (&v_16), v_15));
  return v_16;
}

fragment tint_struct_5 dawn_entry_point(float4 v_18 [[position]], tint_struct_6 v_19 [[stage_in]], const device tint_struct_3* v_20 [[buffer(1)]], sampler v_21 [[sampler(0)]], texture2d<float, access::sample> v_22 [[texture(0)]]) {
  thread uint v_23 = 0u;
  tint_struct_2 const v_24 = tint_struct_2{.tint_member_5=v_20, .tint_member_11=(&v_23), .tint_member_12=v_21, .tint_member_13=v_22};
  tint_struct_5 v_25 = {};
  v_25.tint_member_14 = v_13(tint_struct{.tint_member=v_18, .tint_member_1=v_19.tint_member_15, .tint_member_2=v_19.tint_member_16, .tint_member_3=v_19.tint_member_17}, v_24).tint_member_4;
  return v_25;
}
