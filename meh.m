//
//  meh.m
//  meh
//
//  Created by Rory B. Bellows on 19/12/2017.
//  Copyright © 2017 Rory B. Bellows. All rights reserved.
//

/* TODO
 *  - FIX: Sometimes just randomly crashes for no reason at [NSApp run] ????
 *  - FIX: Handle images bigger than screen & preserve aspect ratio on resize
 *  - Different backends (Metal/OpenGL)
 *  - cURL integration
 *  - Animated GIFs (https://gist.github.com/urraka/685d9a6340b26b830d49)
 *  - EXIF info
 *  - FIX: Offset origin when changing images
 *  - Slideshow
 *  - Handle alpha
 *  - Argument parsing
 */

#include <stdio.h>
#include <dirent.h>
#include <libgen.h>
#include <string.h>
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#define STB_IMAGE_IMPLEMENTATION
#include "3rdparty/stb_image.h"

#define TOTAL_VALID_EXTS 12
static const char* valid_exts[TOTAL_VALID_EXTS] = {
  ".jpg", ".jpeg", ".png", ".bmp",
  ".tga", ".psd",  ".gif", ".hdr",
  ".pic", ".pnm", ".pgm",  ".tiff"
};

typedef struct {
  int w, h, c;
  unsigned char* buf;
  char* path;
} image_t;

#define BPP 4

image_t* load_img(const char* path) {
  image_t* img = malloc(sizeof(image_t));
  if (!img) {
    fprintf(stderr, "malloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  
  img->buf = stbi_load(path, &img->w, &img->h, &img->c, STBI_rgb_alpha);
  if (!img->buf) {
    fprintf(stderr, "stbi_load() failed\n");
    [NSApp terminate:nil];
  }
  
  img->path = strdup(path);
  return img;
}

static int sort_strcmp(const void* a, const void* b) {
  return strcmp(*(const char**)a, *(const char**)b);
}

void sort(const char* arr[], int n) {
  qsort(arr, n, sizeof(const char*), sort_strcmp);
}

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

@interface AppView : NSView {
  image_t* img;
  char* dir;
  char** dir_imgs;
  int dir_imgs_len, img_pos;
}

-(void)populate_dir_imgs;
-(void)free_img;
@end

@implementation AppView
-(void)populate_dir_imgs {
  DIR* d = opendir(self->dir);
  if (!d)
    return;
  
  dir_imgs = malloc(1024 * sizeof(char*));
  if (!dir_imgs) {
    fprintf(stderr, "malloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  
  int i = 0, j = 0, k = 1024;
  struct dirent* dir;
  while ((dir = readdir(d)) != NULL) {
    if (dir->d_type == DT_REG) {
      char* ext = strrchr(dir->d_name, '.');
      if (!ext)
        continue;
      for (char* p = ext; *p; ++p)
        *p = tolower(*p);
      for (i = 0; i < TOTAL_VALID_EXTS; ++i) {
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

-(id)initWithFrame:(NSRect)frame Image:(image_t*)img {
  if (self = [super initWithFrame:frame]) {
    self->img = img;
  }
  return self;
}

-(void)free_img {
  if (img) {
    free(img->buf);
    free(img->path);
    free(img);
  }
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
    case 0x28: // K
      if (!dir_imgs) {
        self->dir = dirname(img->path);
        [self populate_dir_imgs];
        
        char* tmp = basename(img->path);
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
      
      size_t needed = snprintf(NULL, 0, "%s/%s", dir, dir_imgs[img_pos]) + 1;
      char* buffer = malloc(needed);
      snprintf(buffer, needed, "%s/%s", dir, dir_imgs[img_pos]);
      
      [self free_img];
      if (!(img = load_img(buffer)))
        [[self window] close];
      
      NSRect frame = [[self window] frame];
      frame.size.width  = img->w;
      frame.size.height = img->h;
      [[self window] setFrame:frame
                      display:YES
                      animate:animate_window];
      [self setNeedsDisplay:YES];
      break;
    default:
      break;
  }
}

-(void)drawRect:(NSRect)dirtyRect {
  NSRect bounds = [self bounds];
  
  CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
  
  CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB();
  CGDataProviderRef p = CGDataProviderCreateWithData(NULL, img->buf, img->w * img->h * BPP, NULL);
  CGImageRef cgir = CGImageCreate(img->w, img->h, 8, 32, img->w * BPP, s, kCGBitmapByteOrderDefault, p, NULL, false, kCGRenderingIntentDefault);
  
  CGColorSpaceRelease(s);
  CGDataProviderRelease(p);
  
  CGContextDrawImage(ctx, CGRectMake(0, 0, bounds.size.width, bounds.size.height), cgir);
  
  CGImageRelease(cgir);
}

-(void)dealloc {
  [self free_img];
  if (dir_imgs) {
    for (int i = 0; i < dir_imgs_len; ++i)
      if (dir_imgs[i])
        free(dir_imgs[i]);
    free(dir_imgs);
  }
}
@end

int create_window(const char* path) {
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
  
  image_t* img = load_img(path);
  if (!img)
    return 0;
  
  id window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, img->w, img->h)
                                          styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
  if (!window) {
    fprintf(stderr, "alloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  
  [window center];
  [window setTitle:@""];
  [window makeKeyAndOrderFront:nil];
  [window setMovableByWindowBackground:YES];
  [window setTitlebarAppearsTransparent:YES];
  [[window standardWindowButton:NSWindowZoomButton] setHidden:YES];
  [[window standardWindowButton:NSWindowCloseButton] setHidden:YES];
  [[window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
  
  id app_del = [AppDelegate alloc];
  if (!app_del) {
    fprintf(stderr, "alloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  [NSApp setDelegate:app_del];
  id app_view = [[AppView alloc] initWithFrame:NSMakeRect(0, 0, img->w, img->h)
                                         Image:img];
  [window setContentView:app_view];
  
  return 1;
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    int n_windows = 0;
    for (int i = 1; i < argc; ++i)
      if (create_window(argv[i]))
        n_windows++;
    if (!n_windows) {
      fprintf(stderr, "No valid images passed through arguments\n");
      return 1;
    }
    
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}

