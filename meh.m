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
#import <Cocoa/Cocoa.h>
#define STBI_NO_GIF 1
#define STB_IMAGE_IMPLEMENTATION
#include "3rdparty/stb_image.h"
#include "3rdparty/gif_load.h"

#define TOTAL_VALID_EXTS 12
static const char* valid_exts[TOTAL_VALID_EXTS] = {
  ".jpg", ".jpeg", ".png", ".bmp",
  ".tga", ".psd",  ".gif", ".hdr",
  ".pic", ".pnm", ".pgm",  ".tiff"
};

typedef struct {
  int w, h, delay, total_frames, cur_frame;
  uint32_t** frames;
} gif_info_t;

typedef struct {
  int w, h, c;
  gif_info_t* gif;
  void* buf;
  char* path;
} image_t;

#define BPP 4

int endswith(const char* haystack, const char* needle) {
  size_t hlen = strlen(haystack);
  size_t nlen = strlen(needle);
  if(nlen > hlen)
    return 0;
  return (strcmp(&haystack[hlen - nlen], needle)) == 0;
}

#pragma pack(push, 1)
typedef struct {
  void *data, *draw;
  gif_info_t* info;
  unsigned long size;
} gif_data_t;
#pragma pack(pop)

#ifndef O_BINARY
#define O_BINARY 0
#endif

