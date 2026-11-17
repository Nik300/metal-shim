#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

struct tint_struct {
  uint tint_member;
  float2 tint_member_1;
  float4 tint_member_2;
  float4 tint_member_3;
  float4 tint_member_4;
  float tint_member_5;
  uint tint_member_6;
  float3 tint_member_7;
  float3 tint_member_8;
  float3 tint_member_9;
};

struct tint_struct_1 {
  float4 tint_member_10;
  uint tint_member_11;
  float2 tint_member_12;
  float4 tint_member_13;
};

struct tint_struct_4 {
  /* 0x0000 */ float4 tint_member_16;
  /* 0x0010 */ float2 tint_member_17;
  /* 0x0018 */ float2 tint_member_18;
  /* 0x0020 */ float4 tint_member_19;
  /* 0x0030 */ float tint_member_20;
  /* 0x0034 */ array<int8_t, 12> tint_pad;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_15;
};

struct tint_struct_6 {
  /* 0x0000 */ float4 tint_member_26;
  /* 0x0010 */ float4 tint_member_27;
};

struct tint_struct_5 {
  /* 0x0000 */ tint_struct_6 tint_member_25;
  /* 0x0020 */ uint tint_member_28;
  /* 0x0024 */ array<uint, 4> tint_member_29;
  /* 0x0034 */ array<int8_t, 12> tint_pad_1;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_14;
  thread uint* tint_member_21;
  const device array<uint, 1>* tint_member_22;
  const device array<uint, 1>* tint_member_23;
  const constant tint_struct_5* tint_member_24;
};

struct tint_struct_7 {
  float4 tint_member_30 [[position]];
  uint tint_member_31 [[user(locn0)]] [[flat]];
  float2 tint_member_32 [[user(locn1)]];
  float4 tint_member_33 [[user(locn2)]];
};

float3x3 v_1(float3x3 v_2) {
  float const v_3 = v_2[0].x;
  float const v_4 = v_2[0].y;
  float const v_5 = v_2[0].z;
  float const v_6 = v_2[1].x;
  float const v_7 = v_2[1].y;
  float const v_8 = v_2[1].z;
  float const v_9 = v_2[2].x;
  float const v_10 = v_2[2].y;
  float const v_11 = v_2[2].z;
  float const v_12 = ((v_11 * v_7) - (v_8 * v_10));
  float const v_13 = ((-(v_11) * v_6) + (v_8 * v_9));
  float const v_14 = ((v_10 * v_6) - (v_7 * v_9));
  float const v_15 = (((v_3 * v_12) + (v_4 * v_13)) + (v_5 * v_14));
  float3 const v_16 = float3(v_12, ((-(v_11) * v_4) + (v_5 * v_10)), ((v_8 * v_4) - (v_5 * v_7)));
  float3 const v_17 = float3(v_13, ((v_11 * v_3) - (v_5 * v_9)), ((-(v_8) * v_3) + (v_5 * v_6)));
  return (float3x3(v_16, v_17, float3(v_14, ((-(v_10) * v_3) + (v_4 * v_9)), ((v_7 * v_3) - (v_4 * v_6)))) * (1.0f / v_15));
}

float2 v_18(float2 v_19) {
  return float2(-(v_19.y), v_19.x);
}

uint v_20(uint v_21, uint v_22) {
  uint const v_23 = select(v_22, 1u, (v_22 == 0u));
  return (v_21 - ((v_21 / v_23) * v_23));
}

