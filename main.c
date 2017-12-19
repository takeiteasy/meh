//
//  main.c
//  meh
//
//  Created by Rory B. Bellows on 19/12/2017.
//  Copyright © 2017 Rory B. Bellows. All rights reserved.
//

static int w, h, c;
static unsigned char *orig_buf, *buf;

#include <stdio.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSApplication {}
@end

@implementation AppDelegate
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)theApplication {
  (void)theApplication;
  return YES;
}
@end

@interface AppView : NSView {}
@end

@implementation AppView
-(id)initWithFrame:(NSRect)frame {
  if (self = [super initWithFrame:frame]) {}
  return self;
}

-(BOOL)acceptsFirstResponder {
  return YES;
}

-(void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = [self bounds];
  if (buf)
    free(buf);
  buf = (unsigned char*)malloc(bounds.size.width * bounds.size.height * 4);
  stbir_resize_uint8(orig_buf, w, h, 0, buf, bounds.size.width, bounds.size.height, 0, 4);
  
  CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
  
  CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB();
  CGDataProviderRef p = CGDataProviderCreateWithData(NULL, buf, bounds.size.width * bounds.size.height * c, NULL);
  CGImageRef img = CGImageCreate(bounds.size.width, bounds.size.height, 8, 32, bounds.size.width * 4, s, kCGBitmapByteOrderDefault, p, NULL, false, kCGRenderingIntentDefault);
  
  CGColorSpaceRelease(s);
  CGDataProviderRelease(p);
  
  CGContextDrawImage(ctx, CGRectMake(0, 0, bounds.size.width, bounds.size.height), img);
  
  CGImageRelease(img);
}
@end

int main(int argc, const char * argv[]) {
  orig_buf = stbi_load("/Users/roryb/Pictures/40e4bfd8f20f5f370f1125dbea504b5859ab6884bde4b59a3044c2c4f64feb12.jpg", &w, &h, &c, 4);
  if (!orig_buf) {
    printf("stbi_load() failed: %s\n", stbi_failure_reason());
    return 1;
  }
  
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    id menubar = [NSMenu alloc];
    id appMenuItem = [NSMenuItem alloc];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];
    id appMenu = [NSMenu alloc];
    id appName = [[NSProcessInfo processInfo] processName];
    id quitTitle = [@"Quit" stringByAppendingString:appName];
    id quitMenuItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                 action:@selector(terminate:)
                                          keyEquivalent:@"q"];
    [appMenu addItem:quitMenuItem];
    [appMenuItem setSubmenu:appMenu];
    
    id window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, w, h)
                                            styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    
    [window center];
    [window setTitle:@""];
    [window makeKeyAndOrderFront:nil];
    [window setMovableByWindowBackground:YES];
    [window setTitlebarAppearsTransparent:YES];
    [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    
    id app_del = [AppDelegate alloc];
    if (!app_del)
      [NSApp terminate:nil];
    [NSApp setDelegate:app_del];
    id app_view = [[AppView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    [window setContentView:app_view];
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
