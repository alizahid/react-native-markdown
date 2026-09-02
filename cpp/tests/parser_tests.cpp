// Golden tests for the shared markdown core.
// Build & run: cpp/tests/run_tests.sh

#include <algorithm>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

#include "../core/AstJson.h"
#include "../core/Parser.h"

namespace {

int g_failures = 0;
int g_total = 0;

void expectAst(const char* name, const std::string& markdown, const std::string& expected) {
  g_total++;
  auto doc = jetmarkdown::parseMarkdown(markdown);
  const std::string actual = jetmarkdown::astToJson(doc->root);
  if (actual != expected) {
    g_failures++;
    std::printf("FAIL %s\n  input:    %s\n  expected: %s\n  actual:   %s\n",
                name, markdown.c_str(), expected.c_str(), actual.c_str());
  }
}

void expectContains(const char* name, const std::string& markdown, const std::string& fragment) {
  g_total++;
  auto doc = jetmarkdown::parseMarkdown(markdown);
  const std::string actual = jetmarkdown::astToJson(doc->root);
  if (actual.find(fragment) == std::string::npos) {
    g_failures++;
    std::printf("FAIL %s\n  input:    %s\n  missing:  %s\n  actual:   %s\n",
                name, markdown.c_str(), fragment.c_str(), actual.c_str());
  }
}

void expectNotContains(const char* name, const std::string& markdown, const std::string& fragment) {
  g_total++;
  auto doc = jetmarkdown::parseMarkdown(markdown);
  const std::string actual = jetmarkdown::astToJson(doc->root);
  if (actual.find(fragment) != std::string::npos) {
    g_failures++;
    std::printf("FAIL %s\n  input:    %s\n  found unexpected: %s\n  actual:   %s\n",
                name, markdown.c_str(), fragment.c_str(), actual.c_str());
  }
}

} // namespace

