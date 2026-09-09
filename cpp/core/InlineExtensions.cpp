#include "InlineExtensions.h"

#include <cstring>

namespace jetmarkdown {

namespace {

constexpr size_t kNpos = std::string::npos;

// Walls stop delimiter matching; inline nodes may sit between a pair.
bool isWall(NodeType type) {
  switch (type) {
    case NodeType::Text:
    case NodeType::SoftBreak:
    case NodeType::HardBreak:
    case NodeType::Bold:
    case NodeType::Italic:
    case NodeType::Strikethrough:
    case NodeType::Link:
    case NodeType::InlineCode:
    case NodeType::Spoiler:
    case NodeType::Superscript:
    case NodeType::Subscript:
    case NodeType::Image:
      return false;
    default:
      return true;
  }
}

struct Pos {
  size_t child = 0;
  size_t off = 0;
  bool valid = false;
};

// First occurrence of token in Text children, starting at (startChild,
// startOff). Search stops at walls.
Pos findToken(
    const std::vector<Node*>& kids,
    size_t startChild,
    size_t startOff,
    const char* token) {
  for (size_t ci = startChild; ci < kids.size(); ci++) {
    Node* child = kids[ci];
    if (child->type == NodeType::Text) {
      if (child->verbatim) {
        // Escaped/entity characters never form delimiters.
        continue;
      }
      size_t from = (ci == startChild) ? startOff : 0;
      size_t found = child->text.find(token, from);
      if (found != kNpos) {
        return {ci, found, true};
      }
    } else if (isWall(child->type)) {
      return {};
    }
  }
  return {};
}

// Wraps [open, close) into a new `type` node, splitting the boundary Text
// nodes. closeLen may be 0 (delimiter-less end, used by bare ^word).
// Returns the child index right after the wrapper, where scanning resumes.
size_t wrapRange(
    std::vector<Node*>& kids,
    AstArena& arena,
    Pos open,
    size_t openLen,
    Pos close,
    size_t closeLen,
    NodeType type) {
  Node* openNode = kids[open.child];
  Node* closeNode = kids[close.child];
  Node* wrapper = arena.alloc(type);

  const std::string before = openNode->text.substr(0, open.off);
  std::string after;

  auto pushText = [&](std::string&& value) {
    if (value.empty()) {
      return;
    }
    Node* text = arena.alloc(NodeType::Text);
    text->text = std::move(value);
    wrapper->children.push_back(text);
  };

  if (open.child == close.child) {
    const size_t innerStart = open.off + openLen;
    pushText(openNode->text.substr(innerStart, close.off - innerStart));
    after = openNode->text.substr(close.off + closeLen);
  } else {
    pushText(openNode->text.substr(open.off + openLen));
    for (size_t i = open.child + 1; i < close.child; i++) {
      wrapper->children.push_back(kids[i]);
    }
    pushText(closeNode->text.substr(0, close.off));
    after = closeNode->text.substr(close.off + closeLen);
  }

  std::vector<Node*> replacement;
  if (!before.empty()) {
    openNode->text = before;
    replacement.push_back(openNode);
  }
  replacement.push_back(wrapper);
  const size_t resumeIdx = open.child + replacement.size();
  if (!after.empty()) {
    Node* text = arena.alloc(NodeType::Text);
    text->text = std::move(after);
    replacement.push_back(text);
  }

  kids.erase(kids.begin() + open.child, kids.begin() + close.child + 1);
  kids.insert(kids.begin() + open.child, replacement.begin(), replacement.end());
  return resumeIdx;
}

// Cross-node symmetric-or-asymmetric pair pass (spoilers, strikethrough).
void pairPass(
    Node* parent,
    AstArena& arena,
    const char* openTok,
    const char* closeTok,
    NodeType type) {
  auto& kids = parent->children;
  const size_t openLen = std::strlen(openTok);
  const size_t closeLen = std::strlen(closeTok);

  size_t ci = 0;
  size_t off = 0;
  while (ci < kids.size()) {
    Node* child = kids[ci];
    if (child->type != NodeType::Text || child->verbatim) {
      ci++;
      off = 0;
      continue;
    }
    const size_t found = child->text.find(openTok, off);
    if (found == kNpos) {
      ci++;
      off = 0;
      continue;
    }
    const Pos close = findToken(kids, ci, found + openLen, closeTok);
    if (!close.valid) {
      off = found + openLen;
      continue;
    }
    if (close.child == ci && close.off == found + openLen) {
      // Empty content ("||||") stays literal.
      off = close.off + closeLen;
      continue;
    }
    ci = wrapRange(kids, arena, {ci, found, true}, openLen, close, closeLen, type);
    off = 0;
  }
}

bool containsWhitespace(const std::string& s, size_t start, size_t end) {
  for (size_t i = start; i < end; i++) {
    if (s[i] == ' ' || s[i] == '\t') {
      return true;
    }
  }
  return false;
}

// ~subscript~ : same Text run, non-empty, no whitespace inside.
void subscriptPass(Node* parent, AstArena& arena) {
  auto& kids = parent->children;
  size_t ci = 0;
  size_t off = 0;
  while (ci < kids.size()) {
    Node* child = kids[ci];
    if (child->type != NodeType::Text || child->verbatim) {
      ci++;
      off = 0;
      continue;
    }
    const size_t open = child->text.find('~', off);
    if (open == kNpos) {
      ci++;
      off = 0;
      continue;
    }
    const size_t close = child->text.find('~', open + 1);
    if (close == kNpos) {
      ci++;
      off = 0;
      continue;
    }
    if (close == open + 1 || containsWhitespace(child->text, open + 1, close)) {
      off = open + 1;
      continue;
    }
    ci = wrapRange(
        kids, arena, {ci, open, true}, 1, {ci, close, true}, 1, NodeType::Subscript);
    off = 0;
  }
}

// ^(multi word) | ^pandoc^ | ^word : see header for the disambiguation.
void superscriptPass(Node* parent, AstArena& arena) {
  auto& kids = parent->children;
  size_t ci = 0;
  size_t off = 0;
  while (ci < kids.size()) {
    Node* child = kids[ci];
    if (child->type != NodeType::Text || child->verbatim) {
      ci++;
      off = 0;
      continue;
    }
    const std::string& text = child->text;
    const size_t caret = text.find('^', off);
    if (caret == kNpos) {
      ci++;
      off = 0;
      continue;
    }

    // ^(multi word) — may span styled runs until the first ")".
    if (caret + 1 < text.size() && text[caret + 1] == '(') {
      const Pos close = findToken(kids, ci, caret + 2, ")");
      if (close.valid && !(close.child == ci && close.off == caret + 2)) {
        ci = wrapRange(
            kids, arena, {ci, caret, true}, 2, close, 1, NodeType::Superscript);
        off = 0;
        continue;
      }
      off = caret + 1;
      continue;
    }

    if (caret + 1 >= text.size() || text[caret + 1] == ' ' ||
        text[caret + 1] == '\t' || text[caret + 1] == '^') {
      off = caret + 1;
      continue;
    }

    const size_t nextCaret = text.find('^', caret + 1);
    size_t nextSpace = kNpos;
    for (size_t i = caret + 1; i < text.size(); i++) {
      if (text[i] == ' ' || text[i] == '\t') {
        nextSpace = i;
        break;
      }
    }

    if (nextCaret != kNpos && (nextSpace == kNpos || nextCaret < nextSpace)) {
      // Pandoc ^sup^.
      ci = wrapRange(
          kids,
          arena,
          {ci, caret, true},
          1,
          {ci, nextCaret, true},
          1,
          NodeType::Superscript);
      off = 0;
      continue;
    }

    // Reddit bare ^word — runs to the next whitespace (or end of run).
    const size_t end = (nextSpace == kNpos) ? text.size() : nextSpace;
    if (end == caret + 1) {
      off = caret + 1;
      continue;
    }
    ci = wrapRange(
        kids, arena, {ci, caret, true}, 1, {ci, end, true}, 0, NodeType::Superscript);
    off = 0;
  }
}

void process(Node* node, AstArena& arena) {
  if (node->type == NodeType::CodeBlock || node->type == NodeType::InlineCode ||
      node->type == NodeType::Image) {
    return;
  }
  if (!node->children.empty()) {
    pairPass(node, arena, ">!", "!<", NodeType::Spoiler);
    pairPass(node, arena, "||", "||", NodeType::Spoiler);
    pairPass(node, arena, "~~", "~~", NodeType::Strikethrough);
    subscriptPass(node, arena);
    superscriptPass(node, arena);
    for (Node* child : node->children) {
      process(child, arena);
    }
  }
}

} // namespace

void applyInlineExtensions(MarkdownDocument& doc) {
  if (doc.root != nullptr) {
    process(doc.root, doc.arena);
  }
}

} // namespace jetmarkdown
