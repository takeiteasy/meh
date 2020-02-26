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
 *  - Single window option
 *  - Argument parsing (Copy a bunch from feh)
 *  - More key shortcuts (Copy a bunch from feh)
 *  - Zooming
 *  - Archives (Using XADMaster)
 *  - Touch controls?
 */

#import <Cocoa/Cocoa.h>
#include "error.h"

#define MEM_CHECK(X) \
if (!(X)) { \
  NSLog(@"ERROR: Out of memory"); \
  abort(); \
}
#if defined(MEH_ANIMATE_RESIZE)
static BOOL animate_window = YES;
#else
static BOOL animate_window = NO;
#endif
static NSArray *extensions = nil;
static NSImage *error_img = nil;
static BOOL slideshow = YES;
static float slideshow_timer = 3.f;
static BOOL slideshow_next = YES;
static BOOL first_window = YES;
BOOL createWindow(NSString *path);

BOOL alert(enum NSAlertStyle style, NSString *fmt, ...) {
  NSAlert *alert = [[NSAlert alloc] init];
  MEM_CHECK(alert);
  [alert setAlertStyle:style];
  [alert addButtonWithTitle:@"OK"];
  va_list args;
  va_start(args, fmt);
  NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
  va_end(args);
  MEM_CHECK(msg);
  [alert setMessageText:msg];
  return [alert runModal] == NSAlertFirstButtonReturn;
}

NSArray* openDialog(NSString *dir) {
  NSOpenPanel *dialog = [NSOpenPanel openPanel];
  MEM_CHECK(dialog);
  if (dir)
    [dialog setDirectoryURL:[NSURL fileURLWithPath:dir]];
  [dialog setAllowedFileTypes:extensions];
  [dialog setAllowsMultipleSelection:YES];
  [dialog setCanChooseFiles:YES];
  [dialog setCanChooseDirectories:NO];
  return  [dialog runModal] == NSModalResponseOK ? [dialog URLs] : nil;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong, nonatomic) NSWindow *window;
@end

@interface AppView : NSView {
  NSPoint dragPoint;
}
@end

@interface ImageView : NSImageView {
  NSImage *image;
  AppView *subview;
  NSArray *files;
  NSString *files_dir;
  NSInteger files_cursor;
  BOOL timerPaused;
  NSTimer *timer;
}
-(void)toggleSlideshow;
-(void)handleTimer:(NSTimer*)timer;
-(BOOL)loadImage:(NSString*)path;
-(BOOL)loadURLImage:(NSURL*)url;
-(void)setErrorImg;
-(BOOL)setImageIdx:(NSInteger)idx;
-(BOOL)setImageNext;
-(BOOL)setImagePrev;
-(void)forceResize;
-(NSString*)fileDir;
@end

@implementation ImageView
-(id)initWithFrame:(NSRect)frame imagePath:(NSString*)path {
  self = [super initWithFrame:frame];
  if (![self loadImage:path])
    return nil;
  subview = [[AppView alloc] initWithFrame:frame];
  [self setAnimates:YES];
  [self setCanDrawSubviewsIntoLayer:YES];
  [self setImageScaling:NSImageScaleAxesIndependently];
  [self addSubview:subview];
  [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
  if (slideshow) {
    timerPaused = YES;
    [self toggleSlideshow];
  }
  return self;
}

-(void)toggleSlideshow {
  if (timerPaused || !timer) {
    timer = [NSTimer scheduledTimerWithTimeInterval:slideshow_timer
                                             target:self
                                           selector:@selector(handleTimer:)
                                           userInfo:nil
                                            repeats:YES];
    timerPaused = NO;
  } else {
    [timer invalidate];
    timerPaused = YES;
  }
}

-(void)handleTimer:(NSTimer*)timer {
  if (slideshow_next)
    [self setImageNext];
  else
    [self setImagePrev];
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
  [links enumerateObjectsUsingBlock:^(NSString *fname, NSUInteger idx, BOOL *stop) {
    if (!idx) {
      if (![self loadImage:fname])
        [[self window] close];
      [self forceResize];
    } else {
      if (!createWindow(fname))
        alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", fname);
    }
  }];
  return YES;
}

-(BOOL)loadURLImage:(NSURL*)url {
  if (![extensions containsObject:[[[url absoluteString] pathExtension] lowercaseString]]) {
    alert(NSAlertStyleCritical, @"ERROR: URL \"%@\" has invalid extension", [url absoluteString]);
    return NO;
  }
  MEM_CHECK(image = [NSImage alloc]);
  if (![image initWithContentsOfURL:url]) {
    alert(NSAlertStyleCritical, @"ERROR: Failed to load image from URL \"%@\"");
    return NO;
  }
  files = nil;
  files_dir = nil;
  files_cursor = -1;
  [self setImage:image];
  return YES;
}

-(BOOL)loadImage:(NSString*)path {
  NSURL *url = [NSURL URLWithString:path];
  if (url && [url scheme] && [url host])
    return [self loadURLImage:url];
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    alert(NSAlertStyleCritical, @"ERROR: File \"%@\" doesn't exist", path);
    return NO;
  }
  NSArray *dir_parts = [path pathComponents];
  NSString *dir_path = [NSString pathWithComponents:[dir_parts subarrayWithRange:(NSRange){ 0, [dir_parts count] - 1}]];
  if (!(image = [[NSImage alloc] initWithContentsOfFile:path])) {
    alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", path);
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir_path])
      return NO;
    [self setErrorImg];
  }
  if (![dir_path isEqualToString:files_dir])
    [self updateFileList:dir_path fileName:dir_parts[[dir_parts count] - 1]];
  [self setImage:image];
  return YES;
}

