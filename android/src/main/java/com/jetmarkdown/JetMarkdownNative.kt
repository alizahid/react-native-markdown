package com.jetmarkdown

import com.jetmarkdown.measure.MarkdownMeasurer
import com.jetmarkdown.parser.AstDecoder
import com.jetmarkdown.parser.MdNode

/**
 * JNI bridge into the shared C++ core. The natives are linked into the app's
 * `libappmodules.so` (loaded by React Native at startup), so no explicit
 * `System.loadLibrary` is required.
 */
object JetMarkdownNative {
  @Volatile private var installed = false

  fun ensureInstalled() {
    if (!installed) {
      synchronized(this) {
        if (!installed) {
          // libappmodules.so may not be loaded yet at package-construction
          // time; callers retry from later lifecycle points.
          installed = runCatching { installMeasurer(MarkdownMeasurer) }.isSuccess
        }
      }
    }
  }

  fun parseMarkdown(markdown: String): MdNode {
    return AstDecoder.decode(parse(markdown.toByteArray(Charsets.UTF_8)))
  }


  @JvmStatic private external fun parse(markdown: ByteArray): ByteArray

  @JvmStatic private external fun installMeasurer(measurer: MarkdownMeasurer)
}
