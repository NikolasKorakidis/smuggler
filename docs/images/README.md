# Images

Web-sized JPGs used by the main README (about 1600 px wide, under 700 KB each).

Original full-size PNGs go in `source/`. That folder is not committed, which keeps the repo small. Convert new images with:

```bash
sips -s format jpeg -s formatOptions 80 -Z 1600 source/<file>.png --out <name>.jpg
```

The current images are AI concept art, not in-game screenshots. Swap in real screenshots as the game catches up.
