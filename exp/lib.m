// Probe: what does the _MTLDevice base do with shader compilation on the shim device?
#import <Foundation/Foundation.h>
#import "TSMetal.h"
int main(void){ @autoreleasepool{
  id<MTLDevice> d = TSMtlCreateDevice();
  NSError *err = nil;
  id<MTLLibrary> lib = [d newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(uint i [[vertex_id]]) { return float4(i, 0, 0, 1); }\nfragment half4 f() { return half4(1); }" options:nil error:&err];
  NSLog(@"library=%@ err=%@", lib, err);
  id<MTLFunction> vf = [lib newFunctionWithName:@"v"];
  NSLog(@"function=%@", vf);
  if (vf) {
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = vf; pd.fragmentFunction = [lib newFunctionWithName:@"f"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id ps = [d newRenderPipelineStateWithDescriptor:pd error:&err];
    NSLog(@"pipeline=%@ err=%@", ps, err);
  }
  NSLog(@"default library=%@", [d newDefaultLibrary]);
  NSLog(@"event=%@ queue(max)=%@", [d newEvent], [d newCommandQueueWithMaxCommandBufferCount:4]);
} return 0; }
