// Experiment: can a _MTLDevice subclass be created with plain -init outside an IOAccelerator?
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
@interface _MTLDevice : NSObject @end
@interface TSProbeDevice : _MTLDevice @end
@implementation TSProbeDevice
- (NSString *)name { return @"probe"; }
@end
int main(void){ @autoreleasepool{
  id d = [[TSProbeDevice alloc] init];
  NSLog(@"device=%@", d);
  NSLog(@"name=%@ conformsMTLDevice=%d", [d name], [d conformsToProtocol:@protocol(MTLDevice)]);
  NSLog(@"supportsFamily Mac2=%d", [(id<MTLDevice>)d supportsFamily:MTLGPUFamilyMac2]);
  id q = [(id<MTLDevice>)d newCommandQueue];
  NSLog(@"queue=%@", q);
} return 0; }
