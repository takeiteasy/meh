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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
#pragma clang diagnostic pop
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#if defined(MEH_ANIMATE_RESIZE)
static BOOL animate_window = YES;
#else
static BOOL animate_window = NO;
#endif

static int w, h, c, last_img_failed = 0;
static unsigned char *orig_buf, *buf;
static char *cdir, *cpath;
static const char* valid_exts[11] = {
  ".jpg", ".jpeg", ".png",
  ".bmp", ".tga",  ".psd",
  ".gif", ".hdr",  ".pic",
  ".pnm", ".pgm"
};
static char** dir_imgs;
static int dir_imgs_len, img_pos;

#define FREE_NULL(x) \
if (x) { \
  free(x); \
  x = NULL; \
}

void free_dir_imgs() {
  if (dir_imgs) {
    for (int i = 0; i < dir_imgs_len; ++i) {
      FREE_NULL(dir_imgs[i]);
    }
    FREE_NULL(dir_imgs);
  }
}

void free_imgs() {
  FREE_NULL(orig_buf);
  if (!last_img_failed) {
    FREE_NULL(buf);
  }
}

void free_paths() {
  FREE_NULL(cdir);
  FREE_NULL(cpath);
}

void cleanup() {
  free_imgs();
  free_paths();
  free_dir_imgs();
}

static int sort_strcmp(const void* a, const void* b) {
  return strcmp(*(const char**)a, *(const char**)b);
}

void sort(const char* arr[], int n) {
  qsort(arr, n, sizeof(const char*), sort_strcmp);
}

void get_dir_imgs(const char* path) {
  struct dirent* dir;
  DIR* d = opendir(path);
  if (!d)
    return;
  
  free_dir_imgs();
  dir_imgs = malloc(1024 * sizeof(char*));
  if (!dir_imgs) {
    fprintf(stderr, "malloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  
  int i = 0, j = 0, k = 1024;
  while ((dir = readdir(d)) != NULL) {
    if (dir->d_type == DT_REG) {
      char* ext = strrchr(dir->d_name, '.');
      if (!ext)
        continue;
      for (char* p = ext; *p; ++p)
        *p = tolower(*p);
      for (i = 0; i < 11; ++i) {
        if (strcmp(ext, valid_exts[i]) == 0) {
          dir_imgs[j] = malloc(strlen(dir->d_name));
          strcpy(dir_imgs[j], dir->d_name);
          j += 1;
          if (j == k) {
            k += 1024;
            dir_imgs = realloc(dir_imgs, k * sizeof(char*));
          }
          break;
        }
      }
    }
  }
  sort((const char**)dir_imgs, j);
  dir_imgs_len = j;
  closedir(d);
}

int load_img(const char* path) {
  free_imgs();
  orig_buf = stbi_load(path, &w, &h, &c, 4);
  if (!orig_buf) {
    orig_buf = NULL;
    printf("stbi_load(%s) failed: %s\n", path, stbi_failure_reason());
    return 0;
  }
  buf = malloc(w * h * 4);
  memcpy(buf, orig_buf, w * h * 4);
  return 1;
}

int load_first_img(const char* path) {
  if (!load_img(path))
    return 0;
  free_paths();
  cdir = dirname((char*)path);
  cpath = strdup(path);
  return 1;
}

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
    case 0x26: // J
    case 0x28: // K
      if (!dir_imgs) {
        get_dir_imgs(cdir);
        char* tmp = basename(cpath);
        for (int i = 0; i < dir_imgs_len; ++i) {
          if (strcmp(tmp, dir_imgs[i]) == 0) {
            img_pos = i;
            break;
          }
        }
        free(tmp);
      }
      
      if ([event keyCode] == 0x26)
        img_pos--;
      else
        img_pos++;
      
      if (img_pos < 0)
        img_pos = dir_imgs_len - 1;
      else if (img_pos == dir_imgs_len)
        img_pos = 0;
      
      free(cpath);
      size_t needed = snprintf(NULL, 0, "%s/%s", cdir, dir_imgs[img_pos]) + 1;
      char* buffer = malloc(needed);
      snprintf(buffer, needed, "%s/%s", cdir, dir_imgs[img_pos]);
      cpath = buffer;
      
      if (!load_img(cpath)) {
        last_img_failed = 1;
        w = 640;
        h = 480;
        int s = w * h * 4;
        orig_buf = malloc(s);
        memset(orig_buf, 0, s);
        for (int i = 0; i < s; i += 4) {
          orig_buf[i + 0] = 255;
          orig_buf[i + 1] = 0;
          orig_buf[i + 2] = 255;
          orig_buf[i + 3] = 255;
        }
        buf = orig_buf;
        [[self window] setStyleMask:[[self window] styleMask] & ~NSWindowStyleMaskResizable];
      } else {
        if (last_img_failed) {
          [[self window] setStyleMask:[[self window] styleMask] | NSWindowStyleMaskResizable];
          [[[self window] standardWindowButton:NSWindowZoomButton] setHidden:YES];
          [[[self window] standardWindowButton:NSWindowCloseButton] setHidden:YES];
          [[[self window] standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
        }
        last_img_failed = 0;
      }
      
      NSRect frame = [[self window] frame];
      frame.size.width  = w;
      frame.size.height = h;
      [[self window] setFrame:frame
                      display:YES
                      animate:animate_window];
      break;
    default:
      break;
  }
}

-(void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = [self bounds];
  if (!last_img_failed) {
    buf = realloc(buf, bounds.size.width * bounds.size.height * 4);
    stbir_resize_uint8(orig_buf, w, h, 0, buf, bounds.size.width, bounds.size.height, 0, 4);
  }
  
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

void create_window() {
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
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    int n_windows = 0;
    for (int i = 1; i < argc; ++i) {
      if (load_first_img(argv[i])) {
        create_window();
        n_windows++;
      }
    }
    if (!n_windows) {
      fprintf(stderr, "No valid images passed to arguments.\n");
      return 1;
    }
    atexit(cleanup);
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