float4 v_24(uint v_25, float2 v_26, float4 v_27, float4 v_28, float4 v_29, float v_30, float3x3 v_31, thread float4* const v_32, thread float2* const v_33) {
  float4 v_34 = v_27;
  uint const v_35 = v_20((v_25 + 1u), 4u);
  float4 v_36 = (v_28 - v_28.wxyz);
  float4 v_37 = (v_29 - v_29.wxyz);
  float4 const v_38 = (1.0f / max(abs(v_36), max(abs(v_37), float4(1.0f))));
  v_36 = (v_36 * v_38);
  v_37 = (v_37 * v_38);
  float4 v_39 = ((v_36 * v_36) + (v_37 * v_37));
  float4 const v_40 = sign(v_39);
  if (any((v_40 == float4(0.0f)))) {
    if (all((v_40 == float4(0.0f)))) {
      v_36 = float4(0.0f, 1.0f, 0.0f, -1.0f);
      v_37 = float4(-1.0f, 0.0f, 1.0f, 0.0f);
      v_39 = float4(1.0f);
    } else {
      bool const v_41 = ((((v_40.x + v_40.y) + v_40.z) + v_40.w) > 2.5f);
      float4 const v_42 = v_37.yzwx;
      float4 const v_43 = v_36.yzwx;
      float4 const v_44 = select(v_42, v_43, bool4(v_41));
      float4 const v_45 = -(v_36.yzwx);
      float4 const v_46 = v_37.yzwx;
      float4 const v_47 = select(v_45, v_46, bool4(v_41));
      v_36 = mix(v_44, v_36, v_40);
      v_37 = mix(v_47, v_37, v_40);
      v_39 = mix(v_39.yzwx, v_39, v_40);
      v_34 = mix(v_34.yzwx, v_34, v_40);
    }
  }
  float4 const v_48 = rsqrt(v_39);
  v_36 = (v_36 * v_48);
  v_37 = (v_37 * v_48);
  float2 const v_49 = -(float2(v_36[v_35], v_37[v_35]));
  float2 const v_50 = float2(v_36[v_25], v_37[v_25]);
  float2 const v_51 = float2(v_28[v_25], v_29[v_25]);
  (*v_32) = ((v_37 * (v_28 - v_51.x)) - (v_36 * (v_29 - v_51.y)));
  float3x3 const v_52 = v_1(v_31);
  float3 v_53 = (v_31 * float3(v_51, 1.0f));
  float4 const v_54 = ((-(v_37) * (v_52[0].x - (v_52[0].z * v_28))) + (v_36 * (v_52[0].y - (v_52[0].z * v_29))));
  float4 const v_55 = ((-(v_37) * (v_52[1].x - (v_52[1].z * v_28))) + (v_36 * (v_52[1].y - (v_52[1].z * v_29))));
  (*v_32) = ((*v_32) * rsqrt(((v_54 * v_54) + (v_55 * v_55))));
  (*v_32) = ((*v_32) + ((1.5f - v_34) * abs(v_53.z)));
  bool v_56 = false;
  if (any((v_26 != float2(0.0f)))) {
    v_56 = (v_53.z > 0.0f);
  } else {
    v_56 = false;
  }
  if (v_56) {
    float2 const v_57 = (v_52[0].xy - (v_52[0].z * v_51));
    float2 const v_58 = (v_52[1].xy - (v_52[1].z * v_51));
    float2 const v_59 = float2(v_57.x, v_57.y);
    float2x2 const v_60 = float2x2(v_59, float2(v_58.x, v_58.y));
    float2 const v_61 = (float2(v_34[v_25], v_34[v_35]) * v_26);
    float2 v_62 = ((v_61.x * v_18(-(v_50))) * v_60);
    float2 v_63 = ((v_61.y * v_18(v_49)) * v_60);
    bool const v_64 = all((v_61 != float2(0.0f)));
    if (v_64) {
      v_62 = normalize(v_62);
      v_63 = normalize(v_63);
      if ((dot(v_62, v_63) < -0.80000001192092895508f)) {
        float const v_65 = v_63.x;
        float const v_66 = v_63.y;
        float2 const v_67 = float2(v_62.x, v_62.y);
        float const v_68 = sign(determinant(float2x2(v_67, float2(v_65, v_66))));
        v_62 = (v_68 * v_18(v_62));
        v_63 = (-(v_68) * v_18(v_63));
      }
    }
    v_53 = float3((v_53.xy + (v_53.z * normalize((v_62 + v_63)))), v_53.z);
    (*v_32) = ((*v_32) - v_53.z);
  }
  (*v_33) = v_51;
  return float4(v_53.xy, (v_53.z * v_30), v_53.z);
}

