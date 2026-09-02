import type { ColorValue, StyleProp } from "react-native";

export type FontVariant =
  | "small-caps"
  | "oldstyle-nums"
  | "lining-nums"
  | "tabular-nums"
  | "proportional-nums"
  | "stylistic-one"
  | "stylistic-two"
  | "stylistic-three"
  | "stylistic-four"
  | "stylistic-five"
  | "stylistic-six"
  | "stylistic-seven"
  | "stylistic-eight"
  | "stylistic-nine"
  | "stylistic-ten"
  | "stylistic-eleven"
  | "stylistic-twelve"
  | "stylistic-thirteen"
  | "stylistic-fourteen"
  | "stylistic-fifteen"
  | "stylistic-sixteen"
  | "stylistic-seventeen"
  | "stylistic-eighteen"
  | "stylistic-nineteen"
  | "stylistic-twenty";

export type FontWeight =
  | "normal"
  | "bold"
  | "100"
  | "200"
  | "300"
  | "400"
  | "500"
  | "600"
  | "700"
  | "800"
  | "900"
  | 100
  | 200
  | 300
  | 400
  | 500
  | 600
  | 700
  | 800
  | 900;

/**
 * Text styling shared by every text-bearing markdown element.
 */
export interface MarkdownTextStyle {
  /** Highlight behind the text run. */
  backgroundColor?: ColorValue;
  color?: ColorValue;
  fontFamily?: string;
  fontSize?: number;
  fontVariant?: FontVariant[];
  fontWeight?: FontWeight;
  /** Total line height in points, like React Native's `lineHeight`. */
  lineHeight?: number;
  textDecorationColor?: ColorValue;
  /**
   * Android renders `underline` and `line-through` natively; decoration
   * color/style on Android are drawn for links and mentions, best-effort
   * elsewhere.
   */
  textDecorationLine?:
    | "none"
    | "underline"
    | "line-through"
    | "underline line-through";
  textDecorationStyle?: "solid" | "double" | "dotted" | "dashed";
}

/**
 * Box styling shared by every block-level markdown element.
 */
export interface MarkdownLayoutStyle {
  backgroundColor?: ColorValue;
  borderBottomColor?: ColorValue;
  borderBottomWidth?: number;
  borderColor?: ColorValue;
  /** iOS only; Android always renders circular corners. */
  borderCurve?: "circular" | "continuous";
  borderLeftColor?: ColorValue;
  borderLeftWidth?: number;
  borderRadius?: number;
  borderRightColor?: ColorValue;
  borderRightWidth?: number;
  borderTopColor?: ColorValue;
  borderTopWidth?: number;
  borderWidth?: number;
  padding?: number;
  paddingBottom?: number;
  paddingHorizontal?: number;
  paddingLeft?: number;
  paddingRight?: number;
  paddingTop?: number;
  paddingVertical?: number;
}

export interface MarkdownImageStyle {
  backgroundColor?: ColorValue;
  borderRadius?: number;
  /** Fixed rendered height; wins over the image's intrinsic height. */
  height?: number;
  maxHeight?: number;
}

export interface MarkdownTableStyle extends MarkdownLayoutStyle {
  /** Upper clamp for computed column widths. Unset = natural width. */
  maxColumnWidth?: number;
  /** Lower clamp for computed column widths. Unset = natural width. */
  minColumnWidth?: number;
}

export interface MarkdownSpoilerStyle {
  backgroundColor?: ColorValue;
  /** iOS only; Android always renders circular corners. */
  borderCurve?: "circular" | "continuous";
  borderRadius?: number;
}

export interface MarkdownDividerStyle {
  color?: ColorValue;
  height?: number;
}

export interface MarkdownListStyle {
  marginLeft?: number;
}

export interface MarkdownListMarkerStyle {
  color?: ColorValue;
  marginLeft?: number;
  width?: number;
}

/**
 * Mention styling. `variants` maps a regular expression (matched against the
 * mention link's URL) to the style for that mention type. Longest pattern
 * first, first match wins:
 *
 * ```ts
 * mention: {
 *   color: 'gray',
 *   variants: {
 *     '^users://': { color: 'blue' },
 *     '^channels://': { color: 'green' },
 *   },
 * }
 * ```
 */
export interface MarkdownMentionStyle extends MarkdownTextStyle {
  /** iOS only; Android always renders circular corners. */
  borderCurve?: "circular" | "continuous";
  /** Rounds the `backgroundColor` chip behind the mention. */
  borderRadius?: number;
  variants?: Record<string, MarkdownTextStyle>;
}

/** Link styling; `backgroundColor` renders as a chip behind the link. */
export interface MarkdownLinkStyle extends MarkdownTextStyle {
  /** iOS only; Android always renders circular corners. */
  borderCurve?: "circular" | "continuous";
  /** Rounds the `backgroundColor` chip behind the link. */
  borderRadius?: number;
}

