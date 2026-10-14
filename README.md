# Image Diff

A macOS tool for comparing two images, ported from
[image-diff-windows](https://github.com/tom-seddon/image-diff-windows). It runs on macOS 13 or
later, on Apple Silicon and Intel Macs (universal binaries).

It has a window and a command line, and a comparison can be set up from either.

## Installing

Download `ImageDiff-<version>-macos-universal.zip` from the
[releases page](https://github.com/tom-seddon/image-diff-macos/releases), unzip it, and move
`ImageDiff.app` to Applications. The app isn't notarised, so the first time you open it,
right-click it and choose **Open** (or use **Open Anyway** in System Settings > Privacy &
Security).

`imgdiff` is in the zip and also inside the app. To use it from a terminal, link it onto your
path, for example:

```
ln -s /Applications/ImageDiff.app/Contents/MacOS/imgdiff /usr/local/bin/imgdiff
```

## The window: `ImageDiff.app`

Open it and choose the two images with **Choose…**, type or paste their paths and press
Return, or drag them onto the window or the Dock icon. Or start it with the comparison
already set up:

```
open -a ImageDiff --args "$PWD/before.png" "$PWD/after.png" --mode flip --tolerance 4
imgdiff before.png after.png --show
```

Views (switch with the buttons or the 1 and 2 keys):

- **Difference**: the left image faded to grey, with every changed pixel in magenta.
- **Flip**: one image at a time, at the same zoom and position. Press **Space**, click the
  image, or press **Show right / Show left** to switch instantly between them, with no
  transition, so you can spot differences by eye. Holding Space keeps flipping. A label in
  the corner says which image is showing. Space in Difference view jumps to Flip.

Other controls:

- **Tolerance** ignores per-channel differences up to the chosen amount (0-255).
- **Zoom**: ⌘ + scroll wheel or pinch zooms around the cursor, **Fit** (⌘0), **100%** (⌘1),
  ⌘= and ⌘- zoom in and out.
- **Pan** by dragging with any mouse button. A left click without dragging flips.
- The status bar shows the pixel under the cursor in both images as `#AARRGGBB`.
- **Swap** exchanges left and right; **⌘R** (or F5) reloads both files from disk.
- **Save Difference…** (⌘S) writes the highlighted image as a PNG.
- Dropping two files sets both sides. Dropping one file fills an empty side, or replaces the
  side of the window you drop it on. You can also drop a file straight onto a path box.

| Option | Meaning |
| --- | --- |
| `-m`, `--mode <diff\|flip>` | View to open in (default `diff`) |
| `-t`, `--tolerance <0-255>` | Ignore channel differences up to this amount (default 0) |
| `-o`, `--output <file.png>` | Also save the highlighted difference image |
| `-h`, `--help` | Show help |

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

Needs Xcode 15 or later (or the matching Command Line Tools).

```
swift test
swift run ImageDiff                # build for this Mac and open the window
scripts/build-app.sh               # universal dist/ImageDiff.app and dist/imgdiff
```

To make a release, go to **Actions > Build > Run workflow**, pick the branch (usually `main`)
and enter a version like `1.2.0`. The workflow builds and tests it, tags the commit `v1.2.0`
and publishes a release with the zipped app and command line. Pushing a tag like `v1.2.0`
yourself does the same.
