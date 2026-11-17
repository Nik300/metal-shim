#ifdef __clang__
#pragma clang diagnostic ignored "-Wall"
#endif

#pragma METAL fp math_mode(relaxed)
#include <metal_stdlib>
using namespace metal;

volatile constexpr constant uint tint_volatile_zero = 0u;

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
  /* 0x0110 */ float4 tint_member_10;
  /* 0x0120 */ int tint_member_11;
  /* 0x0124 */ int tint_member_12;
  /* 0x0128 */ int tint_member_13;
  /* 0x012c */ array<int8_t, 4> tint_pad_1;
};

struct tint_struct_3 {
  /* 0x0000 */ array<tint_struct_4, 1> tint_member_4;
};

struct tint_struct_2 {
  const device tint_struct_3* tint_member_3;
  thread uint* tint_member_14;
  sampler tint_member_15;
  texture2d<float, access::sample> tint_member_16;
};

struct tint_struct_5 {
  float4 tint_member_17 [[color(0)]];
};

struct tint_struct_6 {
  uint tint_member_18 [[user(locn0)]] [[flat]];
  float2 tint_member_19 [[user(locn1)]];
};

float v(int v_1, float v_2, float v_3, float v_4) {
  switch(v_1) {
    case 0:
    {
      if (( tint_volatile_zero == 0u)) {
        return min(max(v_2, v_3), v_4);
      }
      break;
    }
    case 1:
    {
      float const v_5 = (v_4 - v_3);
      float const v_6 = (v_2 - v_3);
      if (( tint_volatile_zero == 0u)) {
        return ((v_6 - (v_5 * floor((v_6 / v_5)))) + v_3);
      }
      break;
    }
    case 2:
    {
      float const v_7 = (v_4 - v_3);
      float const v_8 = (2.0f * v_7);
      float const v_9 = (v_2 - v_3);
      float const v_10 = (v_9 - (v_8 * floor((v_9 / v_8))));
      if (( tint_volatile_zero == 0u)) {
        return (mix(v_10, (v_8 - v_10), step(v_7, v_10)) + v_3);
      }
      break;
    }
    default:
    {
      if (( tint_volatile_zero == 0u)) {
        return v_2;
      }
      break;
    }
  }
  /* unreachable */
  return 0.0f;
}

float4 v_11(float2 v_12, float2 v_13, texture2d<float, access::sample> v_14, sampler v_15) {
  return v_14.sample(v_15, (v_12 * v_13), bias(-0.47499999403953552246f));
}

float4 v_16(float2 v_17, float2 v_18, float4 v_19, int v_20, int v_21, int v_22, float2 v_23, texture2d<float, access::sample> v_24, sampler v_25) {
  float2 v_26 = v_17;
  bool v_27 = false;
  if ((v_20 == 3)) {
    v_27 = (v_22 == 0);
  } else {
    v_27 = false;
  }
  if (v_27) {
    float const v_28 = (floor(v_26.x) + 0.5f);
    bool v_29 = false;
    if ((v_28 < v_19.x)) {
      v_29 = true;
    } else {
      v_29 = (v_28 > v_19.z);
    }
    if (v_29) {
      return float4(0.0f);
    }
  }
  bool v_30 = false;
  if ((v_21 == 3)) {
    v_30 = (v_22 == 0);
  } else {
    v_30 = false;
  }
  if (v_30) {
    float const v_31 = (floor(v_26.y) + 0.5f);
    bool v_32 = false;
    if ((v_31 < v_19.y)) {
      v_32 = true;
    } else {
      v_32 = (v_31 > v_19.w);
    }
    if (v_32) {
      return float4(0.0f);
    }
  }
  v_26.x = v(v_20, v_26.x, v_19.x, v_19.z);
  v_26.y = v(v_21, v_26.y, v_19.y, v_19.w);
  float4 v_33 = 0.0f;
  if ((v_22 == 0)) {
    v_33 = float4((floor(v_19.xy) + 0.50001001358032226562f), (ceil(v_19.zw) - 0.50001001358032226562f));
  } else {
    v_33 = float4((v_19.xy + v_23), (v_19.zw - v_23));
  }
  float2 const v_34 = min(max(v_26, v_33.xy), v_33.zw);
  float4 v_35 = v_11(v_34, v_18, v_24, v_25);
  if ((v_22 == 1)) {
    float2 const v_36 = float2((v_26 - v_34));
    float2 const v_37 = abs(v_36);
    bool const v_38 = (v_20 == 1);
    bool const v_39 = (v_21 == 1);
    bool v_40 = false;
    if (v_38) {
      v_40 = true;
    } else {
      v_40 = v_39;
    }
    if (v_40) {
      float v_41 = 0.0f;
      float v_42 = 0.0f;
      float4 v_43 = 0.0f;
      float4 v_44 = 0.0f;
      if (v_38) {
        v_41 = select(v_33.z, v_33.x, (v_36.x > 0.0f));
        v_43 = v_11(float2(v_41, v_34.y), v_18, v_24, v_25);
      }
      if (v_39) {
        v_42 = select(v_33.w, v_33.y, (v_36.y > 0.0f));
        v_44 = v_11(float2(v_34.x, v_42), v_18, v_24, v_25);
      }
      bool v_45 = false;
      if (v_38) {
        v_45 = v_39;
      } else {
        v_45 = false;
      }
      if (v_45) {
        float4 const v_46 = v_11(float2(v_41, v_42), v_18, v_24, v_25);
        float4 const v_47 = v_35;
        float4 const v_48 = v_43;
        float4 const v_49 = mix(v_47, v_48, float4(v_37.x));
        float4 const v_50 = v_44;
        float4 const v_51 = mix(v_50, v_46, float4(v_37.x));
        v_35 = mix(v_49, v_51, float4(v_37.y));
      } else {
        if (v_38) {
          float4 const v_52 = v_35;
          float4 const v_53 = v_43;
          v_35 = mix(v_52, v_53, float4(v_37.x));
        } else {
          if (v_39) {
            float4 const v_54 = v_35;
            float4 const v_55 = v_44;
            v_35 = mix(v_54, v_55, float4(v_37.y));
          }
        }
      }
    }
    if ((v_20 == 3)) {
      v_35 = (v_35 * max((1.0f - v_37.x), 0.0f));
    }
    if ((v_21 == 3)) {
      v_35 = (v_35 * max((1.0f - v_37.y), 0.0f));
    }
  }
  return v_35;
}