-(BOOL)updateFileList:(NSString*)dir fileName:(NSString*)file {
  MEM_CHECK(files = [[NSMutableArray alloc] init]);
  NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir
                                                                      error:NULL];
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
    alert(NSAlertStyleCritical, @"ERROR: Could not find image in directory! Something went wrong");
    return NO;
  }
  files_dir = dir;
  return YES;
}

-(void)setErrorImg {
  if (!error_img) {
    NSData *data = [NSData dataWithBytes:(const void*)error_data length:sizeof(uint8_t) * error_data_size];
    MEM_CHECK(error_img = [NSImage alloc]);
    if (![error_img initWithData:data]) {
      NSLog(@"ERROR: Failed to recreate error image from memory");
      abort();
    }
  }
  image = error_img;
}

-(BOOL)setImageIdx:(NSInteger)idx {
  if (!files)
    return NO;
  files_cursor = idx;
  if (files_cursor < 0)
    files_cursor = [files count] - 1;
  if (files_cursor >= [files count])
    files_cursor = 0;
  if (![self loadImage:[NSString stringWithFormat: @"%@/%@", files_dir, files[files_cursor]]]) {
    alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", files[files_cursor]);
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

-(NSString*)fileDir {
  return files_dir;
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
@end


@implementation AppDelegate
@synthesize window;

-(id)initWithPath:(NSString*)path {
  CGSize screen = [[NSScreen mainScreen] frame].size;
  window = [[NSWindow alloc] initWithContentRect:NSMakeRect(screen.width / 2, screen.height / 2, 0.f, 0.f)
                                          styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
  MEM_CHECK(window);
  
  [window setTitle:@""];
  [window makeKeyAndOrderFront:nil];
  [window setMovableByWindowBackground:YES];
  [window setTitlebarAppearsTransparent:YES];
  [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
  [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
  [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
  [window setReleasedWhenClosed:NO];
  
  id app_view = [ImageView alloc];
  MEM_CHECK(app_view);
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
    case 0x1f: { // O
      ImageView *view = (ImageView*)[self superview];
      NSArray *urls = openDialog([view fileDir]);
      if (!urls)
        break;
      [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, BOOL *stop) {
        if (!idx) {
          if (![view loadImage:[url relativePath]])
            [[self window] close];
          [view forceResize];
        } else {
          if (!createWindow([url relativePath]))
            alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", [url relativePath]);
        }
      }];
      break;
    }
    case 0x23: // P
      if (slideshow)
        [(ImageView*)[self superview] toggleSlideshow];
      break;
    default:
#if DEBUG
      NSLog(@"Unrecognized key: 0x%x", [event keyCode]);
#endif
      break;
  }
}

-(void)mouseDown:(NSEvent *)theEvent {
  NSRect  windowFrame = [[self window] frame];
  dragPoint = [NSEvent mouseLocation];
  dragPoint.x -= windowFrame.origin.x;
  dragPoint.y -= windowFrame.origin.y;
}

- (void)mouseDragged:(NSEvent *)theEvent {
  NSRect  screenFrame = [[NSScreen mainScreen] frame];
  NSRect  windowFrame = [self frame];
  NSPoint currentPoint = [NSEvent mouseLocation];
  NSPoint newOrigin = NSMakePoint(currentPoint.x - dragPoint.x,
                                  currentPoint.y - dragPoint.y);
  if ((newOrigin.y + windowFrame.size.height) > (screenFrame.origin.y + screenFrame.size.height))
      newOrigin.y = screenFrame.origin.y + (screenFrame.size.height - windowFrame.size.height);
  [[self window] setFrameOrigin:newOrigin];
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
    
    extensions = [NSArray arrayWithObjects:@"pdf", @"eps", @"epi", @"epsf", @"epsi", @"ps", @"tiff", @"tif", @"jpg", @"jpeg", @"jpe", @"gif", @"png", @"pict", @"pct", @"pic", @"bmp", @"BMPf", @"ico", @"icns", @"dng", @"cr2", @"crw", @"fpx", @"fpix", @"raf", @"dcr", @"ptng", @"pnt", @"mac", @"mrw", @"nef", @"orf", @"exr", @"psd", @"qti", @"qtif", @"hdr", @"sgi", @"srf", @"targa", @"tga", @"cur", @"xbm", nil];
  }
  
  id app_del = [[AppDelegate alloc] initWithPath:path];
  MEM_CHECK(app_del);
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
      alert(NSAlertStyleInformational, @"No valid images passed through arguments");
      [NSApp terminate:nil];
    }
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
