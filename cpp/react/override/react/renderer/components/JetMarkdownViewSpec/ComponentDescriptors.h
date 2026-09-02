#pragma once

// Shadows the codegen-generated ComponentDescriptors.h (this directory is
// first on the include path) so autolinking and the iOS component view
// register a descriptor over the custom measurable shadow node instead of
// the codegen default.

#include <react/renderer/core/ConcreteComponentDescriptor.h>

#include "../../../../../JetMarkdownShadowNode.h"

namespace facebook::react {

using JetMarkdownViewComponentDescriptor =
    ConcreteComponentDescriptor<JetMarkdownShadowNode>;

} // namespace facebook::react
