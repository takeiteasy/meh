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
 *  - Zooming
 *  - Drag and drop
 *  - Open file dialog
 */

#import <Cocoa/Cocoa.h>
#include "error.h"

#if defined(MEH_ANIMATE_RESIZE)
static BOOL animate_window = YES;
#else
static BOOL animate_window = NO;
#endif
static NSArray *extensions = nil;
static NSImage *error_img = nil;
static BOOL first_window = YES;

BOOL createWindow(NSString *path);

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong, nonatomic) NSWindow *window;
@end

@interface AppView : NSView {}
@end

@interface ImageView : NSImageView {
  NSImage *image;
  AppView *subview;
  NSArray *files;
  NSString *files_dir;
  NSInteger files_cursor;
}
-(BOOL)loadImage:(NSString*)path;
-(void)setErrorImg;
-(BOOL)setImageIdx:(NSInteger)idx;
-(BOOL)setImageNext;
-(BOOL)setImagePrev;
-(void)forceResize;
@end

@implementation ImageView
-(id)initWithFrame:(NSRect)frame imagePath:(NSString*)path {
  if (![self loadImage:path])
    return nil;
  subview = [[AppView alloc] initWithFrame:frame];
  self = [super initWithFrame:frame];
  [self addSubview:subview];
  [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
  return self;
}

-(NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
  if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType])
    return [sender draggingSourceOperationMask] & NSDragOperationLink ? NSDragOperationLink : NSDragOperationCopy;
  return NSDragOperationNone;
}

-(BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
  NSPasteboard *pboard = [sender draggingPasteboard];
  if (![[pboard types] containsObject:NSFilenamesPboardType] || !([sender draggingSourceOperationMask] & NSDragOperationLink))
    return NO;
  NSArray *links = [pboard propertyListForType:NSFilenamesPboardType];
  if (![self loadImage:links[0]])
    [[self window] close];
  if ([links count] > 1) {
    for (int i = 1; i < [links count]; ++i) {
      if (!createWindow(links[i]))
        NSLog(@"ERROR: Failed to load \"%@\"", links[i]);
    }
  }
  return YES;
}

-(BOOL)loadImage:(NSString*)path {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    NSLog(@"ERROR: File \"%@\" doesn't exist!", path);
    return NO;
  }
  NSArray *dir_parts = [path pathComponents];
  NSString *dir_path = [NSString pathWithComponents:[dir_parts subarrayWithRange:(NSRange){ 0, [dir_parts count] - 1}]];
  if (!(image = [[NSImage alloc] initWithContentsOfFile:path])) {
    NSLog(@"ERROR: Failed to load \"%@\"", path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir_path])
      return NO;
    [self setErrorImg];
  }
  if (![dir_path isEqualToString:files_dir])
    [self updateFileList:dir_path fileName:dir_parts[[dir_parts count] - 1]];
  if ([[[path pathExtension] lowercaseString] isEqualToString:@"gif"]) {
    
  }
  return YES;
}

-(BOOL)updateFileList:(NSString*)dir fileName:(NSString*)file {
  if (!(files = [[NSMutableArray alloc] init])) {
    NSLog(@"ERROR: Out of memory");
    return NO;
  }
  NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir
                                                                      error:NULL];
  if (!extensions)
    extensions = [NSArray arrayWithObjects:@"pdf", @"eps", @"epi", @"epsf", @"epsi", @"ps", @"tiff", @"tif", @"jpg", @"jpeg", @"jpe", @"gif", @"png", @"pict", @"pct", @"pic", @"bmp", @"BMPf", @"ico", @"icns", @"dng", @"cr2", @"crw", @"fpx", @"fpix", @"raf", @"dcr", @"ptng", @"pnt", @"mac", @"mrw", @"nef", @"orf", @"exr", @"psd", @"qti", @"qtif", @"hdr", @"sgi", @"srf", @"targa", @"tga", @"cur", @"xbm", nil];
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"ANY %@ CONTAINS[c] pathExtension", extensions];
  files = [[dirs filteredArrayUsingPredicate:predicate] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  
  files_cursor = -1;
  [files enumerateObjectsUsingBlock:^(NSString *fname, NSUInteger idx, BOOL *stop) {
    if ([fname isEqualToString:file]) {
      files_cursor = idx;
      *stop = YES;
    }
  }];
  if (files_cursor == -1) {
    NSLog(@"ERROR: Could not find image in directory! Something went wrong");
    return NO;
  }
  files_dir = dir;
  return YES;
}

