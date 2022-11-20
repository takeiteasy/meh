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

typedef enum {
    ALPHABETIC,
    FSIZE,
    MTIME,
    CTIME,
    FORMAT,
    RANDOM
} FileSortType;

static FileSortType settingSortBy = ALPHABETIC;
static BOOL settingReverseSort = NO;

static NSArray *validExtensions = @[@"pdf", @"eps", @"epi",@"epsf",
                                    @"epsi", @"ps", @"tiff", @"tif",
                                    @"jpg", @"jpeg", @"jpe", @"gif",
                                    @"png", @"pict", @"pct", @"pic",
                                    @"bmp", @"BMPf", @"ico", @"icns",
                                    @"dng", @"cr2", @"crw", @"fpx",
                                    @"fpix", @"raf", @"dcr", @"ptng",
                                    @"pnt", @"mac", @"mrw", @"nef",
                                    @"orf", @"exr", @"psd", @"qti",
                                    @"qtif", @"hdr", @"sgi", @"srf",
                                    @"targa", @"tga", @"cur", @"xbm"];

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
#if __MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_12_0
    [dialog setAllowedFileTypes:validExtensions];
#else
    [dialog setAllowedContentTypes:validExtensions];
#endif
    [dialog setAllowsMultipleSelection:YES];
    [dialog setCanChooseFiles:YES];
    [dialog setCanChooseDirectories:NO];
    return  [dialog runModal] == NSModalResponseOK ? [dialog URLs] : nil;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSMutableArray *windows;
}
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
}
-(BOOL)previousImage;
-(BOOL)nextImage;
@end

@implementation AppSubView
-(id)initWithFrame:(NSRect)frame {
    return [super initWithFrame:frame];
}

-(BOOL)acceptsFirstResponder {
    return YES;
}

-(void)keyDown:(NSEvent*)event {
    (void)event;
}

-(void)keyUp:(NSEvent*)event {
#define WINDOW [self window]
#define VIEW ((AppView*)[self superview])
#define DELEGATE ((AppDelegate*)[[self window] delegate])
    
    switch ([event keyCode]) {
        case 0x35: // ESC
        case 0x0C: // Q
            [WINDOW close];
            break;
        case 0x7b: // Arrow key left
        case 0x7d: // Arrow key down
        case 0x26: // J
            [VIEW previousImage];
            break;
        case 0x7e: // Arrow key up
        case 0x7c: // Arrow key right
        case 0x28: // K
            [VIEW nextImage];
            break;
        default:
#if DEBUG
            NSLog(@"DEBUG: Unrecognized key: 0x%x", [event keyCode]);
#endif
            break;
    }
}
@end

@implementation AppView
-(id)initWithFrame:(NSRect)frame imagePath:(NSString*)path {
    if (self = [super initWithFrame:frame]) {
        subView = [[AppSubView alloc] initWithFrame:frame];
        [self addSubview:subView];
        
        NSArray *dirParts = [path pathComponents];
        dir = [NSString pathWithComponents:[dirParts subarrayWithRange:(NSRange){ 0, [dirParts count] - 1}]];
        file = dirParts[[dirParts count] - 1];
        [self updateFilesList];
        
        if (![self loadImage:path])
            return nil;
        [self setAnimates:YES];
        [self setCanDrawSubviewsIntoLayer:YES];
        [self setImageScaling:NSImageScaleAxesIndependently];
    }
    return self;
}

-(void)updateFilesList {
    static NSArray<NSURLResourceKey> *key = nil;
    static NSString *descKey = nil;
    if (!key)
        switch (settingSortBy) {
            case ALPHABETIC:
                key =  @[NSURLPathKey];
                descKey = @"path";
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
        case FORMAT:
        case ALPHABETIC: {
            NSArray *tmp = [all sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:descKey
                                                                                            ascending:!settingReverseSort
                                                                                             selector:@selector(caseInsensitiveCompare:)]]];
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
                return settingReverseSort ? [rDate compare:lDate] : [lDate compare:rDate];
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
        predicate = [NSPredicate predicateWithFormat:@"ANY %@ MATCHES[c] pathExtension", validExtensions];
    files = [[NSMutableArray alloc] init];
    [[all filteredArrayUsingPredicate:predicate] enumerateObjectsUsingBlock:^(NSURL *fname, NSUInteger idx, BOOL *stop) {
        NSLog(@"%@ %@", fname, [fname lastPathComponent]);
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

-(BOOL)loadImage:(NSString*)path {
    if (!(image = [[NSImage alloc] initWithContentsOfFile:path]))
        return NO;
    [self setImage:image];
    return YES;
}

-(BOOL)setImageIdx:(NSInteger)idx {
    if (idx < 0)
        idx = [files count] - 1;
    if (idx >= [files count])
        idx = 0;
    fileIdx = idx;
    if (![self loadImage:[NSString stringWithFormat:@"%@/%@", dir, files[fileIdx]]])
        return NO;
    [self forceResize];
    return YES;
}

-(BOOL)previousImage {
    return [self setImageIdx:fileIdx - 1];
}

-(BOOL)nextImage {
    return [self setImageIdx:fileIdx + 1];
}

-(void)forceResize {
    NSRect frame = [[self window] frame];
    frame.size = [image size];
    [[self window] setFrame:frame
                    display:YES
                    animate:YES];
    [subView setFrame:NSMakeRect(0.f, 0.f, frame.size.width, frame.size.height)];
    [self setNeedsDisplay:YES];
}
@end

@implementation AppDelegate : NSObject
-(BOOL)createNewWindow:(NSString*)path {
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
    
    id view = [AppView alloc];
    if (![view initWithFrame:NSZeroRect
                   imagePath:path])
        WARN("Failed to load image (\"%@\")", path);
    [window setContentView:view];
    [view forceResize];
    
    [windows addObject:window];
    return YES;
#undef BAIL
}

-(id)initWithPaths:(NSArray*)paths {
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
        
        if (!paths)
            paths = openDialog(nil);
        
        for (NSString *path in [paths valueForKeyPath:@"@distinctUnionOfObjects.self"])
            [self createNewWindow:path];
        
        if (![windows count])
            PANIC("%s", "No files loaded, quitting");
    }
    return self;
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
    (void)app;
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp setDelegate:[[AppDelegate new] initWithPaths:@[@"/Users/george/git/meh/lenna.png"]]];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
