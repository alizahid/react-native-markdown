#include "Parser.h"

#include <cstdlib>

#include "../md4c/md4c.h"
#include "InlineExtensions.h"
#include "Preprocess.h"

namespace jetmarkdown {

namespace {

void appendUtf8(std::string& out, uint32_t cp) {
  // Surrogates are not scalar values; encoding them yields invalid UTF-8
  // that desynchronizes the UTF-16 offset tables downstream.
  if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
    cp = 0xFFFD;
  }
  if (cp < 0x80) {
    out.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

// Translates one markdown entity ("&amp;", "&#65;", "&#x41;") to UTF-8.
// Unknown named entities are appended literally.
void appendEntity(std::string& out, const char* s, size_t n) {
  if (n < 3 || s[0] != '&' || s[n - 1] != ';') {
    out.append(s, n);
    return;
  }
  if (s[1] == '#') {
    uint32_t cp = 0;
    bool hex = (n > 3 && (s[2] == 'x' || s[2] == 'X'));
    size_t i = hex ? 3 : 2;
    if (i >= n - 1) {
      out.append(s, n);
      return;
    }
    for (; i < n - 1; i++) {
      char c = s[i];
      uint32_t digit;
      if (c >= '0' && c <= '9') {
        digit = c - '0';
      } else if (hex && c >= 'a' && c <= 'f') {
        digit = 10 + (c - 'a');
      } else if (hex && c >= 'A' && c <= 'F') {
        digit = 10 + (c - 'A');
      } else {
        out.append(s, n);
        return;
      }
      cp = cp * (hex ? 16 : 10) + digit;
      if (cp > 0x10FFFF) {
        cp = 0xFFFD;
      }
    }
    appendUtf8(out, cp);
    return;
  }
  const std::string name(s + 1, n - 2);
  struct Named {
    const char* name;
    const char* utf8;
  };
  static const Named kNamed[] = {
      {"amp", "&"},      {"lt", "<"},       {"gt", ">"},
      {"quot", "\""},    {"apos", "'"},     {"nbsp", " "},
      {"copy", "©"},{"reg", "®"}, {"trade", "™"},
      {"hellip", "…"}, {"mdash", "—"}, {"ndash", "–"},
      {"lsquo", "‘"}, {"rsquo", "’"}, {"ldquo", "“"},
      {"rdquo", "”"}, {"deg", "°"},
  };
  for (const auto& e : kNamed) {
    if (name == e.name) {
      out.append(e.utf8);
      return;
    }
  }
  out.append(s, n);
}

std::string attributeToString(const MD_ATTRIBUTE& attr) {
  std::string out;
  if (attr.text == nullptr || attr.size == 0) {
    return out;
  }
  for (int i = 0; attr.substr_offsets[i] < attr.size; i++) {
    MD_OFFSET off = attr.substr_offsets[i];
    MD_OFFSET end = attr.substr_offsets[i + 1];
    const char* sub = attr.text + off;
    size_t len = end - off;
    switch (attr.substr_types[i]) {
      case MD_TEXT_ENTITY:
        appendEntity(out, sub, len);
        break;
      case MD_TEXT_NULLCHAR:
        out.append("�");
        break;
      default:
        out.append(sub, len);
        break;
    }
  }
  return out;
}

// Nesting cap: malicious documents (">"×20000) otherwise build ASTs deep
// enough to overflow the stack in every recursive consumer. Content beyond
// the cap flattens into the deepest allowed node.
constexpr size_t kMaxNestingDepth = 64;

struct ParseState {
  MarkdownDocument* doc = nullptr;
  std::vector<Node*> stack;
  // Enter callbacks swallowed by the depth cap; the matching leave
  // callbacks must not pop real nodes.
  int overflowDepth = 0;
  // Inside an image span all inline callbacks accumulate into the alt text.
  Node* imageNode = nullptr;
  int imageSpanDepth = 0;
  bool inHeaderRow = false;

  Node* top() {
    return stack.back();
  }

  bool atDepthCap() const {
    return stack.size() >= kMaxNestingDepth;
  }

  Node* push(NodeType type) {
    Node* node = doc->arena.alloc(type);
    if (!stack.empty()) {
      stack.back()->children.push_back(node);
    }
    stack.push_back(node);
    return node;
  }

  void pop() {
    stack.pop_back();
  }

  void appendText(const char* s, size_t n) {
    Node* parent = top();
    if (parent->type == NodeType::CodeBlock || parent->type == NodeType::InlineCode) {
      parent->text.append(s, n);
      return;
    }
    if (!parent->children.empty() &&
        parent->children.back()->type == NodeType::Text &&
        !parent->children.back()->verbatim) {
      parent->children.back()->text.append(s, n);
      return;
    }
    Node* text = doc->arena.alloc(NodeType::Text);
    text->text.assign(s, n);
    parent->children.push_back(text);
  }

  // Entity-derived text: the characters were explicitly de-fanged by the
  // author, so the node is tagged verbatim and kept unmerged — the
  // inline-extension scanner skips it.
  void appendVerbatimText(const std::string& s) {
    Node* parent = top();
    if (parent->type == NodeType::CodeBlock || parent->type == NodeType::InlineCode) {
      parent->text.append(s);
      return;
    }
    Node* text = doc->arena.alloc(NodeType::Text);
    text->text = s;
    text->verbatim = true;
    parent->children.push_back(text);
  }
};

int onEnterBlock(MD_BLOCKTYPE type, void* detail, void* userdata) {
  auto* state = static_cast<ParseState*>(userdata);
  // Depth cap: swallow pushes beyond the limit (THEAD/TBODY/HR/HTML never
  // push, and their leaves never pop, so they bypass the accounting).
  if (type != MD_BLOCK_THEAD && type != MD_BLOCK_TBODY &&
      type != MD_BLOCK_HR && type != MD_BLOCK_HTML && state->atDepthCap()) {
    state->overflowDepth++;
    return 0;
  }
  switch (type) {
    case MD_BLOCK_DOC:
      state->doc->root = state->push(NodeType::Document);
      break;
    case MD_BLOCK_QUOTE:
      state->push(NodeType::BlockQuote);
      break;
    case MD_BLOCK_UL: {
      Node* node = state->push(NodeType::List);
      node->ordered = false;
      break;
    }
    case MD_BLOCK_OL: {
      auto* d = static_cast<MD_BLOCK_OL_DETAIL*>(detail);
      Node* node = state->push(NodeType::List);
      node->ordered = true;
      node->startIndex = static_cast<int32_t>(d->start);
      break;
    }
    case MD_BLOCK_LI:
      state->push(NodeType::ListItem);
      break;
    case MD_BLOCK_HR:
      state->push(NodeType::ThematicBreak);
      state->pop();
      break;
    case MD_BLOCK_H: {
      auto* d = static_cast<MD_BLOCK_H_DETAIL*>(detail);
      Node* node = state->push(NodeType::Heading);
      node->level = static_cast<uint8_t>(d->level);
      break;
    }
    case MD_BLOCK_CODE: {
      auto* d = static_cast<MD_BLOCK_CODE_DETAIL*>(detail);
      Node* node = state->push(NodeType::CodeBlock);
      node->url = attributeToString(d->lang);
      break;
    }
    case MD_BLOCK_P:
      state->push(NodeType::Paragraph);
      break;
    case MD_BLOCK_TABLE:
      state->push(NodeType::Table);
      break;
    case MD_BLOCK_THEAD:
      state->inHeaderRow = true;
      break;
    case MD_BLOCK_TBODY:
      state->inHeaderRow = false;
      break;
    case MD_BLOCK_TR: {
      Node* node = state->push(NodeType::TableRow);
      node->level = state->inHeaderRow ? 1 : 0;
      break;
    }
    case MD_BLOCK_TH:
    case MD_BLOCK_TD: {
      auto* d = static_cast<MD_BLOCK_TD_DETAIL*>(detail);
      Node* node = state->push(NodeType::TableCell);
      switch (d->align) {
        case MD_ALIGN_LEFT:
          node->level = static_cast<uint8_t>(CellAlign::Left);
          break;
        case MD_ALIGN_CENTER:
          node->level = static_cast<uint8_t>(CellAlign::Center);
          break;
        case MD_ALIGN_RIGHT:
          node->level = static_cast<uint8_t>(CellAlign::Right);
          break;
        default:
          node->level = static_cast<uint8_t>(CellAlign::Default);
          break;
      }
      break;
    }
    case MD_BLOCK_HTML:
      // MD_FLAG_NOHTML is set; not reached.
      break;
  }
  return 0;
}

int onLeaveBlock(MD_BLOCKTYPE type, void* detail, void* userdata) {
  (void)detail;
  auto* state = static_cast<ParseState*>(userdata);
  switch (type) {
    case MD_BLOCK_THEAD:
    case MD_BLOCK_TBODY:
    case MD_BLOCK_HR:
    case MD_BLOCK_HTML:
      break;
    default:
      if (state->overflowDepth > 0) {
        state->overflowDepth--;
      } else {
        state->pop();
      }
      break;
  }
  return 0;
}

int onEnterSpan(MD_SPANTYPE type, void* detail, void* userdata) {
  auto* state = static_cast<ParseState*>(userdata);
  if (state->imageNode != nullptr) {
    // Styled spans inside image alt text are flattened.
    state->imageSpanDepth++;
    return 0;
  }
  if (state->atDepthCap()) {
    state->overflowDepth++;
    return 0;
  }
  switch (type) {
    case MD_SPAN_EM:
      state->push(NodeType::Italic);
      break;
    case MD_SPAN_STRONG:
      state->push(NodeType::Bold);
      break;
    case MD_SPAN_A: {
      auto* d = static_cast<MD_SPAN_A_DETAIL*>(detail);
      Node* node = state->push(NodeType::Link);
      node->url = attributeToString(d->href);
      // md4c (patched) lets Reddit-style spaces through in destinations;
      // encode them so the URL is openable as-is.
      for (size_t i = 0; (i = node->url.find(' ', i)) != std::string::npos; i += 3) {
        node->url.replace(i, 1, "%20");
      }
      break;
    }
    case MD_SPAN_IMG: {
      auto* d = static_cast<MD_SPAN_IMG_DETAIL*>(detail);
      Node* node = state->doc->arena.alloc(NodeType::Image);
      node->url = attributeToString(d->src);
      state->top()->children.push_back(node);
      state->imageNode = node;
      break;
    }
    case MD_SPAN_CODE:
      state->push(NodeType::InlineCode);
      break;
    case MD_SPAN_DEL:
      // MD_FLAG_STRIKETHROUGH is off; "~~" is handled by InlineExtensions.
      state->push(NodeType::Strikethrough);
      break;
    default:
      // Unsupported span types (latex, wikilink, underline) are not enabled.
      state->push(NodeType::Paragraph);
      break;
  }
  return 0;
}

int onLeaveSpan(MD_SPANTYPE type, void* detail, void* userdata) {
  (void)detail;
  auto* state = static_cast<ParseState*>(userdata);
  if (state->imageNode != nullptr) {
    if (state->imageSpanDepth > 0) {
      // Spans nested inside alt text unwind here — including nested images,
      // whose leave must not clear the OUTER image's accumulation.
      state->imageSpanDepth--;
      return 0;
    }
    if (type == MD_SPAN_IMG) {
      state->imageNode = nullptr;
      return 0;
    }
  }
  if (state->overflowDepth > 0) {
    state->overflowDepth--;
    return 0;
  }
  state->pop();
  return 0;
}

int onText(MD_TEXTTYPE type, const MD_CHAR* text, MD_SIZE size, void* userdata) {
  auto* state = static_cast<ParseState*>(userdata);

  if (state->imageNode != nullptr) {
    switch (type) {
      case MD_TEXT_ENTITY:
        appendEntity(state->imageNode->text, text, size);
        break;
      case MD_TEXT_NULLCHAR:
        state->imageNode->text.append("�");
        break;
      case MD_TEXT_BR:
      case MD_TEXT_SOFTBR:
        state->imageNode->text.push_back(' ');
        break;
      default:
        state->imageNode->text.append(text, size);
        break;
    }
    return 0;
  }

  switch (type) {
    case MD_TEXT_NORMAL:
    case MD_TEXT_CODE:
    case MD_TEXT_HTML:
      state->appendText(text, size);
      break;
    case MD_TEXT_ENTITY: {
      std::string translated;
      appendEntity(translated, text, size);
      state->appendVerbatimText(translated);
      break;
    }
    case MD_TEXT_NULLCHAR: {
      static const char* kReplacement = "�";
      state->appendText(kReplacement, 3);
      break;
    }
    case MD_TEXT_BR: {
      Node* parent = state->top();
      if (parent->type == NodeType::CodeBlock) {
        parent->text.push_back('\n');
      } else {
        parent->children.push_back(state->doc->arena.alloc(NodeType::HardBreak));
      }
      break;
    }
    case MD_TEXT_SOFTBR: {
      Node* parent = state->top();
      if (parent->type == NodeType::CodeBlock) {
        parent->text.push_back('\n');
      } else {
        parent->children.push_back(state->doc->arena.alloc(NodeType::SoftBreak));
      }
      break;
    }
    case MD_TEXT_LATEXMATH:
      state->appendText(text, size);
      break;
  }
  return 0;
}

} // namespace

std::unique_ptr<MarkdownDocument> parseMarkdown(const std::string& markdown) {
  auto doc = std::make_unique<MarkdownDocument>();

  const std::string preprocessed = preprocessMarkdown(markdown);

  ParseState state;
  state.doc = doc.get();

  MD_PARSER parser = {};
  parser.abi_version = 0;
  parser.flags = MD_FLAG_TABLES | MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_NOHTML |
      MD_FLAG_PERMISSIVEATXHEADERS; // Reddit accepts "###Heading"
  parser.enter_block = onEnterBlock;
  parser.leave_block = onLeaveBlock;
  parser.enter_span = onEnterSpan;
  parser.leave_span = onLeaveSpan;
  parser.text = onText;

  const int result = md_parse(
      preprocessed.data(), static_cast<MD_SIZE>(preprocessed.size()), &parser, &state);

  if (result != 0 || doc->root == nullptr) {
    doc->root = doc->arena.alloc(NodeType::Document);
    Node* paragraph = doc->arena.alloc(NodeType::Paragraph);
    Node* text = doc->arena.alloc(NodeType::Text);
    text->text = markdown;
    paragraph->children.push_back(text);
    doc->root->children.push_back(paragraph);
    return doc;
  }

  applyInlineExtensions(*doc);
  return doc;
}

} // namespace jetmarkdown