-(void)setErrorImg {
  if (!error_img) {
    NSData *data = [NSData dataWithBytes:(const void*)error_data length:sizeof(uint8_t) * error_data_size];
    error_img = [[NSImage alloc] initWithData:data];
  }
  image = error_img;
}

-(BOOL)setImageIdx:(NSInteger)idx {
  files_cursor = idx;
  if (files_cursor < 0)
    files_cursor = [files count] - 1;
  if (files_cursor >= [files count])
    files_cursor = 0;
  if (![self loadImage:[NSString stringWithFormat: @"%@/%@", files_dir, files[files_cursor]]]) {
    NSLog(@"ERROR: Failed to load \"%@\"", files[files_cursor]);
    [self setErrorImg];
  }
  [self forceResize];
  return YES;
}

-(BOOL)setImageNext {
  return [self setImageIdx:files_cursor + 1];
}

-(BOOL)setImagePrev {
  return [self setImageIdx:files_cursor - 1];
}

-(void)forceResize {
  NSRect frame = [[self window] frame];
  frame.size = [image size];
  [[self window] setFrame:frame
                  display:YES
                  animate:animate_window];
  [subview setFrame:NSMakeRect(0.f, 0.f, frame.size.width, frame.size.height)];
  [self setNeedsDisplay:YES];
}

-(BOOL)acceptsFirstResponder {
  return YES;
}

-(void)keyDown:(NSEvent*)event {
  (void)event;
}

-(void)keyUp:(NSEvent*)event {
  (void)event;
}

-(void)drawRect:(NSRect)dirtyRect {
  [image drawInRect:[self frame]];
}
@end


@implementation AppDelegate
@synthesize window;

-(id)initWithPath:(NSString*)path {
  CGSize screen = [[NSScreen mainScreen] frame].size;
  window = [[NSWindow alloc] initWithContentRect:NSMakeRect(screen.width / 2, screen.height / 2, 0.f, 0.f)
                                          styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
  if (!window) {
    NSLog(@"ERROR: Out of memory");
    abort();
  }
  
  [window setTitle:@""];
  [window makeKeyAndOrderFront:nil];
  [window setMovableByWindowBackground:YES];
  [window setTitlebarAppearsTransparent:YES];
  [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
  [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
  [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
  [window setReleasedWhenClosed:NO];
  
  id app_view = [ImageView alloc];
  if (!app_view) {
    NSLog(@"ERROR: Out of memory");
    abort();
  }
  if (![app_view initWithFrame:NSZeroRect
                     imagePath:path]) {
    [window close];
    return nil;
  }
  [window setContentView:app_view];
  [app_view forceResize];
  return self;
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
  (void)app;
  return YES;
}
@end

@implementation AppView
-(id)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  return self;
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
    case 0x7b: // Arrow key left
    case 0x7d: // Arrow key down
    case 0x26: // J
      [(ImageView*)[self superview] setImagePrev];
      break;
    case 0x7e: // Arrow key up
    case 0x7c: // Arrow key right
    case 0x28: // K
      [(ImageView*)[self superview] setImageNext];
      break;
    default:
      break;
  }
}
@end

BOOL createWindow(NSString *path) {
  if (first_window) {
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
  }
  
  id app_del = [[AppDelegate alloc] initWithPath:path];
  if (!app_del) {
    NSLog(@"ERROR: Out of memory");
    abort();
  }
  if (first_window) {
    [NSApp setDelegate:app_del];
    first_window = NO;
  }
  
  return YES;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    int n_windows = 0;
    for (int i = 1; i < argc; ++i)
      if (createWindow(@(argv[i])))
        n_windows++;
    if (!n_windows) {
      NSLog(@"No valid images passed through arguments\n");
      [NSApp terminate:nil];
    }
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
