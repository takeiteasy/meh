//
//  main.c
//  meh
//
//  Created by Rory B. Bellows on 19/12/2017.
//  Copyright © 2017 Rory B. Bellows. All rights reserved.
//

/* TODO
 *  - Argument parsing
 *  - Handle images bigger than screen & preserve aspect ratio on resize
 *  - Different backends (Metal/OpenGL)
 *  - cURL integration
 *  - Animated GIFs (http://gist.github.com/urraka/685d9a6340b26b830d49)
 *  - EXIF info
 *  - Slideshow
 *  - Handle alpha
 *  - Replace stb_image with ImageMagick
 */

#include <stdio.h>
#include <dirent.h>
#include <libgen.h>
#include <string.h>
#include <MagickWand/MagickWand.h>
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

size_t w, h, c;
static char* buf;

#if defined(MEH_ANIMATE_RESIZE)
static BOOL animate_window = YES;
#else
static BOOL animate_window = NO;
#endif

@interface AppDelegate : NSApplication {}
@end

@implementation AppDelegate
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
  (void)app;
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

-(void)keyDown:(NSEvent *)event {
}

-(void)keyUp:(NSEvent *)event {
  switch ([event keyCode]) {
    case 0x35: // ESC
    case 0x0C: // Q
      [[self window] close];
      break;
    default:
      break;
  }
}

-(void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = [self bounds];
  
  CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
  
  CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB();
  CGDataProviderRef p = CGDataProviderCreateWithData(NULL, buf, w * h * c, NULL);
  CGImageRef img = CGImageCreate(w, h, 8, 32, w * c, s, kCGBitmapByteOrderDefault, p, NULL, false, kCGRenderingIntentDefault);
  
  CGColorSpaceRelease(s);
  CGDataProviderRelease(p);
  
  CGContextDrawImage(ctx, CGRectMake(0, 0, bounds.size.width, bounds.size.height), img);
  
  CGImageRelease(img);
}
@end

int main(int argc, const char* argv[]) {
  MagickWandGenesis();
  
  MagickWand* test = NewMagickWand();
  if (MagickReadImage(test, "/Users/roryb/Pictures/34a01325ab9978f260022e0154ab0397.jpg") == MagickFalse) {
    return 1;
  }
  w = MagickGetImageWidth(test);
  h = MagickGetImageHeight(test);
  c = 4;
  buf = malloc(w * h * c);
  MagickExportImagePixels(test, 0, 0, w, h, "RGBA", CharPixel, buf);
  
  
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    id menubar = [NSMenu alloc];
    id appMenuItem = [NSMenuItem alloc];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];
    id appMenu = [NSMenu alloc];
    id appName = [[NSProcessInfo processInfo] processName];
    id quitTitle = [@"Quit " stringByAppendingString:appName];
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