void v_56(tint_struct v_57, thread tint_struct_1* const v_58, tint_struct_2 v_59) {
  (*v_59.tint_member_14) = v_57.tint_member;
  float4 v_60 = float4(0.0f);
  int v_61 = 0;
  {
    while(true) {
      if ((v_61 < 8)) {
      } else {
        break;
      }
      float4 const v_62 = (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_5[v_61];
      float2 const v_63 = (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_7.xy;
      float2 const v_64 = (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_7.zw;
      float4 const v_65 = v_60;
      float2 const v_66 = float2(v_63.x, v_63.y);
      float2x2 const v_67 = float2x2(v_66, float2(v_64.x, v_64.y));
      float2 const v_68 = (v_67 * (v_57.tint_member_1 + float2((v_62.x * (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_6))));
      v_60 = (v_65 + (v_62.y * v_16((v_68 + (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_8), (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_9, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_10, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_11, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_12, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_13, float2(0.50001001358032226562f), v_59.tint_member_16, v_59.tint_member_15)));
      float2 const v_69 = (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_7.xy;
      float2 const v_70 = (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_7.zw;
      float4 const v_71 = v_60;
      float2 const v_72 = float2(v_69.x, v_69.y);
      float2x2 const v_73 = float2x2(v_72, float2(v_70.x, v_70.y));
      float2 const v_74 = (v_73 * (v_57.tint_member_1 + float2((v_62.z * (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_6))));
      v_60 = (v_71 + (v_62.w * v_16((v_74 + (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_8), (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_9, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_10, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_11, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_12, (*v_59.tint_member_3).tint_member_4[(*v_59.tint_member_14)].tint_member_13, float2(0.50001001358032226562f), v_59.tint_member_16, v_59.tint_member_15)));
      {
        v_61 = as_type<int>((as_type<uint>(v_61) + 1u));
      }
    }
  }
  float4 const v_75 = v_60;
  (*v_58).tint_member_2 = v_75;
}

tint_struct_1 v_76(tint_struct v_77, tint_struct_2 v_78) {
  tint_struct_1 v_79 = {};
  (v_56(v_77, (&v_79), v_78));
  return v_79;
}

fragment tint_struct_5 dawn_entry_point(tint_struct_6 v_81 [[stage_in]], const device tint_struct_3* v_82 [[buffer(1)]], sampler v_83 [[sampler(0)]], texture2d<float, access::sample> v_84 [[texture(0)]]) {
  thread uint v_85 = 0u;
  tint_struct_2 const v_86 = tint_struct_2{.tint_member_3=v_82, .tint_member_14=(&v_85), .tint_member_15=v_83, .tint_member_16=v_84};
  tint_struct_5 v_87 = {};
  v_87.tint_member_17 = v_76(tint_struct{.tint_member=v_81.tint_member_18, .tint_member_1=v_81.tint_member_19}, v_86).tint_member_2;
  return v_87;
}
