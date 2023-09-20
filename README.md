# meh

[feh](https://feh.finalrewind.org/) inspired image viewer for Mac. **WIP** -- See [TODO](https://github.com/takeiteasy/meh#todo) section for progress.

<p align="center">
  <img src="https://raw.githubusercontent.com/takeiteasy/meh/master/screenshot.png">
</p>

```
usage: meh [files...] [options]

  Arguments:
    * -s/--sort -- Specify file list sort [default: alphabetic]
      * options: alphabetic, fsize, mtime, ctime, format, random
    * -r/--reverse -- Enable reversed sorting
    * -S/--slideshow -- Enable slideshow mode
    * -d/--slideshow-delay -- Set slideshow delay [.1-60, default delay: 5 seconds]
    * -R/--slideshow-reverse -- Enable slideshow reverse order
    * -A/--disable-animations -- Disable resizing animation for windows [warning: slow]
    * -q/--quit -- Close window when last image reached
    * -h/--help -- Print this message

  Keys:
    * CMD+Q -- Quit applications
    * ESC/Q -- Close window
    * J/Arrow Left/Arrow Down -- Previous image
    * K/Arrow Right/Arrow Up -- Next image
    * O -- Open file dialog
    * S -- Toggle slideshow

  File types:
    * pdf, eps, epi, epsf, epsi, ps, tiff, tif, jpg, jpeg, jpe, gif, png, pict, pct, pic, bmp, bmpf, ico, icns, dng, cr2, crw, fpx, fpix, raf, dcr, ptng, pnt, mac, mrw, nef, orf, exr, psd, qti, qtif, hdr, sgi, srf, targa, tga, cur, xbm
```

## Build

Run ```make``` to build the regular cli version, or to build the app version run ```make app``` or ```make install```. Alternatively, build the xcodeproj with [xcodegen](https://github.com/yonaskolb/XcodeGen).

## TODO

- [ ] Touch controls
- [ ] Archive support
- [ ] Load images from URL

## License
```
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
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