int main() {
  using namespace std::string_literals;

  // --- Basics ---
  expectAst(
      "paragraph",
      "hello world",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"hello world"}]}]})");

  expectAst(
      "heading",
      "## Title",
      R"({"type":"document","children":[{"type":"heading","level":2,"children":[{"type":"text","text":"Title"}]}]})");

  expectAst(
      "bold italic nesting",
      "**bold _italic_**",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"bold","children":[{"type":"text","text":"bold "},{"type":"italic","children":[{"type":"text","text":"italic"}]}]}]}]})");

  expectAst(
      "link",
      "[label](https://example.com)",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"link","url":"https://example.com","children":[{"type":"text","text":"label"}]}]}]})");

  expectContains(
      "mention link keeps scheme",
      "hey [@ali](users://ali)!",
      R"({"type":"link","url":"users://ali","children":[{"type":"text","text":"@ali"}]})");

  expectContains(
      "autolink",
      "see https://example.com now",
      R"("type":"link","url":"https://example.com")");

  expectAst(
      "image",
      "![alt text](https://example.com/x.png)",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"image","text":"alt text","url":"https://example.com/x.png"}]}]})");

  expectAst(
      "inline code",
      "run `npm i` now",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"run "},{"type":"inlineCode","text":"npm i"},{"type":"text","text":" now"}]}]})");

  expectAst(
      "code block with lang",
      "```js\nlet x = 1;\n```",
      R"({"type":"document","children":[{"type":"codeBlock","text":"let x = 1;\n","url":"js"}]})");

  expectContains("block quote", "> quoted", R"("type":"blockQuote")");

  expectContains(
      "ordered list start",
      "3. three\n4. four",
      R"("type":"list","ordered":true,"start":3)");

  expectContains("thematic break", "a\n\n---\n\nb", R"("type":"thematicBreak")");

  expectContains("hard break", "line one  \nline two", R"("type":"hardBreak")");

  // --- Tables ---
  expectAst(
      "table structure",
      "| a | b |\n|---|--:|\n| 1 | 2 |",
      R"({"type":"document","children":[{"type":"table","children":[{"type":"tableRow","level":1,"children":[{"type":"tableCell","children":[{"type":"text","text":"a"}]},{"type":"tableCell","level":3,"children":[{"type":"text","text":"b"}]}]},{"type":"tableRow","children":[{"type":"tableCell","children":[{"type":"text","text":"1"}]},{"type":"tableCell","level":3,"children":[{"type":"text","text":"2"}]}]}]}]})");

  // --- Spoilers ---
  expectAst(
      "discord spoiler",
      "a ||secret|| b",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"a "},{"type":"spoiler","children":[{"type":"text","text":"secret"}]},{"type":"text","text":" b"}]}]})");

  expectAst(
      "reddit spoiler mid-line",
      "a >!secret!< b",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"a "},{"type":"spoiler","children":[{"type":"text","text":"secret"}]},{"type":"text","text":" b"}]}]})");

  expectAst(
      "reddit spoiler at line start (not blockquote)",
      ">!secret!< after",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"spoiler","children":[{"type":"text","text":"secret"}]},{"type":"text","text":" after"}]}]})");

  expectContains(
      "spoiler inside blockquote",
      "> before >!secret!< after",
      R"({"type":"spoiler","children":[{"type":"text","text":"secret"}]})");

  expectAst(
      "spoiler spanning styled runs",
      "||bold **x** end||",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"spoiler","children":[{"type":"text","text":"bold "},{"type":"bold","children":[{"type":"text","text":"x"}]},{"type":"text","text":" end"}]}]}]})");

  expectNotContains(
      "spoiler not inside fenced code",
      "```\n>!not a spoiler!<\n||also not||\n```",
      R"("type":"spoiler")");

  expectNotContains(
      "spoiler not inside inline code",
      "`||nope||`",
      R"("type":"spoiler")");

  expectNotContains("empty spoiler literal", "||||", R"("type":"spoiler")");

  expectNotContains(
      "unclosed spoiler literal",
      "a ||secret forever",
      R"("type":"spoiler")");

  // --- Strikethrough vs subscript ---
  expectAst(
      "double tilde strikethrough",
      "~~gone~~",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"strikethrough","children":[{"type":"text","text":"gone"}]}]}]})");

  expectAst(
      "single tilde subscript",
      "H~2~O",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"H"},{"type":"subscript","children":[{"type":"text","text":"2"}]},{"type":"text","text":"O"}]}]})");

  expectNotContains(
      "subscript rejects spaces",
      "~not a sub~",
      R"("type":"subscript")");

  expectContains(
      "strikethrough spanning styled runs",
      "~~a **b** c~~",
      R"({"type":"strikethrough","children":[{"type":"text","text":"a "},{"type":"bold","children":[{"type":"text","text":"b"}]},{"type":"text","text":" c"}]})");

  // --- Superscript ---
  expectAst(
      "pandoc superscript",
      "x^2^ y",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"x"},{"type":"superscript","children":[{"type":"text","text":"2"}]},{"type":"text","text":" y"}]}]})");

  expectAst(
      "reddit bare superscript",
      "x^2 y",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"x"},{"type":"superscript","children":[{"type":"text","text":"2"}]},{"type":"text","text":" y"}]}]})");

  expectAst(
      "reddit paren superscript",
      "note^(multi word here) end",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"note"},{"type":"superscript","children":[{"type":"text","text":"multi word here"}]},{"type":"text","text":" end"}]}]})");

  expectAst(
      "bare superscript to end of line",
      "wow^amazing",
      R"({"type":"document","children":[{"type":"paragraph","children":[{"type":"text","text":"wow"},{"type":"superscript","children":[{"type":"text","text":"amazing"}]}]}]})");

  expectNotContains(
      "lone caret literal",
      "a ^ b",
      R"("type":"superscript")");

  // --- Interactions ---
  expectContains(
      "sub inside spoiler",
      "||H~2~O||",
      R"({"type":"spoiler","children":[{"type":"text","text":"H"},{"type":"subscript","children":[{"type":"text","text":"2"}]},{"type":"text","text":"O"}]})");

  expectNotContains(
      "extensions skip link labels",
      "[a ||b|| c](https://example.com)",
      R"("type":"spoiler")");

  expectContains(
      "entity translation",
      "a &amp; b &#65;",
      R"({"type":"text","text":"a & b A"})");

  expectContains(
      "nested list structure",
      "- a\n  - b",
      R"("type":"list")");

  // --- Hostile nesting must parse without blowing the stack (depth cap).
  {
    std::string hostile;
    for (int i = 0; i < 20000; i++) {
      hostile += '>';
    }
    hostile += " x";
    auto doc = jetmarkdown::parseMarkdown(hostile);
    g_total++;
    if (doc->root == nullptr) {
      g_failures++;
      std::printf("FAIL deep nesting parse\n");
    }
  }

  // --- Nested image inside alt text keeps the outer alt intact.
  expectContains(
      "nested image alt",
      "![a ![b](u2) c](u1)",
      R"("text":"a b c")");

  // --- Surrogate-range character references become U+FFFD, not invalid
  // UTF-8.
  expectContains(
      "surrogate entity replaced",
      "bad &#xD800; ref",
      "\xEF\xBF\xBD");

  std::printf("%d/%d passed\n", g_total - g_failures, g_total);
  return g_failures == 0 ? 0 : 1;
}
