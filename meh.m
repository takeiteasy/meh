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
 *  - Argument parsing (Copy a bunch from feh)
 *  - More key shortcuts (Copy a bunch from feh)
 *  - Zooming
 *  - Archives (Using XADMaster)
 *  - Touch controls?
 *  - Async loading
 */

#include <getopt.h>
#import <Cocoa/Cocoa.h>
#include "error.h"

#define MEM_CHECK(X) \
if (!(X)) { \
  NSLog(@"ERROR: Out of memory"); \
  abort(); \
}

#define DEFAULT_SLIDESHOW_TIMER 3.f

enum SORT_BY {
  ALPHABETIC,
  FSIZE,
  MTIME,
  CTIME,
  FORMAT,
  RANDOM
};

#define SETTINGS \
  X(BOOL, animate_window, NO) \
  X(NSArray*, extensions, nil) \
  X(NSImage*, error_img, nil) \
  X(BOOL, slideshow, NO) \
  X(float, slideshow_timer, DEFAULT_SLIDESHOW_TIMER) \
  X(BOOL, slideshow_prev, NO) \
  X(BOOL, single_window, NO) \
  X(BOOL, first_window, YES) \
  X(BOOL, sort_files, NO) \
  X(BOOL, reverse_sort, NO) \
  X(enum SORT_BY, sort_type, ALPHABETIC) \

static struct context {
#define X(A, B, C) \
  A B;
SETTINGS
#undef X
} ctx = {
#define X(A, B, C) \
  .B = C,
SETTINGS
#undef X
};

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
  [dialog setAllowedFileTypes:ctx.extensions];
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
  NSMutableArray *files;
  NSString *files_dir;
  NSInteger files_cursor;
  BOOL timerPaused;
  NSTimer *timer;
}
-(void)toggleSlideshow;
-(void)handleTimer:(NSTimer*)timer;
-(BOOL)loadImage:(NSString*)path;
-(BOOL)updateFileList:(NSString*)dir fileName:(NSString*)file;
-(BOOL)addImageList:(NSString*)path setImage:(BOOL)set;
-(BOOL)loadURLImage:(NSURL*)url;
-(void)setErrorImg;
-(BOOL)setImageIdx:(NSInteger)idx;
-(BOOL)setImageNext;
-(BOOL)setImagePrev;
-(void)forceResize;
-(NSString*)fileDir;
@end
static ImageView *single_window_view = nil;

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
  if (ctx.slideshow) {
    timerPaused = YES;
    [self toggleSlideshow];
  }
  return self;
}

-(void)toggleSlideshow {
  if (timerPaused || !timer) {
    timer = [NSTimer scheduledTimerWithTimeInterval:ctx.slideshow_timer
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
  if (ctx.slideshow_prev)
    [self setImagePrev];
  else
    [self setImageNext];
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
    if (ctx.single_window)
      [self addImageList:fname setImage:(BOOL)!idx];
    else {
      if (!idx) {
        if (![self loadImage:fname])
          [[self window] close];
        [self forceResize];
      } else {
        if (!createWindow(fname))
          alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", fname);
      }
    }
  }];
  return YES;
}