export interface MarkdownInlineCodeStyle extends MarkdownTextStyle {
  backgroundColor?: ColorValue;
  /** iOS only; Android always renders circular corners. */
  borderCurve?: "circular" | "continuous";
  borderRadius?: number;
  padding?: number;
  paddingHorizontal?: number;
  paddingLeft?: number;
  paddingRight?: number;
}

export type MarkdownTableCellStyle = MarkdownTextStyle &
  Pick<
    MarkdownLayoutStyle,
    | "padding"
    | "paddingHorizontal"
    | "paddingVertical"
    | "paddingLeft"
    | "paddingRight"
    | "paddingTop"
    | "paddingBottom"
  >;

export type MarkdownHeadingLevel = "h1" | "h2" | "h3" | "h4" | "h5" | "h6";

/**
 * Per-element styles for the markdown viewer.
 */
export interface MarkdownStyles {
  blockQuote?: MarkdownTextStyle & MarkdownLayoutStyle;
  bold?: MarkdownTextStyle;
  codeBlock?: MarkdownTextStyle & MarkdownLayoutStyle;
  divider?: MarkdownDividerStyle;
  /** Vertical spacing between blocks. The `style` prop's `gap` wins. */
  gap?: number;
  headings?: Partial<Record<MarkdownHeadingLevel, MarkdownTextStyle>>;
  image?: MarkdownImageStyle;
  inlineCode?: MarkdownInlineCodeStyle;
  italic?: MarkdownTextStyle;
  link?: MarkdownLinkStyle;
  list?: MarkdownListStyle;
  listItem?: MarkdownTextStyle;
  listMarker?: MarkdownListMarkerStyle;
  mention?: MarkdownMentionStyle;
  paragraph?: MarkdownTextStyle;
  spoiler?: MarkdownSpoilerStyle;
  strikethrough?: MarkdownTextStyle;
  subscript?: MarkdownTextStyle;
  superscript?: MarkdownTextStyle;
  table?: MarkdownTableStyle;
  /** Body-row overrides layered on top of `tableRow`. */
  tableBodyRow?: MarkdownLayoutStyle;
  tableCell?: MarkdownTableCellStyle;
  /** Header-cell overrides layered on top of `tableCell`. */
  tableHeaderCell?: MarkdownTableCellStyle;
  /** Header-row overrides layered on top of `tableRow`. */
  tableHeaderRow?: MarkdownLayoutStyle;
  /** Base style for every row; header/body variants layer on top. */
  tableRow?: MarkdownLayoutStyle;
}

/**
 * Pre-sizing data for images referenced in the markdown. Images whose URL is
 * listed here lay out at their final size immediately (zero layout shift);
 * unknown images show a full-width, 200pt-tall placeholder and resize once
 * loaded.
 */
export interface MarkdownImageData {
  height: number;
  url: string;
  width: number;
}

export interface MarkdownUrlEvent {
  url: string;
}

export interface MarkdownImageEvent {
  /** Height of the rendered image, in dp. */
  height: number;
  url: string;
  /** Width of the rendered image, in dp. */
  width: number;
  /** Horizontal position of the rendered image relative to the screen, in dp. */
  x: number;
  /** Vertical position of the rendered image relative to the screen, in dp. */
  y: number;
}

/**
 * The main container style: background, padding, and the gap between
 * blocks, plus base text styles that cascade into every text element
 * (paragraphs, headings, lists, tables, quotes) unless overridden
 * per-element via the `styles` prop. Element builtins survive the cascade:
 * heading sizes/weight and the code block's monospace font stay unless
 * their own section overrides them.
 *
 * For outer layout (margin, width, flex), wrap the component in a View.
 */
export interface MarkdownContainerStyle extends MarkdownTextStyle {
  backgroundColor?: ColorValue;
  /** Vertical spacing between blocks; overrides `styles.gap`. */
  gap?: number;
  maxHeight?: number;
  padding?: number;
  paddingBottom?: number;
  paddingHorizontal?: number;
  paddingLeft?: number;
  paddingRight?: number;
  paddingTop?: number;
  paddingVertical?: number;
}

export interface JetMarkdownViewProps {
  /** Scale text with the system font size setting. Defaults to true. */
  allowFontScaling?: boolean;
  images?: MarkdownImageData[];
  /** The markdown source to render. */
  markdown: string;
  onImagePress?: (event: MarkdownImageEvent) => void;
  onLinkLongPress?: (event: MarkdownUrlEvent) => void;
  onLinkPress?: (event: MarkdownUrlEvent) => void;
  /**
   * Main container style: `backgroundColor`, `padding*`, `gap`, and base
   * text styles that cascade into every text element unless overridden via
   * `styles`. All keys are measured natively.
   */
  style?: StyleProp<MarkdownContainerStyle>;
  /** Per-element markdown styles. Hoist to module scope or memoize. */
  styles?: MarkdownStyles;
}
