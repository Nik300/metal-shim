#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  uint tint_member;
  float4 tint_member_1;
  float tint_member_2;
  uint tint_member_3;
  float3 tint_member_4;
  float3 tint_member_5;
  float3 tint_member_6;
};

struct tint_struct_1 {
  float4 tint_member_7;
  uint tint_member_8;
  float4 tint_member_9;
};

struct tint_struct_4 {
  /* 0x0000 */ float4 tint_member_12;
  /* 0x0010 */ float4 tint_member_13;
  /* 0x0020 */ float2 tint_member_14;
  /* 0x0028 */ array<int8_t, 8> tint_pad;
  /* 0x0030 */ float4 tint_member_15;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_11;
};

struct tint_struct_6 {
  /* 0x0000 */ float4 tint_member_20;
  /* 0x0010 */ float4 tint_member_21;
};

struct tint_struct_5 {
  /* 0x0000 */ tint_struct_6 tint_member_19;
  /* 0x0020 */ uint tint_member_22;
  /* 0x0024 */ array<uint, 3> tint_member_23;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_10;
  thread uint* tint_member_16;
  const device array<uint, 1>* tint_member_17;
  const constant tint_struct_5* tint_member_18;
};

struct tint_struct_7 {
  float4 tint_member_24 [[position]];
  uint tint_member_25 [[user(locn0)]] [[flat]];
  float4 tint_member_26 [[user(locn1)]] [[center_no_perspective]];
};

float3x3 v(float3x3 v_1) {
  float const v_2 = v_1[0].x;
  float const v_3 = v_1[0].y;
  float const v_4 = v_1[0].z;
  float const v_5 = v_1[1].x;
  float const v_6 = v_1[1].y;
  float const v_7 = v_1[1].z;
  float const v_8 = v_1[2].x;
  float const v_9 = v_1[2].y;
  float const v_10 = v_1[2].z;
  float const v_11 = ((v_10 * v_6) - (v_7 * v_9));
  float const v_12 = ((-(v_10) * v_5) + (v_7 * v_8));
  float const v_13 = ((v_9 * v_5) - (v_6 * v_8));
  float const v_14 = (((v_2 * v_11) + (v_3 * v_12)) + (v_4 * v_13));
  float3 const v_15 = float3(v_11, ((-(v_10) * v_3) + (v_4 * v_9)), ((v_7 * v_3) - (v_4 * v_6)));
  float3 const v_16 = float3(v_12, ((v_10 * v_2) - (v_4 * v_8)), ((-(v_7) * v_2) + (v_4 * v_5)));
  return (float3x3(v_15, v_16, float3(v_13, ((-(v_9) * v_2) + (v_3 * v_8)), ((v_6 * v_2) - (v_3 * v_5)))) * (1.0f / v_14));
}

float4 v_17(float2 v_18, float4 v_19, float v_20, float3x3 v_21, thread float2* const v_22) {
  float2 v_23 = v_18;
  if (all((v_19.xy <= v_19.zw))) {
    v_23 = mix(v_19.xy, v_19.zw, v_23);
    float3 const v_24 = (v_21 * float3(v_23, 1.0f));
    (*v_22) = v_23;
    return float4(v_24.xy, (v_20 * v_24.z), v_24.z);
  } else {
    v_23 = mix(v_19.zw, v_19.xy, v_23);
    float3x3 const v_25 = v(v_21);
    float3 const v_26 = (v_25 * float3(v_23, 1.0f));
    float const v_27 = (1.0f / v_26.z);
    (*v_22) = (v_26.xy * v_27);
    return float4((v_23 * v_27), (v_20 * v_27), v_27);
  }
  /* unreachable */
  return 0.0f;
}

int v_28(int v_29, int v_30) {
  uint const v_31 = uint((v_29 == (-2147483647 - 1)));
  bool const v_32 = bool((v_31 & uint((v_30 == -1))));
  uint const v_33 = uint((v_30 == 0));
  int const v_34 = select(v_30, 1, bool((v_33 | uint(v_32))));
  return as_type<int>((as_type<uint>(v_29) - as_type<uint>(as_type<int>((as_type<uint>((v_29 / v_34)) * as_type<uint>(v_34))))));
}

