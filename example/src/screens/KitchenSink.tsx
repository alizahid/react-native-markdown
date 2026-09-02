import { Alert, ScrollView, StyleSheet } from "react-native";
import {
  JetMarkdownView,
  type MarkdownContainerStyle,
  type MarkdownStyles,
  mergeStyles,
} from "react-native-jet-markdown";

const MARKDOWN = `# Jet Markdown

Paragraph with **bold**, _italic_, ~~strikethrough~~, and **bold _italic_ nested** runs.

## Links & mentions

Visit [the docs](https://example.com/docs) or ping [@ali](users://ali) in [#general](channels://general).

Reviewers: [@sam](users://sam) and [@kim](users://kim) — updates land in [#releases](channels://releases), chatter in [#random](channels://random).

### Code & science

Inline \`const x = 42\` code. Water is H~2~O, area is x^2^ and reddit^style sup with ^(multi word groups) too.

#### Spoilers (styling lands in M6)

Both ||discord style|| and >!reddit style!< parse already.

---

## Blocks

> A block quote with **bold** and a nested paragraph.
>
> Second paragraph inside the quote.

- unordered item one with enough text to wrap onto a second line eventually
- item two with \`inline code\`
  - nested child item
  - another nested child
- item three

1. ordered one
2. ordered two
3. ordered three

\`\`\`ts
function reallyLongFunctionName(parameter: string, another: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 1000));
}
\`\`\`

## Images

Pre-sized (zero layout shift):

![pre-sized](https://picsum.photos/id/1015/600/400)

Unknown size (placeholder then resize):

![unknown](https://picsum.photos/id/1025/500/300)

Broken URL (placeholder stays):

![broken](https://example.invalid/nope.png)

Giphy

![](https://media.giphy.com/media/c26ZBTyZaHhhgKyEyD/giphy.gif)

## Tables

Narrow (stretches to fill):

| Name | Role |
|------|------|
| Ali | Author |
| Kit | Reviewer |

Wide (scrolls horizontally):

| ID | Package name | Version | Downloads | License | Maintainer | Last publish | Notes |
|----|--------------|---------|-----------|---------|------------|--------------|-------|
| 1 | [react-native-jet-markdown](https://alizahid.dev) | 0.1.0 | 120,394 | MIT | *@ali* | 2 days ago | A really long descriptive note that pads this cell |
| 2 | react-native-enriched | 1.0.0 | 88,120 | MIT | **swmansion** | 1 week ago | Another very descriptive note about the package |`;

const styles: MarkdownStyles = mergeStyles({
  headings: {
    h1: { color: "#111827" },
    h2: { color: "#1D4ED8" },
    h3: { color: "#047857", fontWeight: "600" },
  },
  paragraph: { fontSize: 16, color: "#1F2937" },
  bold: { color: "#B91C1C" },
  italic: { color: "#7C3AED" },
  strikethrough: { color: "#9CA3AF" },
  link: {
    color: "#2563EB",
    textDecorationLine: "underline",
    backgroundColor: "#DBEAFE",
    borderRadius: 4,
    borderCurve: "continuous",
  },
  mention: {
    fontWeight: "600",
    backgroundColor: "#FCE7F3",
    borderRadius: 4,
    borderCurve: "continuous",
    variants: {
      "^users://": { color: "#DB2777" },
      "^channels://": { color: "#059669", backgroundColor: "#D1FAE5" },
    },
  },
  inlineCode: {
    fontFamily: "Courier",
    color: "#BE185D",
    backgroundColor: "#FDF2F8",
    borderRadius: 4,
    paddingHorizontal: 4,
  },
  tableHeaderRow: { backgroundColor: "#EEF2FF" },
  tableBodyRow: { backgroundColor: "#FAFAFA" },
  tableHeaderCell: { color: "#3730A3", paddingVertical: 10 },
  superscript: { color: "#EA580C" },
  subscript: { color: "#0284C7" },
  image: { borderRadius: 12, backgroundColor: "#E5E7EB", maxHeight: 260 },
});

const images = [
  { url: "https://picsum.photos/id/1015/600/400", width: 300, height: 200 },
];

export function KitchenSink() {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={sheet.container}
    >
      <JetMarkdownView
        images={images}
        markdown={MARKDOWN}
        onImagePress={({ url, x, y, width, height }) =>
          Alert.alert(
            "onImagePress",
            `${url}\n${width.toFixed(0)}x${height.toFixed(0)} @ (${x.toFixed(0)}, ${y.toFixed(0)})`
          )
        }
        onLinkLongPress={({ url }) => Alert.alert("onLinkLongPress", url)}
        onLinkPress={({ url }) => Alert.alert("onLinkPress", url)}
        style={markdownStyle}
        styles={styles}
      />
    </ScrollView>
  );
}

const markdownStyle: MarkdownContainerStyle = {
  padding: 16,
  gap: 12,
  fontFamily: "Satoshi",
  lineHeight: 24,
};

const sheet = StyleSheet.create({
  container: {
    flex: 1,
  },
});
