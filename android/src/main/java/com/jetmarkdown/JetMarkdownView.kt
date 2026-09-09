package com.jetmarkdown

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.StateWrapper
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.jetmarkdown.render.ContentCache
import com.jetmarkdown.render.RenderedContent
import com.jetmarkdown.style.StyleConfig
import com.jetmarkdown.views.BlockStackView
import com.jetmarkdown.views.MarkdownHost

/**
 * Host view: one nested block stack. Fabric supplies the final frame (the
 * C++ shadow node measured the same cached content), so onLayout only
 * distributes frames.
 */
class JetMarkdownView(context: Context) : ViewGroup(context), MarkdownHost {
  private var markdown: String = ""
  private var stylesJson: String = ""

  var allowFontScaling = true
    set(value) {
      if (field != value) {
        field = value
        boundLayout = null
        requestLayout()
      }
    }
  // Layouts are cached per (content, width, image sizes), and content per
  // (markdown, styles, font scale, appearance): identity says whether the
  // bound view tree is still current.
  private var boundLayout: RenderedContent.WidthLayout? = null
  private val stack = BlockStackView(context)

  /** url -> [w, h] dp: from the images prop (wins) and loaded bitmaps. */
  private val propImageSizes = HashMap<String, FloatArray>()
  private val loadedImageSizes = HashMap<String, FloatArray>()
  var stateWrapper: StateWrapper? = null

  private val revealedSpoilers = HashSet<Int>()

  init {
    addView(stack)
    stack.host = this
  }

  /** Fabric view recycling: clear all per-content state. */
  fun resetForRecycle() {
    markdown = ""
    stylesJson = ""
    allowFontScaling = true
    stateWrapper = null
    boundLayout = null
    propImageSizes.clear()
    loadedImageSizes.clear()
    revealedSpoilers.clear()
    stack.setBlocks(emptyList(), 0f)
  }

  override fun onImageIntrinsicSize(url: String, widthDp: Float, heightDp: Float) {
    if (!propImageSizes.containsKey(url) && !loadedImageSizes.containsKey(url)) {
      loadedImageSizes[url] = floatArrayOf(widthDp, heightDp)
      publishImageSizes()
      requestLayout()
    }
  }

  override fun isSpoilerRevealed(id: Int): Boolean = revealedSpoilers.contains(id)

  override fun toggleSpoiler(id: Int) {
    if (!revealedSpoilers.add(id)) {
      revealedSpoilers.remove(id)
    }
    invalidateDeep(this)
  }

  override fun onLinkPress(url: String) = emitUrlEvent("topLinkPress", url)

  override fun onLinkLongPress(url: String) = emitUrlEvent("topLinkLongPress", url)

  override fun onImagePress(url: String, xDp: Float, yDp: Float, widthDp: Float, heightDp: Float) =
    emitEvent("topImagePress") {
      putString("url", url)
      putDouble("x", xDp.toDouble())
      putDouble("y", yDp.toDouble())
      putDouble("width", widthDp.toDouble())
      putDouble("height", heightDp.toDouble())
    }

  private fun emitUrlEvent(name: String, url: String) =
    emitEvent(name) { putString("url", url) }

  private fun emitEvent(name: String, data: WritableMap.() -> Unit) {
    val reactContext = context as? com.facebook.react.bridge.ReactContext ?: return
    val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
    val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
    dispatcher.dispatchEvent(object : Event<Nothing>(surfaceId, id) {
      override fun getEventName(): String = name

      override fun getEventData(): WritableMap = Arguments.createMap().apply(data)
    })
  }

  private fun invalidateDeep(view: android.view.View) {
    view.invalidate()
    if (view is ViewGroup) {
      for (i in 0 until view.childCount) {
        invalidateDeep(view.getChildAt(i))
      }
    }
  }

  fun setImages(value: ReadableArray?) {
    propImageSizes.clear()
    if (value != null) {
      for (i in 0 until value.size()) {
        val entry = value.getMap(i) ?: continue
        val url = entry.getString("url") ?: continue
        propImageSizes[url] = floatArrayOf(
          entry.getDouble("width").toFloat(),
          entry.getDouble("height").toFloat(),
        )
      }
    }
    requestLayout()
    invalidate()
  }

  // Pushes discovered sizes into the shadow-node state so measure() grows
  // the component. The prop entries stay out (already known to C++).
  private fun publishImageSizes() {
    val wrapper = stateWrapper ?: return
    val sizes = Arguments.createMap()
    for ((url, size) in loadedImageSizes) {
      val entry = Arguments.createMap()
      entry.putDouble("width", size[0].toDouble())
      entry.putDouble("height", size[1].toDouble())
      sizes.putMap(url, entry)
    }
    val state = Arguments.createMap()
    state.putMap("imageSizes", sizes)
    wrapper.updateState(state)
  }

  private fun mergedImageSizes(): Map<String, FloatArray> {
    if (loadedImageSizes.isEmpty() && propImageSizes.isEmpty()) {
      return emptyMap()
    }
    val merged = HashMap<String, FloatArray>(loadedImageSizes)
    merged.putAll(propImageSizes)
    return merged
  }

  fun setMarkdown(value: String?) {
    val next = value ?: ""
    if (next != markdown) {
      markdown = next
      // Spoiler ids are render-order counters; carrying revealed indices
      // into different content would pre-reveal the wrong spans.
      revealedSpoilers.clear()
      // Sizes learned for the old document may not apply to the new one.
      loadedImageSizes.clear()
      requestLayout()
      invalidate()
    }
  }

  fun setStylesJson(value: String?) {
    val next = value ?: ""
    if (next != stylesJson) {
      stylesJson = next
      requestLayout()
      invalidate()
    }
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    // Fabric passes exact dimensions computed by the shadow node.
    setMeasuredDimension(
      MeasureSpec.getSize(widthMeasureSpec),
      MeasureSpec.getSize(heightMeasureSpec),
    )
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val density = resources.displayMetrics.density
    // Must match the shadow node's LayoutContext::fontSizeMultiplier
    // (Android's system font scale).
    val fontScale =
      if (allowFontScaling) resources.configuration.fontScale else 1.0f
    val styles = StyleConfig.from(stylesJson)

    setBackgroundColor(styles.backgroundColor ?: Color.TRANSPARENT)

    val paddingLeftPx = (styles.paddingLeft * density).toInt()
    val paddingRightPx = (styles.paddingRight * density).toInt()
    val paddingTopPx = (styles.paddingTop * density).toInt()
    val contentWidthPx = (r - l) - paddingLeftPx - paddingRightPx
    if (contentWidthPx <= 0) {
      stack.setBlocks(emptyList(), 0f)
      boundLayout = null
      return
    }

    val content = ContentCache.get(markdown, stylesJson, fontScale)
    val imageSizes = mergedImageSizes()
    val layout = content.layoutFor(contentWidthPx, imageSizes)

    if (layout !== boundLayout) {
      boundLayout = layout
      stack.setBlocks(layout.measured, content.gap)
    }

    val contentHeight =
      (layout.totalHeightPx - (styles.paddingTop + styles.paddingBottom) * density).toInt()
    stack.measure(
      MeasureSpec.makeMeasureSpec(contentWidthPx, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(contentHeight, MeasureSpec.EXACTLY),
    )
    stack.layout(
      paddingLeftPx,
      paddingTopPx,
      paddingLeftPx + contentWidthPx,
      paddingTopPx + contentHeight,
    )
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}