int v_35(int v_36, int v_37) {
  uint const v_38 = uint((v_36 == (-2147483647 - 1)));
  bool const v_39 = bool((v_38 & uint((v_37 == -1))));
  uint const v_40 = uint((v_37 == 0));
  return (v_36 / select(v_37, 1, bool((v_40 | uint(v_39)))));
}

void v_41(tint_struct v_42, thread tint_struct_1* const v_43, tint_struct_2 v_44) {
  float2 v_45 = float2(0.0f);
  (*v_44.tint_member_16) = v_42.tint_member_3;
  float2 v_46 = 0.0f;
  float const v_47 = float(v_35(int(v_42.tint_member), 2));
  float2 const v_48 = float2(v_47, float(v_28(int(v_42.tint_member), 2)));
  float3 const v_49 = float3(v_42.tint_member_4.x, v_42.tint_member_4.y, v_42.tint_member_4.z);
  float3 const v_50 = float3(v_42.tint_member_5.x, v_42.tint_member_5.y, v_42.tint_member_5.z);
  float4 const v_51 = v_17(v_48, v_42.tint_member_1, v_42.tint_member_2, float3x3(v_49, v_50, float3(v_42.tint_member_6.x, v_42.tint_member_6.y, v_42.tint_member_6.z)), (&v_46));
  v_45 = v_46;
  float4 const v_52 = v_51;
  (*v_43).tint_member_7 = float4((((*v_44.tint_member_18).tint_member_19.tint_member_20.zw * v_52.xy) - (sign((*v_44.tint_member_18).tint_member_19.tint_member_20.zw) * v_52.ww)), v_52.zw);
  (*v_43).tint_member_9 = float4((*v_44.tint_member_10).tint_member_11[(*v_44.tint_member_16)].tint_member_12);
  (*v_43).tint_member_8 = (*v_44.tint_member_16);
}

tint_struct_1 v_53(uint v_54, uint v_55, tint_struct_2 v_56) {
  uint const v_57 = (v_55 * 15u);
  float4 const v_58 = float4(as_type<float>((*v_56.tint_member_17)[v_57]), as_type<float>((*v_56.tint_member_17)[(v_57 + 1u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 2u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 3u)]));
  float const v_59 = as_type<float>((*v_56.tint_member_17)[(v_57 + 4u)]);
  uint const v_60 = (*v_56.tint_member_17)[(v_57 + 5u)];
  float3 const v_61 = float3(as_type<float>((*v_56.tint_member_17)[(v_57 + 6u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 7u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 8u)]));
  float3 const v_62 = float3(as_type<float>((*v_56.tint_member_17)[(v_57 + 9u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 10u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 11u)]));
  tint_struct_1 v_63 = {};
  (v_41(tint_struct{.tint_member=v_54, .tint_member_1=v_58, .tint_member_2=v_59, .tint_member_3=v_60, .tint_member_4=v_61, .tint_member_5=v_62, .tint_member_6=float3(as_type<float>((*v_56.tint_member_17)[(v_57 + 12u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 13u)]), as_type<float>((*v_56.tint_member_17)[(v_57 + 14u)]))}, (&v_63), v_56));
  return v_63;
}

vertex tint_struct_7 dawn_entry_point(uint v_65 [[vertex_id]], uint v_66 [[instance_id]], const device tint_struct_3* v_67 [[buffer(1)]], const device array<uint, 1>* v_68 [[buffer(2)]], const constant tint_struct_5* v_69 [[buffer(30)]]) {
  thread uint v_70 = 0u;
  tint_struct_2 const v_71 = tint_struct_2{.tint_member_10=v_67, .tint_member_16=(&v_70), .tint_member_17=v_68, .tint_member_18=v_69};
  tint_struct_1 const v_72 = v_53(v_65, v_66, v_71);
  tint_struct_7 v_73 = {};
  v_73.tint_member_24 = v_72.tint_member_7;
  v_73.tint_member_25 = v_72.tint_member_8;
  v_73.tint_member_26 = v_72.tint_member_9;
  return v_73;
}
