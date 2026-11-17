#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  uint tint_member;
  float2 tint_member_1;
};

struct tint_struct_1 {
  float4 tint_member_2;
};

struct tint_struct_4 {
  /* 0x0000 */ array<float4, 14> tint_member_5;
  /* 0x00e0 */ float2 tint_member_6;
  /* 0x00e8 */ array<int8_t, 8> tint_pad;
  /* 0x00f0 */ float4 tint_member_7;
  /* 0x0100 */ float2 tint_member_8;
  /* 0x0108 */ float2 tint_member_9;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_4;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_3;
  thread uint* tint_member_10;
  sampler tint_member_11;
  texture2d<float, access::sample> tint_member_12;
};

struct tint_struct_5 {
  float4 tint_member_13 [[color(0)]];
};

struct tint_struct_6 {
  uint tint_member_14 [[user(locn0)]] [[flat]];
  float2 tint_member_15 [[user(locn1)]];
};

void v(tint_struct v_1, thread tint_struct_1* const v_2, tint_struct_2 v_3) {
  (*v_3.tint_member_10) = v_1.tint_member;
  float4 v_4 = float4(0.0f);
  int v_5 = 0;
  {
    while(true) {
      if ((v_5 < 8)) {
      } else {
        break;
      }
      float4 const v_6 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_5[v_5];
      float2 const v_7 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_7.xy;
      float2 const v_8 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_7.zw;
      float4 const v_9 = v_4;
      float2 const v_10 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_9;
      float2 const v_11 = float2(v_7.x, v_7.y);
      float2x2 const v_12 = float2x2(v_11, float2(v_8.x, v_8.y));
      float2 const v_13 = (v_12 * (v_1.tint_member_1 + float2((v_6.x * (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_6))));
      float2 const v_14 = (v_10 * (v_13 + (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_8));
      v_4 = (v_9 + (v_6.y * v_3.tint_member_12.sample(v_3.tint_member_11, v_14, bias(-0.47499999403953552246f))));
      float2 const v_15 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_7.xy;
      float2 const v_16 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_7.zw;
      float4 const v_17 = v_4;
      float2 const v_18 = (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_9;
      float2 const v_19 = float2(v_15.x, v_15.y);
      float2x2 const v_20 = float2x2(v_19, float2(v_16.x, v_16.y));
      float2 const v_21 = (v_20 * (v_1.tint_member_1 + float2((v_6.z * (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_6))));
      float2 const v_22 = (v_18 * (v_21 + (*v_3.tint_member_3).tint_member_4[(*v_3.tint_member_10)].tint_member_8));
      v_4 = (v_17 + (v_6.w * v_3.tint_member_12.sample(v_3.tint_member_11, v_22, bias(-0.47499999403953552246f))));
      {
        v_5 = as_type<int>((as_type<uint>(v_5) + 1u));
      }
    }
  }
  float4 const v_23 = v_4;
  (*v_2).tint_member_2 = v_23;
}

tint_struct_1 v_24(tint_struct v_25, tint_struct_2 v_26) {
  tint_struct_1 v_27 = {};
  (v(v_25, (&v_27), v_26));
  return v_27;
}

fragment tint_struct_5 dawn_entry_point(tint_struct_6 v_29 [[stage_in]], const device tint_struct_3* v_30 [[buffer(1)]], sampler v_31 [[sampler(0)]], texture2d<float, access::sample> v_32 [[texture(0)]]) {
  thread uint v_33 = 0u;
  tint_struct_2 const v_34 = tint_struct_2{.tint_member_3=v_30, .tint_member_10=(&v_33), .tint_member_11=v_31, .tint_member_12=v_32};
  tint_struct_5 v_35 = {};
  v_35.tint_member_13 = v_24(tint_struct{.tint_member=v_29.tint_member_14, .tint_member_1=v_29.tint_member_15}, v_34).tint_member_2;
  return v_35;
}