-(BOOL)loadURLImage:(NSURL*)url {
  if (![ctx.extensions containsObject:[[[url absoluteString] pathExtension] lowercaseString]]) {
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
  if (ctx.single_window) {
    if (!files) {
      MEM_CHECK(files = [[NSMutableArray alloc] init]);
      [files addObject:path];
      files_cursor = 0;
      files_dir = nil;
    }
  } else {
    if (![dir_path isEqualToString:files_dir])
      [self updateFileList:dir_path fileName:dir_parts[[dir_parts count] - 1]];
  }
  [self setImage:image];
  return YES;
}

-(BOOL)updateFileList:(NSString*)dir fileName:(NSString*)file {
  static NSArray<NSURLResourceKey> *key = nil;
  static NSString *descriptor_key = nil;
  if (!key)
    switch (ctx.sort_type) {
      case ALPHABETIC:
        key =  @[NSURLPathKey];
        descriptor_key = @"path";
        break;
      case FSIZE:
        key = @[NSURLFileSizeKey];
        break;
      case MTIME:
        key = @[NSURLContentModificationDateKey];
        break;
      case CTIME:
        key = @[NSURLCreationDateKey];
        break;
      case FORMAT:
        descriptor_key = @"pathExtension";
      default:
        key = @[];
        break;
    }
  NSError *err = nil;
  NSMutableArray *all = [[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString:dir]
                                                       includingPropertiesForKeys:key
                                                                          options:0
                                                                            error:&err] mutableCopy];
  if (err) {
    NSLog(@"ERROR %ld: %@", (long)[err code], [err localizedDescription]);
    return NO;
  }
  
  switch (ctx.sort_type) {
    case FORMAT:
    case ALPHABETIC: {
      NSArray *tmp = [all sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:descriptor_key
                                                                                      ascending:!ctx.reverse_sort
                                                                                       selector:@selector(caseInsensitiveCompare:)]]];
      MEM_CHECK(tmp);
      all = [tmp mutableCopy];
      break;
    }
    case FSIZE:
    case MTIME:
    case CTIME:
      [all sortUsingComparator:^(NSURL *lURL, NSURL *rURL) {
        NSDate *lDate, *rDate;
        [lURL getResourceValue:&lDate
                        forKey:key[0]
                         error:nil];
        [rURL getResourceValue:&rDate
                        forKey:key[0]
                         error:nil];
        return ctx.reverse_sort ? [rDate compare:lDate] : [lDate compare:rDate];
      }];
      break;
    case RANDOM:
      for (NSInteger i = [all count] - 1; i > 0; i--)
        [all exchangeObjectAtIndex:i
                   withObjectAtIndex:(random() % ([all count] - i) + i)];
      break;
  }
  
  static NSPredicate *predicate = nil;
  if (!predicate)
    predicate = [NSPredicate predicateWithFormat:@"ANY %@ CONTAINS[c] pathExtension", ctx.extensions];
  MEM_CHECK(files = [[NSMutableArray alloc] init]);
  [[all filteredArrayUsingPredicate:predicate] enumerateObjectsUsingBlock:^(NSURL *fname, NSUInteger idx, BOOL *stop) {
    [files addObject:[fname lastPathComponent]];
  }];
  
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
  files_dir = [NSString stringWithFormat:@"%@/", dir];
  return YES;
}

-(BOOL)addImageList:(NSString*)path setImage:(BOOL)set {
  [files addObject:path];
  if (set)
    [self setImageIdx:[files count] - 1];
  return YES;
}

-(void)setErrorImg {
  if (!ctx.error_img) {
    NSData *data = [NSData dataWithBytes:(const void*)error_data length:sizeof(uint8_t) * error_data_size];
    MEM_CHECK(ctx.error_img = [NSImage alloc]);
    if (![ctx.error_img initWithData:data]) {
      NSLog(@"ERROR: Failed to recreate error image from memory");
      abort();
    }
  }
  image = ctx.error_img;
}

-(BOOL)setImageIdx:(NSInteger)idx {
  if (!files)
    return NO;
  files_cursor = idx;
  if (files_cursor < 0)
    files_cursor = [files count] - 1;
  if (files_cursor >= [files count])
    files_cursor = 0;
  if (![self loadImage:[NSString stringWithFormat: @"%@%@", files_dir ? files_dir : @"", files[files_cursor]]]) {
    alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", files[files_cursor]);
    [self setErrorImg];
  }
  if (ctx.slideshow && !timerPaused) {
    [self toggleSlideshow];
    [self toggleSlideshow];
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
                  animate:ctx.animate_window];
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
  if (ctx.single_window)
    single_window_view = app_view;
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
        if (ctx.single_window)
          [view addImageList:[url relativePath] setImage:(BOOL)!idx];
        else {
          if (!idx) {
            if (![view loadImage:[url relativePath]])
              [[self window] close];
            [view forceResize];
          } else {
            if (!createWindow([url relativePath]))
              alert(NSAlertStyleCritical, @"ERROR: Failed to load \"%@\"", [url relativePath]);
          }
        }
      }];
      break;
    }
    case 0x23: // P
      if (ctx.slideshow)
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
  NSRect windowFrame = [[self window] frame];
  dragPoint = [NSEvent mouseLocation];
  dragPoint.x -= windowFrame.origin.x;
  dragPoint.y -= windowFrame.origin.y;
}

