# Image Diff

A macOS tool for comparing two images, ported from
[image-diff-windows](https://github.com/tom-seddon/image-diff-windows). It runs on macOS 13 or
later, on Apple Silicon and Intel Macs (universal binaries).

The comparison window, `ImageDiff.app`, is in progress.

## The command line: `imgdiff`

Compares without opening a window, prints the result, and sets the exit code, so it works
in scripts and build steps.

```
$ imgdiff before.png after.png -o diff.png
Left:  before.png (800x600)
Right: after.png (800x600)
1,234 of 480,000 pixels differ (0.26%), max channel difference 87.
Difference image saved to diff.png
```

| Option | Meaning |
| --- | --- |
| `-t`, `--tolerance <0-255>` | Ignore channel differences up to this amount (default 0) |
| `-o`, `--output <file.png>` | Save the highlighted difference image |
| `-s`, `--show` | Also open the comparison in the window |
| `-m`, `--mode <diff\|flip>` | View the window opens in, with `--show` |

Exit codes: `0` identical, `1` different, `2` error.

## How images are compared

Images are aligned at the top-left corner. A pixel differs when any of its blue, green, red
or alpha values differs by more than the tolerance. If the images are different sizes, every
pixel that exists in only one of them counts as different. Colour profiles are ignored so the
stored pixel values are compared. Any format macOS can decode works: PNG, JPEG, HEIC, WebP,
GIF, BMP, TIFF, ICO and others.

The highlighted difference image shows the left image faded to grey, with every changed
pixel in magenta.

## Building

Needs Xcode 15 or later (or the matching command line tools).

```
swift test
swift build -c release --arch arm64 --arch x86_64 --product imgdiff
```

The universal binary ends up in `.build/apple/Products/Release/imgdiff`.
