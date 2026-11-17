// Experiment: does CAMetalLayer accept the shim device and hand out drawables?
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import "TSMetal.h"
int main(void){ @autoreleasepool{
  [NSApplication sharedApplication];
  id<MTLDevice> d = TSMtlCreateDevice();
  CAMetalLayer *l = [CAMetalLayer layer];
  l.device = d;
  NSLog(@"layer.device=%@", l.device.name);
  l.pixelFormat = MTLPixelFormatBGRA8Unorm;
  l.drawableSize = CGSizeMake(64, 64);
  l.framebufferOnly = NO;
  id<CAMetalDrawable> dr = [l nextDrawable];
  NSLog(@"drawable=%@ texture=%@ iosurface=%p", dr, dr.texture, dr.texture.iosurface);
  id<MTLCommandQueue> q = [d newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  [cb presentDrawable:dr];
  [cb commit]; [cb waitUntilCompleted];
  NSLog(@"presented, status=%lu", (unsigned long)cb.status);
  id<CAMetalDrawable> dr2 = [l nextDrawable];
  NSLog(@"drawable2=%@", dr2.texture);
} return 0; }
