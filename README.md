<p align="center">
  <img alt="react-native-jet-markdown — native markdown viewer for React Native" src="https://raw.githubusercontent.com/alizahid/react-native-jet-markdown/main/docs/hero.svg" width="900">
</p>

<p align="center">
  Fast, fully native Markdown viewer for React Native
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/react-native-jet-markdown"><img src="https://img.shields.io/npm/v/react-native-jet-markdown?color=A02F6F&label=npm" alt="npm"></a>
  <a href="https://github.com/alizahid/react-native-jet-markdown/blob/main/LICENSE"><img src="https://img.shields.io/npm/l/react-native-jet-markdown?color=668C0B" alt="license"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-5E409D" alt="platform">
  <img src="https://img.shields.io/badge/architecture-Fabric-205EA6" alt="architecture">
</p>

---

- **One native Fabric view** — markdown is parsed natively with [md4c](https://github.com/mity/md4c) and rendered as attributed text (TextKit on iOS, StaticLayout/Spannable on Android). No WebView, no JS-side layout, no nested `<Text>` trees.
- **Self-sizing** — the component measures its own height on the Fabric layout thread with a custom C++ shadow node, so it behaves like `<Text>` in any layout, list, or scroll view.
- **Built for lists** — parse and layout results are cached and shared between measurement and mounting; views recycle cleanly in FlatList / FlashList / LegendList.
- **Deeply styleable** — a typed, per-element styles API with cascading text styles, box styles, and regex-based mention variants.

## Supported markdown

Headings, paragraphs, images, GFM tables (horizontal scroll with intelligently sized columns), spoilers (Reddit `>!text!<` **and** Discord `||text||`), superscript (`^sup^`, Reddit `^word` and `^(multi word)`), subscript (`~sub~`), bold / italic / strikethrough, ordered + unordered lists (nested), links, mentions, inline code, code blocks (horizontally scrolling, monospace), block quotes, and thematic breaks.

## Installation

```sh
npm install react-native-jet-markdown
cd ios && pod install
```

Requires React Native 0.86+ with the New Architecture (Fabric).

> **Android support is experimental.** The Android renderer implements the same feature set as iOS, but it has had far less real-world use. Expect rough edges and please [report](https://github.com/alizahid/react-native-jet-markdown/issues) anything that renders differently from iOS.

## Usage

```tsx
import {
  JetMarkdownView,
  mergeStyles,
  type MarkdownStyles,
} from 'react-native-jet-markdown';

// Default look + overrides. Or pass `defaultStyles` as-is, or your own
// object from scratch — with no `styles` prop the viewer renders fully
// plain text.
const styles: MarkdownStyles = mergeStyles({
  paragraph: { fontSize: 16, color: '#1F2937' },
  link: { color: '#2563EB', textDecorationLine: 'underline' },
  mention: {
    fontWeight: '600',
    variants: {
      '^users://': { color: '#DB2777' },
      '^channels://': { color: '#059669' },
    },
  },
  spoiler: { backgroundColor: '#374151', borderRadius: 4 },
});

<JetMarkdownView
  markdown={'Hello **world**, ping [@ali](users://ali)!'}
  styles={styles}
  style={{ padding: 16, gap: 12 }}
  onLinkPress={({ url }) => Linking.openURL(url)}
/>;
```

## Props

| Prop | Type | Description |
| --- | --- | --- |
| `markdown` | `string` | The markdown source. |
| `style` | `MarkdownContainerStyle` | Container box (`backgroundColor`, `padding*`, `gap`) plus base text styles that cascade into every element. See [Container style](#container-style). |
| `styles` | `MarkdownStyles` | Per-element styles. See [Styling](#styling). Hoist to module scope or memoize. |
| `images` | `{ url, width, height }[]` | Pre-sizing data. Listed images lay out at their final size immediately (zero layout shift); unlisted ones render a full-width, 200pt-tall placeholder and snap to their real aspect once loaded. |
| `allowFontScaling` | `boolean` | Scale all text, including `lineHeight`, with the system font size setting. Default `true`. |
| `onLinkPress` | `({ url }) => void` | Link or mention tapped. Mentions arrive with their scheme (e.g. `users://ali`). |
| `onLinkLongPress` | `({ url }) => void` | Link long-pressed. |
| `onImagePress` | `({ url, x, y, width, height }) => void` | Image tapped. `width`/`height` are the rendered size and `x`/`y` the position relative to the screen (dp) — everything a lightbox needs for a zoom-from-thumbnail transition. |

## Styling

The viewer ships **unstyled by default**: with no `styles` prop the output is plain text (only bold/italic runs, monospace code, list markers, and the spoiler cover survive). Two exports cover the common cases:

- `defaultStyles` — a plain `MarkdownStyles` object with the classic markdown look (heading scale, blue links, code boxes, quote bar, table separators). It's just data: spread it, fork it, or use it as a reference.
- `mergeStyles(overrides)` — deep-merges your overrides into `defaultStyles` (element sections merge key-by-key, heading levels individually).

### Container style

The `style` prop styles the container itself: `backgroundColor`, `padding` (+ `paddingHorizontal`/`paddingVertical` and per-side), and `gap` (spacing between blocks; wins over `styles.gap`). Text keys on it (`fontSize`, `fontWeight`, `fontFamily`, `color`, `lineHeight`, `fontVariant`, `textDecoration*`) are the base of the cascade: every element inherits them unless its own section overrides. Element builtins survive the cascade — heading sizes and weights stay unless `headings.hN` overrides, and code keeps its monospace font unless `codeBlock` overrides.

All of these are measured natively. For outer layout (margin, width, flex), wrap the viewer in a `View`.

### Element styles

Two shared shapes compose every element style:

**Text** — `fontSize`, `fontWeight`, `fontFamily`, `color`, `backgroundColor` (run highlight), `fontVariant`, `lineHeight`, `textDecorationColor`, `textDecorationLine`, `textDecorationStyle`

**Layout** — `backgroundColor`, `padding` (+ `paddingHorizontal`/`paddingVertical` and per-side), `borderRadius`, `borderCurve` (iOS), `borderColor`/`borderWidth` (+ per-side)

Every color accepts platform colors (`PlatformColor`, `DynamicColorIOS`) as well as static values — on iOS they stay dynamic and adapt to light/dark automatically; on Android they resolve against the current theme.

| Key | Accepts | Notes |
| --- | --- | --- |
| `headings.h1`–`h6` | text | Do **not** inherit `paragraph`, and ignore the base `lineHeight` (a body line height would clip taller headings) — set `headings.hN.lineHeight` explicitly if needed. `defaultStyles`: 32/26/22/18/16/14, bold. |
| `paragraph` | text | Base for body text; inline styles cascade on top. |
| `bold`, `italic`, `strikethrough` | text | |
| `link` | text + `borderRadius`, `borderCurve` (iOS) | `backgroundColor` draws as a rounded chip behind the run. `defaultStyles`: system blue. |
| `mention` | text + `borderRadius`, `borderCurve` (iOS) + `variants` | `backgroundColor` draws as a rounded chip. `variants` maps a regex (tested against the link URL, longest pattern first) to a style. A link matching any variant is a mention. |
| `inlineCode` | text + `backgroundColor`, `borderRadius`, `borderCurve` (iOS), `padding(Horizontal/Left/Right)` | Always monospace; the background draws as a rounded chip. `defaultStyles`: 8% black background. |
| `superscript`, `subscript` | text | Default: 0.7x size with baseline shift. |
| `spoiler` | `backgroundColor`, `borderRadius`, `borderCurve` | The tap-to-reveal cover — one contiguous polygon even across line wraps. Unstyled: plain black. |
| `codeBlock` | text + layout | Always monospace; long lines scroll horizontally. `defaultStyles`: 14pt, 8% black, radius 6, padding 12. |
| `blockQuote` | text + layout | Text styles cascade into quoted content. `defaultStyles`: 3pt left border, 12pt left padding. |
| `list` | `marginLeft` | |
| `listMarker` | `width`, `marginLeft`, `color` | Fixed-width marker column. Unstyled: sized to the widest marker. `defaultStyles`: 24. |
| `listItem` | text | Cascades into item content. |
| `image` | `borderRadius`, `backgroundColor`, `height`, `maxHeight` | `backgroundColor` shows while loading. |
| `table` | layout + `minColumnWidth`, `maxColumnWidth` | Unstyled: natural column widths. `defaultStyles`: clamps to `[44, 320]`. |
| `tableRow` | layout | Base for all rows. `defaultStyles`: 1pt bottom-border separator. |
| `tableHeaderRow`, `tableBodyRow` | layout | Layer over `tableRow` for header vs body rows. |
| `tableCell` | text + `padding*` | Header cells are always bold. `defaultStyles`: padding 8. |
| `tableHeaderCell` | text + `padding*` | Layers over `tableCell` for header cells. |
| `divider` | `color`, `height` | Thematic break (`---`). Unstyled: 1pt black. `defaultStyles`: subtle hairline. |
| `gap` | number | Vertical spacing between blocks. The `style` prop's `gap` wins when both are set. Unstyled: 0. `defaultStyles`: 12. |

### Tables

Each column gets its natural (unwrapped) width, clamped to `[minColumnWidth, maxColumnWidth]`. If the table fits the container, the surplus is distributed proportionally so it fills the line; if not, columns keep their readable widths and the table scrolls horizontally.

### Mentions

Mentions are plain markdown links with custom schemes — `[@ali](users://ali)`, `[#general](channels://general)` — classified by the `mention.variants` regexes and styled accordingly. Presses arrive through `onLinkPress`; branch on the URL scheme.

### Images

A paragraph containing only an image renders as a block image, aspect-fit to the container width. Pass `images` to pre-size known images and avoid layout shift. Loading runs on SDWebImage (iOS) and Glide (Android) — the same cores expo-image uses — with memory + disk caches, request dedupe, and animated GIF playback (plus APNG on iOS).

## Using in lists

Rendering hundreds of viewers in FlatList / FlashList / LegendList is a first-class use case:

- Hoist `styles` (and `images` when static) to module scope — every item then shares one parsed native style config.
- Parse + layout are cached natively and computed on the Fabric layout thread, so scrolling never parses markdown on the main thread.
- Views reset correctly when recycled; rebinding a view cancels its previous image request, and caches make re-scroll loads instant.
- Wrapping items in `Pressable` works: taps on links, mentions, and spoilers are claimed by the markdown view; taps on plain text reach your `Pressable`.

```tsx
const renderItem = ({ item }) => (
  <Pressable onPress={() => openPost(item)}>
    <JetMarkdownView markdown={item.body} styles={styles} onLinkPress={openLink} />
  </Pressable>
);
```

## Performance

Numbers from the shared C++ core (Apple M-series, `-O2`; the same code runs on device — expect a few multiples slower on mid-range phones, still far below frame budget):

| Operation | Input | Time |
| --- | --- | --- |
| Parse a typical feed post | 1.5 KB mixed markdown | **35 µs** |
| Parse a large document | 160 KB | **4.1 ms** |
| Serialize the full `defaultStyles` object in JS | 980 B JSON | **3 µs**, memoized |

Beyond raw parsing: measurement runs on the Fabric layout thread (never on main), and parse + layout results are cached and shared between measure and mount. The 500-item Feed screen in the example app scrolls at 60 fps on both platforms.

### Why styles cross as JSON

You may notice styles ship natively as one `stylesJson` string instead of a structured object. This is deliberate, not legacy: Fabric props cross via JSI either way (there is no old-bridge serialization in either design), codegen cannot express the open-keyed `mention.variants` map, and the string doubles as the cache key shared by the C++ measurer, iOS, and Android — a structured prop would need deep equality or native re-serialization to get the same caching. The cost is ~3 µs once per distinct styles object.

## Platform notes & limitations

- New Architecture (Fabric) only; React Native 0.86+.
- Android support is experimental; iOS is the reference implementation.
- `textDecorationStyle`/`textDecorationColor` render fully on iOS; Android draws plain underline/strikethrough.
- `borderCurve: 'continuous'` is iOS-only.
- `fontVariant` supports `tabular-nums`, `proportional-nums`, `oldstyle-nums`, `lining-nums`, `small-caps` (font support required).
- Spoilers and inline formatting inside link labels stay literal; spoilers inside table cells are unsupported (the `|` delimiter conflicts).
- Code blocks render plain monospace (no syntax highlighting).
- The viewer fills the width it is given and sizes its own height. Under an unconstrained width (a horizontal `ScrollView`, `alignSelf: 'flex-start'`) it has nothing to wrap against and renders empty — give it a definite width.

## Sponsors

<p align="center">
  <a href="https://acorn.blue"><img alt="Acorn" src="https://acorn.blue/images/acorn.png" width="96"></a>
</p>

<p align="center">
  Built for and sponsored by <a href="https://acorn.blue">Acorn</a>, a Reddit client for iOS.
</p>

## License

MIT