-(void)mouseDragged:(NSEvent *)theEvent {
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
  if (ctx.single_window && !ctx.first_window)
    return [single_window_view addImageList:path setImage:NO];
  if (ctx.first_window) {
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
    
    ctx.extensions = [NSArray arrayWithObjects:@"pdf", @"eps", @"epi",@"epsf",
                                               @"epsi", @"ps", @"tiff", @"tif",
                                               @"jpg", @"jpeg", @"jpe", @"gif",
                                               @"png", @"pict", @"pct", @"pic",
                                               @"bmp", @"BMPf", @"ico", @"icns",
                                               @"dng", @"cr2", @"crw", @"fpx",
                                               @"fpix", @"raf", @"dcr", @"ptng",
                                               @"pnt", @"mac", @"mrw", @"nef",
                                               @"orf", @"exr", @"psd", @"qti",
                                               @"qtif", @"hdr", @"sgi", @"srf",
                                               @"targa", @"tga", @"cur", @"xbm", nil];
  }
  
  id app_del = [[AppDelegate alloc] initWithPath:path];
  MEM_CHECK(app_del);
  if (ctx.first_window) {
    [NSApp setDelegate:app_del];
    ctx.first_window = NO;
  }
  return YES;
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    static struct option options[] = {
      { "slideshow",     no_argument,       0, 's' },
      { "slide-time",    required_argument, 0, 't' },
      { "slide-prev",    no_argument,       0, 'p' },
      { "fancy-window",  no_argument,       0, 'f' },
      { "single-window", no_argument,       0, '1' },
      { "sort",          optional_argument, 0, 'S' },
      { "reverse-sort",  optional_argument, 0, 'r' },
      { 0, 0, 0, 0 }
    };
    
    int opt, opt_idx = 0;
    while ((opt = getopt_long(argc, argv, "st:pf1r:S:", options, &opt_idx)) != -1) {
      switch (opt) {
        case '?':
        case 0:
          if (options[opt_idx].flag)
            break;
          printf ("option %s", options[opt_idx].name);
          if (optarg)
            printf (" with arg %s", optarg);
          printf ("\n");
          break;
        case 't':
          if ((ctx.slideshow_timer = atof(optarg)) <= 0) {
            ctx.slideshow = NO;
            ctx.slideshow_timer = DEFAULT_SLIDESHOW_TIMER;
          }
          break;
        case 's':
          ctx.slideshow = YES;
          break;
        case 'p':
          ctx.slideshow_prev = YES;
          break;
        case 'f':
          ctx.animate_window = YES;
          break;
        case '1':
          ctx.single_window = YES;
          break;
        case 'r':
          ctx.reverse_sort = YES;
        case 'S': {
          ctx.sort_files = YES;
          if (!optarg)
            break;
          NSString *arg = [[NSString stringWithString:@(optarg)] lowercaseString];
          if ([arg isEqualToString:@"alphabetic"])
            ctx.sort_type = ALPHABETIC;
          else if ([arg isEqualToString:@"fsize"])
            ctx.sort_type = FSIZE;
          else if ([arg isEqualToString:@"mtime"])
            ctx.sort_type = MTIME;
          else if ([arg isEqualToString:@"ctime"])
            ctx.sort_type = CTIME;
          else if ([arg isEqualToString:@"format"])
            ctx.sort_type = FORMAT;
          else if ([arg isEqualToString:@"random"])
            ctx.sort_type = RANDOM;
          else {
            NSLog(@"%s: invalid argument '%s' option -- %c", argv[0], optarg, opt);
            abort();
          }
          break;
        }
        default:
          abort();
      }
    }
    
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    if (optind < argc) {
      int n_windows = 0;
      while (optind < argc)
        if (createWindow(@(argv[optind++])))
          n_windows++;
      if (n_windows)
        goto SUCCESS;
    }
    alert(NSAlertStyleInformational, @"No valid images passed through arguments");
    return 1;
    
  SUCCESS:
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
