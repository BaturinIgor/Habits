# Pets (design sources)

Vector pets in the approved "soft volume" style. Everything is drawn in code (SVG from JS), so it ports to SwiftUI shapes; no image assets are needed.

- `pets.js` — renderer `pet(kind, stage, emotion)` for all 11 pets (cat, dog, chick, bunny, turtle, fox, panda, owl, dragon, unicorn, phoenix).
  Stages: 0 baby, 1 teen, 2 adult (collar), 3 legend (crown). Emotions: 0 happy, 1 sad, 2 sleep, 3 just checked a habit.
- `sheet.html#dog,fox` — stages sheet; `emo.html#cat,dog` — emotions sheet (adult).
- `cat-stages.html`, `cat-animation.html` — approved cat and its animation (breathe, blink, tail, jump on check-off, sleep z).
- `shot.js` — render a sheet to PNG with Playwright: `node shot.js dog,fox 2 out.png` (`PAGE=emo.html` for emotions).
- `preview/` — rendered sheets and the cat animation video.

Animation rules for the app: animate only while on screen, use `drawingGroup`, respect Reduce Motion and Low Power Mode, keep it minimal in the widget and on Watch.
