/* meh -- feh-like image viewer for Mac [https://github.com/takeiteasy/meh]
 
 The MIT License (MIT)

 Copyright (c) 2022 George Watson

 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without restriction,
 including without limitation the rights to use, copy, modify, merge,
 publish, distribute, sublicense, and/or sell copies of the Software,
 and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Cocoa/Cocoa.h>
#include <getopt.h>

#define SORT_TYPES              \
    X("alphabetic", ALPHABETIC) \
    X("fsize", FSIZE)           \
    X("mtime", MTIME)           \
    X("ctime", CTIME)           \
    X("format", FORMAT)         \
    X("random", RANDOM)
typedef enum {
#define X(_, E) SORT_##E,
    SORT_TYPES
#undef X
} FileSortType;

static FileSortType settingSortBy = SORT_ALPHABETIC;
static BOOL settingReverseSort = NO;
static BOOL settingsSlideshow = NO;
static double settingsSlideshowDelay = 5.0;
static BOOL settingsSlideshowReverse = NO;
static BOOL settingsQuitAtEnd = NO;
static BOOL enableResizeAnimations = YES;

static NSArray *validExtensions = @[@"pdf",   @"eps",  @"epi",  @"epsf",
                                    @"epsi",  @"ps",   @"tiff", @"tif",
                                    @"jpg",   @"jpeg", @"jpe",  @"gif",
                                    @"png",   @"pict", @"pct",  @"pic",
                                    @"bmp",   @"bmpf", @"ico",  @"icns",
                                    @"dng",   @"cr2",  @"crw",  @"fpx",
                                    @"fpix",  @"raf",  @"dcr",  @"ptng",
                                    @"pnt",   @"mac",  @"mrw",  @"nef",
                                    @"orf",   @"exr",  @"psd",  @"qti",
                                    @"qtif",  @"hdr",  @"sgi",  @"srf",
                                    @"targa", @"tga",  @"cur",  @"xbm"];

static struct option long_options[] = {
    {"sort", required_argument, NULL, 's'},
    {"reverse", no_argument, NULL, 'r'},
    {"slideshow", optional_argument, NULL, 'S'},
    {"slideshow-delay", required_argument, NULL, 'd'},
    {"slideshow-reverse", no_argument, NULL, 'R'},
    {"disable-animations", no_argument, NULL, 'A'},
    {"quit", no_argument, NULL, 'q'},
    {"help", no_argument, NULL, 'h'},
    {NULL, 0, NULL, 0}
};

static void usage(void) {
    puts("usage: meh [files...] [options]");
    puts("");
    puts("  Arguments:");
    puts("    * -s/--sort -- Specify file list sort [default: alphabetic]");
    printf("      * options: ");
#define X(S, _) S,
    const char *sortingOptions[] = { SORT_TYPES NULL };
#undef X
    int sizeOfSortingOptions = (sizeof(sortingOptions) / sizeof(const char*)) - 1;
    for (int i = 0; i < sizeOfSortingOptions; i++)
        printf("%s%s", sortingOptions[i], i == sizeOfSortingOptions - 1 ? "\n" : ", ");
    puts("    * -r/--reverse -- Enable reversed sorting");
    puts("    * -S/--slideshow -- Enable slideshow mode");
    puts("    * -d/--slideshow-delay -- Set slideshow delay [.1-60, default delay: 5 seconds]");
    puts("    * -R/--slideshow-reverse -- Enable slideshow reverse order");
    puts("    * -A/--disable-animations -- Disable resizing animation for windows [warning: slow]");
    puts("    * -q/--quit -- Close window when last image reached");
    puts("    * -h/--help -- Print this message");
    puts("");
    puts("  Keys:");
    puts("    * CMD+Q -- Quit applications");
    puts("    * ESC/Q -- Close window");
    puts("    * J/Arrow Left/Arrow Down -- Previous image");
    puts("    * K/Arrow Right/Arrow Up -- Next image");
    puts("    * O -- Open file dialog");
    puts("    * S -- Toggle slideshow");
    puts("");
    puts("  File types:");
    printf("    * ");
    for (int i = 0; i < [validExtensions count]; i++)
        printf("%s%s", [validExtensions[i] UTF8String], i == [validExtensions count] - 1 ? "\n" : ", ");
}
#define USAGE(N)  \
    do {          \
        usage();  \
        return N; \
    } while(0)

#if defined(DEBUG)
#define LOG(fmt, ...) NSLog(@"DEBUG: " fmt, __VA_ARGS__)
#else
#define LOG(...)
#endif

#if !defined(MIN)
#define MIN(a, b) (a < b ? a : b)
#endif
#if !defined(MAX)
#define MAX(a, b) (a > b ? a : b)
#endif
#if !defined(CLAMP)
#define CLAMP(n, min, max) (MIN(MAX(n, min), max))
#endif

static NSString* fileExtension(NSString *path) {
    return [[path pathExtension] lowercaseString];
}

BOOL alert(enum NSAlertStyle style, NSString *fmt, ...) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:style];
    [alert addButtonWithTitle:@"OK"];
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [alert setMessageText:msg];
    return [alert runModal] == NSAlertFirstButtonReturn;
}
#define PANIC(fmt, ...)                                           \
    do {                                                          \
        alert(NSAlertStyleCritical, @"ERROR! " fmt, __VA_ARGS__); \
        [NSApp terminate:nil];                                    \
    } while(0)
#define WARN(fmt, ...) alert(NSAlertStyleWarning, @"WARNING! " fmt, __VA_ARGS__)

static NSArray* openDialog(NSString *dir) {
    NSOpenPanel *dialog = [NSOpenPanel openPanel];
    if (dir)
        [dialog setDirectoryURL:[NSURL fileURLWithPath:dir]];
    // TODO: setAllowedFileTypes deprecated for setAllowedContentTypes in 12.0
    //       Unsured how setAllowedContentTypes works, this still works for now
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [dialog setAllowedFileTypes:validExtensions];
#pragma clang diagnostic pop
    [dialog setAllowsMultipleSelection:YES];
    [dialog setCanChooseFiles:YES];
    [dialog setCanChooseDirectories:NO];
    if ([dialog runModal] != NSModalResponseOK)
        return nil;
    NSMutableArray *result = [[NSMutableArray alloc] init];
    for (NSURL *url in [dialog URLs])
        [result addObject:[url path]];
    return result;
}

static NSString* resolvePath(NSString *path) {
    return [[NSURL fileURLWithPath:[path stringByExpandingTildeInPath]] path];
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSMutableArray *windows;
}
- (BOOL)createNewWindow:(NSString*)path;
@end

@interface AppSubView : NSView {
    NSPoint dragPoint;
}
@end

@interface AppView : NSImageView {
    AppSubView *subView;
    NSImage *image;
    NSString *dir, *file;
    NSMutableArray *files;
    NSInteger fileIdx;
    BOOL fileError;
    BOOL slideshowEnabled;
    NSTimer *errorUpdate, *slideshowUpdate;
}
- (void)toggleSlideshow;
- (void)loadImageRestart:(NSString*)path;
- (void)previousImage;
- (void)nextImage;
- (NSString*)currentDirectory;
@end

@implementation AppSubView
- (id)initWithFrame:(NSRect)frame {
    return [super initWithFrame:frame];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent*)event {
    (void)event;
}

- (void)keyUp:(NSEvent*)event {
    switch ([event keyCode]) {
        case 0x35: // ESC
        case 0x0C: // Q
            [[self window] close];
            break;
        case 0x7b: // Arrow key left
        case 0x7d: // Arrow key down
        case 0x26: // J
            [(AppView*)[self superview] previousImage];
            break;
        case 0x7e: // Arrow key up
        case 0x7c: // Arrow key right
        case 0x28: // K
            [(AppView*)[self superview] nextImage];
            break;
        case 0x1f: { // O
            AppView *view = (AppView*)[self superview];
            NSArray *files = openDialog([view currentDirectory]);
            if (!files || ![files count])
                break;
            [view loadImageRestart:files[0]];
            for (int i = 1; i < [files count]; i++)
                if (![(AppDelegate*)[[NSApplication sharedApplication] delegate] createNewWindow:files[i]])
                    WARN("Failed to load \"%@\"", files[i]);
            break;
        }
        case 0x1:
            [(AppView*)[self superview] toggleSlideshow];
            break;
        default:
            LOG("Unrecognized key: 0x%x", [event keyCode]);
            break;
    }
}

- (void)mouseDown:(NSEvent *)theEvent {
  NSRect windowFrame = [[self window] frame];
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

@implementation AppView
- (id)initWithFrame:(NSRect)frame imagePath:(NSString*)path {
    if (self = [super initWithFrame:frame]) {
        subView = [[AppSubView alloc] initWithFrame:frame];
        [self addSubview:subView];
        
        NSArray *dirParts = [path pathComponents];
        dir = [NSString pathWithComponents:[dirParts subarrayWithRange:(NSRange){ 0, [dirParts count] - 1}]];
        file = dirParts[[dirParts count] - 1];
        [self updateFilesList];
        fileError = NO;
        
        if (![self loadImage:path])
            return nil;
        
        slideshowEnabled = NO;
        if (settingsSlideshow)
            [self toggleSlideshow];
        
        [self setAnimates:enableResizeAnimations];
        [self setCanDrawSubviewsIntoLayer:YES];
        [self setImageScaling:NSImageScaleAxesIndependently];
    }
    return self;
}

- (void)updateSlideshow {
    if (settingsSlideshowReverse)
        [self previousImage];
    else
        [self nextImage];
}

- (void)toggleSlideshow {
    if (!slideshowEnabled) {
        slideshowEnabled = YES;
        slideshowUpdate = [NSTimer scheduledTimerWithTimeInterval:settingsSlideshowDelay
                                                           target:self
                                                         selector:@selector(updateSlideshow)
                                                         userInfo:nil
                                                          repeats:YES];
    } else {
        slideshowEnabled = NO;
        [slideshowUpdate invalidate];
    }
}

- (void)updateFilesList {
    static NSArray<NSURLResourceKey> *key = nil;
    static NSString *descKey = nil;
    if (!key)
        switch (settingSortBy) {
            case SORT_ALPHABETIC:
                key =  @[NSURLPathKey];
                descKey = @"path";
                break;
            case SORT_FSIZE:
                key = @[NSURLFileSizeKey];
                break;
            case SORT_MTIME:
                key = @[NSURLContentModificationDateKey];
                break;
            case SORT_CTIME:
                key = @[NSURLCreationDateKey];
                break;
            case SORT_FORMAT:
                descKey = @"pathExtension";
            default:
                key = @[];
                break;
        }
    
    NSError *err = nil;
    NSMutableArray *all = [[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL URLWithString:dir]
                                                         includingPropertiesForKeys:key
                                                                            options:0
                                                                              error:&err] mutableCopy];
    if (err)
        PANIC("%ld: %@", (long)[err code], [err localizedDescription]);
    
    switch (settingSortBy) {
        case SORT_FORMAT:
        case SORT_ALPHABETIC: {
            NSArray *tmp = [all sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:descKey
                                                                                            ascending:!settingReverseSort
                                                                                             selector:@selector(caseInsensitiveCompare:)]]];
            all = [tmp mutableCopy];
            break;
        }
        case SORT_FSIZE:
        case SORT_MTIME:
        case SORT_CTIME:
            [all sortUsingComparator:^(NSURL *lURL, NSURL *rURL) {
                NSDate *lDate, *rDate;
                [lURL getResourceValue:&lDate
                                forKey:key[0]
                                 error:nil];
                [rURL getResourceValue:&rDate
                                forKey:key[0]
                                 error:nil];
                return settingReverseSort ? [rDate compare:lDate] : [lDate compare:rDate];
            }];
            break;
        case SORT_RANDOM:
            for (NSInteger i = [all count] - 1; i > 0; i--)
                [all exchangeObjectAtIndex:i
                         withObjectAtIndex:(random() % ([all count] - i) + i)];
            break;
    }
    
    static NSPredicate *predicate = nil;
    if (!predicate)
        predicate = [NSPredicate predicateWithFormat:@"ANY %@ MATCHES[c] pathExtension", validExtensions];
    files = [[NSMutableArray alloc] init];
    [[all filteredArrayUsingPredicate:predicate] enumerateObjectsUsingBlock:^(NSURL *fname, NSUInteger idx, BOOL *stop) {
        [files addObject:[fname lastPathComponent]];
    }];
    
    fileIdx = -1;
    [files enumerateObjectsUsingBlock:^(NSString *fname, NSUInteger idx, BOOL *stop) {
        if ([fname isEqualToString:file]) {
            fileIdx = idx;
            *stop = YES;
        }
    }];
    if (fileIdx == -1)
        PANIC("Couldn't file \"%@\" in \"%@\"", file, dir);
}

- (BOOL)checkImage:(NSString*)path {
    if (![validExtensions containsObject:fileExtension(path)])
        return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return NO;
    return YES;
}

- (BOOL)loadImage:(NSString*)path {
    if (![self checkImage:path])
        return NO;
    if (!(image = [[NSImage alloc] initWithContentsOfFile:path]))
        return NO;
    [self setImage:image];
    [self forceResize:CGSizeMake([image size].width, [image size].height)
     enableAnimations:enableResizeAnimations];
    return YES;
}

- (void)setImageIdx:(NSInteger)idx {
    if (idx < 0) {
        if (settingsQuitAtEnd)
            [[self window] close];
        idx = [files count] - 1;
    }
    if (idx >= [files count]) {
        if (settingsQuitAtEnd)
            [[self window] close];
        idx = 0;
    }
    fileIdx = idx;
    NSString *path = [NSString stringWithFormat:@"%@/%@", dir, files[fileIdx]];
    fileError = ![self loadImage:path];
    if (fileError) {
        WARN("Failed to load \"%@\"", path);
        [self enableErrorImage];
    }
}

- (void)previousImage {
    [self setImageIdx:fileIdx - 1];
}

- (void)nextImage {
    [self setImageIdx:fileIdx + 1];
}

- (NSString*)currentDirectory {
    return dir;
}

- (NSSize)currentImageSize {
    return [image size];
}

- (void)forceResize:(CGSize)size enableAnimations:(BOOL)enabledAnims {
    NSRect frame = [[self window] frame];
    CGPoint centre = CGPointMake(frame.origin.x + (frame.size.width / 2),
                                 frame.origin.y + (frame.size.height / 2));
    frame.size = size;
    frame.origin = CGPointMake(centre.x - (frame.size.width / 2),
                               centre.y - (frame.size.height / 2));
    [[self window] setFrame:frame
                    display:YES
                    animate:enabledAnims];
    [subView setFrame:NSMakeRect(0.f, 0.f, frame.size.width, frame.size.height)];
    [self setNeedsDisplay:YES];
}

- (void)loadImageRestart:(NSString*)path {
    NSArray *dirParts = [path pathComponents];
    dir = [NSString pathWithComponents:[dirParts subarrayWithRange:(NSRange){ 0, [dirParts count] - 1}]];
    file = dirParts[[dirParts count] - 1];
    [self updateFilesList];
    fileError = ![self loadImage:path];
}

// TODO: NSFilenamesPboardType deprecated for NSPasteboardTypeFileURL or kUTTypeFileURL
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType])
        return [sender draggingSourceOperationMask] & NSDragOperationLink ? NSDragOperationLink : NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if (![[pboard types] containsObject:NSFilenamesPboardType] || !([sender draggingSourceOperationMask] & NSDragOperationLink))
        return NO;
    NSArray *links = [pboard propertyListForType:NSFilenamesPboardType];
    if (!links || ![links count])
        return NO;
    
    [self loadImageRestart:links[0]];
    for (int i = 1; i < [links count]; i++)
        if (![(AppDelegate*)[[NSApplication sharedApplication] delegate] createNewWindow:links[i]])
            WARN("Failed to load \"%@\"", links[i]);
    return YES;
}
#pragma clang diagnostic pop

- (void)magnifyWithEvent:(NSEvent*)event {
    float zoom = [event magnification] + 1.f;
    NSSize newSize = NSMakeSize([self frame].size.width * zoom,
                                [self frame].size.height * zoom);
    [self forceResize:newSize
     enableAnimations:NO];
}

- (void)enableErrorImage {
    fileError = YES;
    errorUpdate = [NSTimer scheduledTimerWithTimeInterval:1.
                                                   target:self
                                                 selector:@selector(updateErrorImage)
                                                 userInfo:nil
                                                  repeats:YES];
    [self setNeedsDisplay:YES];
}

- (void)disableErrorImage {
    fileError = NO;
    [errorUpdate invalidate];
}

- (void)updateErrorImage {
    if (!fileError)
        [self disableErrorImage];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!fileError) {
        [super drawRect:dirtyRect];
        return;
    }
    
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
    int *buffer = malloc(dirtyRect.size.width * dirtyRect.size.height * sizeof(int));
    for (int i = 0; i < dirtyRect.size.width * dirtyRect.size.height; i++) {
        int c = rand() % 256;
        buffer[i] = ((unsigned char)c << 16) | ((unsigned char)c << 8) | ((unsigned char)c);
    }
    CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef p = CGDataProviderCreateWithData(NULL, buffer, dirtyRect.size.width * dirtyRect.size.height * 4, NULL);
    CGImageRef img = CGImageCreate(dirtyRect.size.width, dirtyRect.size.height, 8, 32, dirtyRect.size.width * 4, s, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little, p, NULL, 0, kCGRenderingIntentDefault);
    CGContextDrawImage(ctx, dirtyRect, img);
    CGColorSpaceRelease(s);
    CGDataProviderRelease(p);
    CGImageRelease(img);
    free(buffer);
    CGContextFlush(ctx);
}
@end

@implementation AppDelegate : NSObject
- (BOOL)createNewWindow:(NSString*)path {
#define BAIL(MSG)                                \
    do {                                         \
        NSLog(@"ERROR! %s (\"%@\")", MSG, path); \
        return NO;                               \
    } while(0)
    
    if (![validExtensions containsObject:fileExtension(path)])
        BAIL("Invalid file extension");
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        BAIL("File doesn't exist");
    
    CGSize screen = [[NSScreen mainScreen] frame].size;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(screen.width / 2, screen.height / 2, 0.f, 0.f)
                                                   styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@""];
    [window makeKeyAndOrderFront:nil];
    [window setMovableByWindowBackground:YES];
    [window setTitlebarAppearsTransparent:YES];
    [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [window setReleasedWhenClosed:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:window];
 
    id view = [AppView alloc];
    if (![view initWithFrame:NSZeroRect
                   imagePath:path]) {
        WARN("Failed to load image (\"%@\")", path);
        return NO;
    }
    [window setContentView:view];
    [view forceResize:[view currentImageSize]
     enableAnimations:enableResizeAnimations];
    
    [windows addObject:window];
    return YES;
#undef BAIL
}

- (id)initWithPaths:(NSArray*)paths {
    if (self = [super init]) {
        windows = [[NSMutableArray alloc] init];
        
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
        
        if (!paths || ![paths count])
            paths = openDialog(nil);
        if (!paths)
            return nil;
        
        for (NSString *path in [paths valueForKeyPath:@"@distinctUnionOfObjects.self"])
            [self createNewWindow:path];
        
        if (![windows count])
            PANIC("%s", "No files loaded, quitting");
    }
    return self;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
    (void)app;
    return YES;
}

- (void)windowWillClose:(NSNotification*)notification {
    [windows removeObject:[notification object]];
}
@end

int main(int argc, char *argv[]) {
    int opt;
    extern int optind;
    extern char* optarg;
    extern int optopt;
    while ((opt = getopt_long(argc, argv, ":hrs:d:S:RqA", long_options, NULL)) != -1) {
        switch (opt) {
            case 's': {
                NSString *sort = [@(optarg) lowercaseString];
#define X(S, E)                  \
if ([sort isEqualToString:@S]) { \
    settingSortBy = SORT_##E;    \
    break;                       \
}
                SORT_TYPES
#undef X
                printf("ERROR! Invalid sort argument \"%s\"\n", optarg);
                USAGE(EXIT_FAILURE);
            }
            case 'r':
                settingReverseSort = YES;
                break;
            case 'd':
                settingsSlideshowDelay = CLAMP(atof(optarg), 0, 60.);
                if (settingsSlideshowDelay == 0)
                    settingsSlideshowDelay = 5.0;
                break;
            case 'A':
                enableResizeAnimations = NO;
                break;
            case 'h':
                USAGE(EXIT_SUCCESS);
            case 'S':
                settingsSlideshow = YES;
                settingsSlideshowDelay = CLAMP(atof(optarg), 0, 60.);
                if (settingsSlideshowDelay == 0)
                    settingsSlideshowDelay = 5.0;
                break;
            case 'R':
                settingsSlideshowReverse = YES;
                break;
            case 'q':
                settingsQuitAtEnd = YES;
                break;
            case ':':
                switch (optopt) {
                    case 'S':
                        settingsSlideshow = YES;
                        break;
                    default:
                        printf("ERROR: \"-%c\" requires an value!\n", optopt);
                        USAGE(EXIT_FAILURE);
                }
                break;
            case '?':
                printf("ERROR: Unknown argument \"-%c\"\n", optopt);
                USAGE(EXIT_FAILURE);
        }
    }
    
    @autoreleasepool {
        NSMutableArray *files = nil;
        if (optind < argc) {
            files = [[NSMutableArray alloc] init];
            while (optind < argc)
                [files addObject:resolvePath(@(argv[optind++]))];
        }
        
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *appDel = [[AppDelegate new] initWithPaths:files];
        if (!appDel)
            return EXIT_FAILURE;
        [NSApp setDelegate:appDel];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return EXIT_SUCCESS;
}