void gif_frame(void *data, GIF_WHDR *whdr) {
  uint32_t x, y, yoff, iter, ifin, dsrc, ddst;
  gif_data_t* gif = (gif_data_t*)data;
  
#define BGRA(i) \
  ((uint32_t)(whdr->cpal[whdr->bptr[i]].R << ((GIF_BIGE)? 8 : 16)) | \
  (uint32_t)(whdr->cpal[whdr->bptr[i]].G << ((GIF_BIGE)? 16 : 8)) | \
  (uint32_t)(whdr->cpal[whdr->bptr[i]].B << ((GIF_BIGE)? 24 : 0)) | \
  ((whdr->bptr[i] != whdr->tran)? (GIF_BIGE)? 0xFF : 0xFF000000 : 0))
  
  unsigned long sz = (unsigned long)(whdr->xdim * whdr->ydim);
  if (!whdr->ifrm) {
    gif->draw = calloc(sizeof(uint32_t), sz);
    gif->info->delay = (int)whdr->time;
    gif->info->w = (int)whdr->xdim;
    gif->info->h = (int)whdr->ydim;
    gif->info->total_frames = (int)whdr->nfrm;
    gif->info->cur_frame = 1;
    gif->info->frames = calloc(sizeof(uint32_t*), gif->info->total_frames);
  }
  
  uint32_t* pict = (uint32_t*)gif->draw;
  ddst = (uint32_t)(whdr->xdim * whdr->fryo + whdr->frxo);
  ifin = (!(iter = (whdr->intr)? 0 : 4))? 4 : 5; /** interlacing support **/
  for (dsrc = (uint32_t)-1; iter < ifin; iter++)
    for (yoff = 16U >> ((iter > 1)? iter : 1), y = (8 >> iter) & 7;
         y < (uint32_t)whdr->fryd; y += yoff)
      for (x = 0; x < (uint32_t)whdr->frxd; x++)
        if (whdr->tran != (long)whdr->bptr[++dsrc])
          pict[(uint32_t)whdr->xdim * y + x + ddst] = BGRA(dsrc);
  if (whdr->mode == GIF_BKGD) /** cutting a hole for the next frame **/
    for (y = 0; y < (uint32_t)whdr->fryd; y++)
      for (x = 0; x < (uint32_t)whdr->frxd; x++)
        pict[(uint32_t)whdr->xdim * y + x + ddst] = BGRA(whdr->bkgd);
  
  uint32* tmp = calloc(sizeof(uint32_t), sz);
  memcpy(tmp, pict, sz * sizeof(uint32_t));
  gif->info->frames[(int)whdr->ifrm] = tmp;
  
#undef BGRA
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
-(void)load_img:(const char*)path;
-(void)free_img;
-(void)force_resize;
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
  struct dirent* dire;
  while ((dire = readdir(d)) != NULL) {
    if (dire->d_type == DT_REG) {
      char* ext = strrchr(dire->d_name, '.');
      if (!ext)
        continue;
      for (char* p = ext; *p; ++p)
        *p = tolower(*p);
      for (i = 0; i < TOTAL_VALID_EXTS; ++i) {
        if (strcmp(ext, valid_exts[i]) == 0) {
          dir_imgs[j] = malloc(strlen(dire->d_name));
          strcpy(dir_imgs[j], dire->d_name);
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

-(id)initWithFrame:(NSRect)frame Image:(const char*)path {
  [self load_img:path];
  [NSTimer scheduledTimerWithTimeInterval:.1f target:self selector:@selector(handleTimer:) userInfo:nil repeats:YES];
  self = [super initWithFrame:frame];
  return self;
}

-(void)handleTimer:(NSTimer *)timer {
  if (img && img->gif) {
    img->gif->cur_frame += 1;
    if (img->gif->cur_frame >= img->gif->total_frames)
      img->gif->cur_frame = 0;
    img->buf = img->gif->frames[img->gif->cur_frame];
    [self setNeedsDisplay:YES];
  }
}

-(void)load_img:(const char*)path {
  img = malloc(sizeof(image_t));
  if (!img) {
    fprintf(stderr, "malloc() failed: out of memory\n");
    [NSApp terminate:nil];
  }
  
  if (endswith(path, ".gif")) {
    gif_data_t gif = {0};
    int uuid = 0;
    if ((uuid = open(path, O_RDONLY | O_BINARY)) <= 0) {
      fprintf(stderr, "open() failed\n");
      [NSApp terminate:nil];
    }
    
    gif.size = (unsigned long)lseek(uuid, 0UL, SEEK_END);
    lseek(uuid, 0UL, SEEK_SET);
    read(uuid, gif.data = realloc(0, gif.size), gif.size);
    close(uuid);
    
    if (uuid > 0) {
      gif.info = malloc(sizeof(gif_info_t));
      if (!GIF_Load(gif.data, (long)gif.size, gif_frame, 0, (void*)&gif, 0L) || !gif.info->frames) {
        fprintf(stderr, "GIF_Load() failed\n");
        [NSApp terminate:nil];
      }
      free(gif.draw);
      img->gif = gif.info;
      img->buf = img->gif->frames[0];
      img->w = img->gif->w;
      img->h = img->gif->h;
    }
  } else {
    img->buf = (void*)stbi_load(path, &img->w, &img->h, &img->c, STBI_rgb_alpha);
    if (!img->buf) {
      fprintf(stderr, "stbi_load() failed: %s (%s)\n", stbi_failure_reason(), path);
      [NSApp terminate:nil];
    }
    img->gif = NULL;
  }
  
  img->path = strdup(path);
}

-(void)free_img {
  if (img) {
    if (img->gif) {
      for (int i = 0; i < img->gif->total_frames; ++i)
        free(img->gif->frames[i]);
      free(img->gif->frames);
      img->gif->frames = NULL;
      free(img->gif);
      img->gif = NULL;
    } else
      free(img->buf);
    free(img->path);
    free(img);
  }
}

-(void)force_resize {
  NSRect frame = [[self window] frame];
  frame.size.width  = img->w;
  frame.size.height = img->h;
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
      
      size_t needed = snprintf(NULL, 0, "%s/%s", self->dir, dir_imgs[img_pos]) + 1;
      char* buffer = malloc(needed);
      snprintf(buffer, needed, "%s/%s", self->dir, dir_imgs[img_pos]);
      
      [self free_img];
      [self load_img:buffer];
      if (!img)
        [[self window] close];
      
      [self force_resize];
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
  
  CGImageRef cgir = CGImageCreate(img->w, img->h, 8, 32, img->w * BPP, s, (img->gif ? kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little : kCGBitmapByteOrderDefault), p, NULL, false, kCGRenderingIntentDefault);
  
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
  
  id window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 0, 0)
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
  id app_view = [[AppView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)
                                         Image:path];
  [window setContentView:app_view];
  [app_view force_resize];
  
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