void v_69(tint_struct v_70, thread tint_struct_1* const v_71, tint_struct_2 v_72) {
  float2 v_73 = float2(0.0f);
  (*v_72.tint_member_21) = v_70.tint_member_6;
  float4 v_74 = 0.0f;
  float2 v_75 = 0.0f;
  float3 const v_76 = float3(v_70.tint_member_7.x, v_70.tint_member_7.y, v_70.tint_member_7.z);
  float3 const v_77 = float3(v_70.tint_member_8.x, v_70.tint_member_8.y, v_70.tint_member_8.z);
  float4 const v_78 = v_24(v_70.tint_member, v_70.tint_member_1, v_70.tint_member_2, v_70.tint_member_3, v_70.tint_member_4, v_70.tint_member_5, float3x3(v_76, v_77, float3(v_70.tint_member_9.x, v_70.tint_member_9.y, v_70.tint_member_9.z)), (&v_74), (&v_75));
  (*v_71).tint_member_13 = v_74;
  v_73 = v_75;
  float4 const v_79 = v_78;
  (*v_71).tint_member_10 = float4((((*v_72.tint_member_24).tint_member_25.tint_member_26.zw * v_79.xy) - (sign((*v_72.tint_member_24).tint_member_25.tint_member_26.zw) * v_79.ww)), v_79.zw);
  float2 const v_80 = (*v_72.tint_member_14).tint_member_15[(*v_72.tint_member_21)].tint_member_16.xy;
  float2 const v_81 = (*v_72.tint_member_14).tint_member_15[(*v_72.tint_member_21)].tint_member_16.zw;
  float2 const v_82 = float2(v_80.x, v_80.y);
  float2x2 const v_83 = float2x2(v_82, float2(v_81.x, v_81.y));
  (*v_71).tint_member_12 = ((v_83 * v_73) + (*v_72.tint_member_14).tint_member_15[(*v_72.tint_member_21)].tint_member_17);
  (*v_71).tint_member_11 = (*v_72.tint_member_21);
}

tint_struct_1 v_84(uint v_85, uint v_86, tint_struct_2 v_87) {
  uint const v_88 = (v_85 * 3u);
  uint const v_89 = (v_86 * 20u);
  uint const v_90 = (*v_87.tint_member_22)[v_88];
  float2 const v_91 = float2(as_type<float>((*v_87.tint_member_22)[(v_88 + 1u)]), as_type<float>((*v_87.tint_member_22)[(v_88 + 2u)]));
  float4 const v_92 = unpack_unorm4x8_to_float((*v_87.tint_member_23)[v_89]);
  float4 const v_93 = float4(as_type<float>((*v_87.tint_member_23)[(v_89 + 1u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 2u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 3u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 4u)]));
  float4 const v_94 = float4(as_type<float>((*v_87.tint_member_23)[(v_89 + 5u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 6u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 7u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 8u)]));
  float const v_95 = as_type<float>((*v_87.tint_member_23)[(v_89 + 9u)]);
  uint const v_96 = (*v_87.tint_member_23)[(v_89 + 10u)];
  float3 const v_97 = float3(as_type<float>((*v_87.tint_member_23)[(v_89 + 11u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 12u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 13u)]));
  float3 const v_98 = float3(as_type<float>((*v_87.tint_member_23)[(v_89 + 14u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 15u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 16u)]));
  tint_struct_1 v_99 = {};
  (v_69(tint_struct{.tint_member=v_90, .tint_member_1=v_91, .tint_member_2=v_92, .tint_member_3=v_93, .tint_member_4=v_94, .tint_member_5=v_95, .tint_member_6=v_96, .tint_member_7=v_97, .tint_member_8=v_98, .tint_member_9=float3(as_type<float>((*v_87.tint_member_23)[(v_89 + 17u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 18u)]), as_type<float>((*v_87.tint_member_23)[(v_89 + 19u)]))}, (&v_99), v_87));
  return v_99;
}

vertex tint_struct_7 dawn_entry_point(uint v_101 [[vertex_id]], uint v_102 [[instance_id]], const device tint_struct_3* v_103 [[buffer(1)]], const device array<uint, 1>* v_104 [[buffer(2)]], const device array<uint, 1>* v_105 [[buffer(3)]], const constant tint_struct_5* v_106 [[buffer(30)]]) {
  thread uint v_107 = 0u;
  tint_struct_2 const v_108 = tint_struct_2{.tint_member_14=v_103, .tint_member_21=(&v_107), .tint_member_22=v_104, .tint_member_23=v_105, .tint_member_24=v_106};
  tint_struct_1 const v_109 = v_84(v_101, v_102, v_108);
  tint_struct_7 v_110 = {};
  v_110.tint_member_30 = v_109.tint_member_10;
  v_110.tint_member_31 = v_109.tint_member_11;
  v_110.tint_member_32 = v_109.tint_member_12;
  v_110.tint_member_33 = v_109.tint_member_13;
  return v_110;
}
