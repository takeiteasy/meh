//
//  meh.m
//  meh
//
//  Created by Rory B. Bellows on 19/12/2017.
//  Copyright © 2017 Rory B. Bellows. All rights reserved.
//

/* TODO/Ideas
 *  - Handle images bigger than screen
 *  - Preserve aspect ratio on resize
 *  - Animated GIFs
 *  - Image from URL
 *  - EXIF info
 *  - Slideshow
 *  - Argument parsing
 */

#import <Cocoa/Cocoa.h>
#include "error.h"

#if defined(MEH_ANIMATE_RESIZE)
static BOOL animate_window = YES;
#else
static BOOL animate_window = NO;
#endif
static NSArray* extensions = nil;
static NSImage* error_img = nil;

@interface AppDelegate : NSApplication {}
@end

@implementation AppDelegate
-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
  (void)app;
  return YES;
}
@end

@interface AppView : NSView {
  NSImage *image;
  NSArray *files;
  NSString *files_dir;
  NSInteger files_cursor;
}

-(BOOL)loadImage:(NSString*)path;
-(void)forceResize;
@end

@implementation AppView
-(id)initWithFrame:(NSRect)frame Image:(NSString*)path {
  if (![self loadImage:path]) {
    NSLog(@"ERROR: Failed to load \"%@\"", path);
    return nil;
  }
  if (!(files = [[NSMutableArray alloc] init])) {
    NSLog(@"ERROR: Out of memory");
    return nil;
  }
  NSArray *dir_parts = [path pathComponents];
  files_dir = [NSString pathWithComponents:[dir_parts subarrayWithRange:(NSRange){ 0, [dir_parts count] - 1}]];
  NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:files_dir
                                                                      error:NULL];
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"ANY %@ CONTAINS[c] pathExtension", extensions];
  files = [[dirs filteredArrayUsingPredicate:predicate] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  
  files_cursor = -1;
  [files enumerateObjectsUsingBlock:^(NSString *fname, NSUInteger idx, BOOL *stop) {
    if ([fname isEqualToString:dir_parts[[dir_parts count] - 1]]) {
      files_cursor = idx;
      *stop = YES;
    }
  }];
  if (files_cursor == -1) {
    NSLog(@"ERROR: Could not find image in directory! Something went wrong");
    return nil;
  }
  self = [super initWithFrame:frame];
  return self;
}

-(BOOL)loadImage:(NSString*)path {
  return !!(image = [[NSImage alloc] initWithContentsOfFile:path]);
}

-(void)forceResize {
  NSRect frame = [[self window] frame];
  frame.size = [image size];
  [[self window] setFrame:frame
                  display:YES
                  animate:animate_window];
}

-(BOOL)acceptsFirstResponder {
  return YES;
}

-(void)keyDown:(NSEvent*)event {
  (void)event;
}

-(void)keyUp:(NSEvent*)event {
  switch ([event keyCode]) {
    case 0x35: // ESC
    case 0x0C: // Q
      [[self window] close];
      break;
    case 0x26: // J
      files_cursor -= 2;
    case 0x28: // K
      files_cursor++;
      if (files_cursor < 0)
        files_cursor = [files count] - 1;
      if (files_cursor >= [files count])
        files_cursor = 0;
      if (![self loadImage:[NSString stringWithFormat: @"%@/%@", files_dir, files[files_cursor]]]) {
        NSLog(@"ERROR: Failed to load \"%@\"", files[files_cursor]);
        image = error_img;
      }
      [self forceResize];
      break;
    default:
      break;
  }
}

-(void)drawRect:(NSRect)dirtyRect {
  [image drawInRect:[self frame]];
}
@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    extensions = [NSArray arrayWithObjects:@"pdf", @"eps", @"epi", @"epsf", @"epsi", @"ps", @"tiff", @"tif", @"jpg", @"jpeg", @"jpe", @"gif", @"png", @"pict", @"pct", @"pic", @"bmp", @"BMPf", @"ico", @"icns", @"dng", @"cr2", @"crw", @"fpx", @"fpix", @"raf", @"dcr", @"ptng", @"pnt", @"mac", @"mrw", @"nef", @"orf", @"exr", @"psd", @"qti", @"qtif", @"hdr", @"sgi", @"srf", @"targa", @"tga", @"cur", @"xbm", nil];
    NSData* data = [NSData dataWithBytes:(const void*)error_data length:sizeof(uint8_t) * error_data_size];
    error_img = [[NSImage alloc] initWithData:data];
    
    int n_windows = 0;
    for (int i = 1; i < argc; ++i) {
      id menubar = [NSMenu alloc];
      id appMenuItem = [NSMenuItem alloc];
      [menubar addItem:appMenuItem];
      [NSApp setMainMenu:menubar];
      id appMenu = [NSMenu alloc];
      id quitTitle = [@"Quit " stringByAppendingString:[[NSProcessInfo processInfo] processName]];
      id quitMenuItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                   action:@selector(terminate:)
                                            keyEquivalent:@"q"];
      [appMenu addItem:quitMenuItem];
      [appMenuItem setSubmenu:appMenu];
      
      id window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 0, 0)
                                              styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
      if (!window) {
        NSLog(@"ERROR: Out of memory");
        [NSApp terminate:nil];
      }
      
      [window setTitle:@""];
      [window makeKeyAndOrderFront:nil];
      [window setMovableByWindowBackground:YES];
      [window setTitlebarAppearsTransparent:YES];
      [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
      [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
      [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
      
      id app_del = [AppDelegate alloc];
      if (!app_del) {
        NSLog(@"ERROR: Out of memory");
        [NSApp terminate:nil];
      }
      [NSApp setDelegate:app_del];
      id app_view = [AppView alloc];
      if (!app_view) {
        NSLog(@"ERROR: Out of memory");
        [NSApp terminate:nil];
      }
      if (![app_view initWithFrame:NSZeroRect
                             Image:@(argv[i])])
        [NSApp terminate:nil];
      [window setContentView:app_view];
      [app_view forceResize];
      
      n_windows++;
    }
    if (!n_windows) {
      fprintf(stderr, "No valid images passed through arguments\n");
      return 1;
    }
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
