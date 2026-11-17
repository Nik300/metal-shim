// Experiment: map MTLDeviceFeatureProfile values -> supported GPU families / feature sets.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
@interface _MTLDevice : NSObject @end
@interface _MTLDevice (P)
- (void)initGPUFamilySupport;
+ (BOOL)featureProfile:(unsigned long long)p supportsFeatureSet:(unsigned long long)fs;
@end
static unsigned long long gProfile;
@interface TSProbeDevice : _MTLDevice @end
@implementation TSProbeDevice
- (unsigned long long)featureProfile { return gProfile; }
@end
int main(void){ @autoreleasepool{
  struct { long v; const char *n; } fam[] = {
    {MTLGPUFamilyApple1,"Apple1"},{MTLGPUFamilyApple2,"Apple2"},{MTLGPUFamilyApple3,"Apple3"},{MTLGPUFamilyApple4,"Apple4"},
    {MTLGPUFamilyApple5,"Apple5"},{MTLGPUFamilyApple6,"Apple6"},{MTLGPUFamilyApple7,"Apple7"},{MTLGPUFamilyApple8,"Apple8"},
    {MTLGPUFamilyApple9,"Apple9"},{1001,"Mac1"},{MTLGPUFamilyMac2,"Mac2"},{MTLGPUFamilyCommon1,"Common1"},
    {MTLGPUFamilyCommon2,"Common2"},{MTLGPUFamilyCommon3,"Common3"},{MTLGPUFamilyMetal3,"Metal3"},{5002,"Metal4"}};
  for (unsigned long long k = 0; k < 20000; k++) { gProfile = k;
    TSProbeDevice *d = [[TSProbeDevice alloc] init];
    [d initGPUFamilySupport];
    NSMutableString *s = [NSMutableString string];
    for (unsigned i=0;i<sizeof fam/sizeof fam[0];i++) if ([(id<MTLDevice>)d supportsFamily:fam[i].v]) [s appendFormat:@"%s ", fam[i].n];
    NSMutableString *fs = [NSMutableString string];
    for (unsigned long long f = 10000; f < 10010; f++) if ([_MTLDevice featureProfile:gProfile supportsFeatureSet:f]) [fs appendFormat:@"%llu ", f];
    printf("profile %2llu: families[%s] macFeatureSets[%s]\n", gProfile, s.UTF8String, fs.UTF8String);
  }
} return 0; }
