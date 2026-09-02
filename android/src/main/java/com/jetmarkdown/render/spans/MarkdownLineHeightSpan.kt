package com.jetmarkdown.render.spans

import android.graphics.Paint
import android.text.style.LineHeightSpan
import kotlin.math.ceil
import kotlin.math.floor

/**
 * React Native's lineHeight semantics: the line box is exactly [heightPx]
 * tall with glyphs centered (mirrors RN's CustomLineHeightSpan).
 */
class MarkdownLineHeightSpan(private val heightPx: Int) : LineHeightSpan {
  override fun chooseHeight(
    text: CharSequence,
    start: Int,
    end: Int,
    spanstartv: Int,
    lineHeight: Int,
    fm: Paint.FontMetricsInt,
  ) {
    if (fm.descent > heightPx) {
      // Show as much descent as possible.
      fm.descent = minOf(heightPx, fm.descent)
      fm.bottom = fm.descent
      fm.ascent = 0
      fm.top = 0
    } else if (-fm.ascent + fm.descent > heightPx) {
      // Keep the descent, crop the ascent.
      fm.bottom = fm.descent
      fm.ascent = -heightPx + fm.descent
      fm.top = fm.ascent
    } else if (-fm.ascent + fm.bottom > heightPx) {
      // Crop the additional bottom padding.
      fm.top = fm.ascent
      fm.bottom = fm.ascent + heightPx
    } else if (-fm.top + fm.bottom > heightPx) {
      // Crop the additional top padding.
      fm.top = fm.bottom - heightPx
    } else {
      // Center the glyphs in the taller line box.
      val extra = (heightPx - (-fm.top + fm.bottom)) / 2.0
      fm.top -= ceil(extra).toInt()
      fm.bottom += floor(extra).toInt()
      fm.ascent = fm.top
      fm.descent = fm.bottom
    }
  }
}
