package com.jetmarkdown.views

import android.content.Context
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import com.jetmarkdown.render.Block
import com.jetmarkdown.render.MeasuredBlock

/**
 * Vertical stack of measured blocks. All heights come from the measured
 * tree, so onLayout only distributes frames.
 */
class BlockStackView(context: Context) : ViewGroup(context) {
  private var measured: List<MeasuredBlock> = emptyList()
  private var gapPx = 0f

  var host: MarkdownHost? = null

  // Discard hook for views dropped for good: stop in-flight image requests
  // from delivering into a recycled host.
  private fun unbindImages(view: View) {
    when (view) {
      is MarkdownImageView -> view.unbind()
      is ViewGroup -> for (index in 0 until view.childCount) unbindImages(view.getChildAt(index))
    }
  }

  /**
   * Rebinds in place: a child of the right kind at the same index is reused,
   * anything else is replaced. List recycling rebinds whole trees, so the
   * common case (same block kinds, different content) allocates nothing.
   */
  fun setBlocks(blocks: List<MeasuredBlock>, gap: Float) {
    measured = blocks
    gapPx = gap
    blocks.forEachIndexed { index, block ->
      val old = getChildAt(index)
      val view = bindView(old, block)
      if (view !== old) {
        if (old != null) {
          unbindImages(old)
          removeViewAt(index)
        }
        addView(view, index)
      }
    }
    while (childCount > blocks.size) {
      val extra = getChildAt(childCount - 1)
      unbindImages(extra)
      removeViewAt(childCount - 1)
    }
    requestLayout()
  }

  private fun bindView(old: View?, measuredBlock: MeasuredBlock): View {
    return when (val block = measuredBlock.block) {
      is Block.Text -> (old as? BlockTextView ?: BlockTextView(context)).apply {
        this.host = this@BlockStackView.host
        setBlock(block)
        measuredBlock.textLayout?.let(::setTextLayout)
      }
      is Block.Code -> (old as? CodeBlockView ?: CodeBlockView(context)).apply {
        bind(measuredBlock, block)
      }
      is Block.Quote -> (old as? QuoteView ?: QuoteView(context)).apply {
        bind(measuredBlock, block, gapPx, this@BlockStackView.host)
      }
      is Block.ListBlock -> (old as? ListBlockView ?: ListBlockView(context)).apply {
        bind(measuredBlock, block, gapPx, this@BlockStackView.host)
      }
      is Block.Divider -> (old as? DividerView ?: DividerView(context)).apply { color = block.color }
      is Block.Table -> (old as? TableBlockView ?: TableBlockView(context)).apply {
        bind(measuredBlock, block, this@BlockStackView.host)
      }
      is Block.Image -> (old as? MarkdownImageView ?: MarkdownImageView(context)).apply {
        this.host = this@BlockStackView.host
        bind(block)
      }
    }
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    setMeasuredDimension(
      MeasureSpec.getSize(widthMeasureSpec),
      MeasureSpec.getSize(heightMeasureSpec),
    )
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val width = r - l
    var y = 0
    measured.forEachIndexed { index, block ->
      val child = getChildAt(index) ?: return@forEachIndexed
      val height = block.heightPx.toInt()
      val childWidth = if (block.block is Block.Image) {
        block.contentWidthPx.toInt().coerceAtMost(width)
      } else {
        width
      }
      child.measure(
        MeasureSpec.makeMeasureSpec(childWidth, MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
      )
      child.layout(0, y, childWidth, y + height)
      y += height
      if (index < measured.size - 1) {
        y += gapPx.toInt()
      }
    }
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}

/** Thematic break. */
class DividerView(context: Context) : View(context) {
  var color: Int = 0
    set(value) {
      field = value
      setBackgroundColor(value)
    }
}

/** Block quote: paints its box style, hosts a nested stack inside padding. */
class QuoteView(context: Context) : ViewGroup(context) {
  private var measured: MeasuredBlock? = null
  private var block: Block.Quote? = null
  private val stack = BlockStackView(context)

  init {
    setWillNotDraw(false)
    addView(stack)
  }

  fun bind(
    measuredBlock: MeasuredBlock,
    quote: Block.Quote,
    gap: Float,
    host: MarkdownHost? = null,
  ) {
    measured = measuredBlock
    block = quote
    stack.host = host
    stack.setBlocks(measuredBlock.children, gap)
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    block?.let { BoxDrawing.draw(canvas, it.style, width.toFloat(), height.toFloat()) }
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    setMeasuredDimension(
      MeasureSpec.getSize(widthMeasureSpec),
      MeasureSpec.getSize(heightMeasureSpec),
    )
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val style = block?.style ?: return
    val left = (style.borderLeftWidth + style.paddingLeft).toInt()
    val top = (style.borderTopWidth + style.paddingTop).toInt()
    val right = (r - l) - (style.borderRightWidth + style.paddingRight).toInt()
    val bottom = (b - t) - (style.borderBottomWidth + style.paddingBottom).toInt()
    stack.measure(
      MeasureSpec.makeMeasureSpec(right - left, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(bottom - top, MeasureSpec.EXACTLY),
    )
    stack.layout(left, top, right, bottom)
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}

/** Code block: paints its box, hosts unwrapped text in a horizontal scroller. */
class CodeBlockView(context: Context) : ViewGroup(context) {
  private var measured: MeasuredBlock? = null
  private var block: Block.Code? = null
  private val scroller = NestedHorizontalScrollView(context).apply {
    isHorizontalScrollBarEnabled = false
    overScrollMode = OVER_SCROLL_NEVER
    clipToPadding = false
  }
  private val textView = BlockTextView(context)

  init {
    setWillNotDraw(false)
    scroller.addView(textView)
    addView(scroller)
  }

  fun bind(measuredBlock: MeasuredBlock, code: Block.Code) {
    measured = measuredBlock
    block = code
    measuredBlock.textLayout?.let(textView::setTextLayout)
    invalidate()
    requestLayout()
  }

  override fun onDraw(canvas: Canvas) {
    block?.let { BoxDrawing.draw(canvas, it.style, width.toFloat(), height.toFloat()) }
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    setMeasuredDimension(
      MeasureSpec.getSize(widthMeasureSpec),
      MeasureSpec.getSize(heightMeasureSpec),
    )
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val style = block?.style ?: return
    val contentWidth = measured?.contentWidthPx?.toInt() ?: 0
    val textHeight = measured?.textLayout?.height ?: 0
    val left = style.paddingLeft.toInt()
    val top = style.paddingTop.toInt()
    val right = (r - l) - style.paddingRight.toInt()

    textView.measure(
      MeasureSpec.makeMeasureSpec(contentWidth, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(textHeight, MeasureSpec.EXACTLY),
    )
    scroller.measure(
      MeasureSpec.makeMeasureSpec(right - left, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(textHeight, MeasureSpec.EXACTLY),
    )
    scroller.layout(left, top, right, top + textHeight)
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}

/** List: rows of a fixed-width marker column and nested content stacks. */
class ListBlockView(context: Context) : ViewGroup(context) {
  private var measured: MeasuredBlock? = null
  private var block: Block.ListBlock? = null
  private var gapPx = 0f

  fun bind(
    measuredBlock: MeasuredBlock,
    list: Block.ListBlock,
    gap: Float,
    host: MarkdownHost? = null,
  ) {
    measured = measuredBlock
    block = list
    gapPx = gap
    // Children are (marker, content) pairs; grow/shrink the pair list, then
    // rebind every pair in place.
    val needed = measuredBlock.markerLayouts.size * 2
    while (childCount > needed) {
      removeViewAt(childCount - 1)
    }
    while (childCount < needed) {
      addView(BlockTextView(context))
      addView(BlockStackView(context))
    }
    measuredBlock.markerLayouts.forEachIndexed { index, marker ->
      (getChildAt(index * 2) as BlockTextView).setTextLayout(marker)
      (getChildAt(index * 2 + 1) as BlockStackView).apply {
        this.host = host
        setBlocks(measuredBlock.rowContents[index], gap)
      }
    }
    requestLayout()
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    setMeasuredDimension(
      MeasureSpec.getSize(widthMeasureSpec),
      MeasureSpec.getSize(heightMeasureSpec),
    )
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val list = block ?: return
    val tree = measured ?: return
    val markerX = (list.marginLeftPx + list.markerMarginLeftPx).toInt()
    val contentX = (markerX + list.markerWidthPx).toInt()
    val contentWidth = tree.contentWidthPx.toInt()

    var y = 0
    tree.markerLayouts.forEachIndexed { index, marker ->
      val markerView = getChildAt(index * 2) ?: return@forEachIndexed
      val contentView = getChildAt(index * 2 + 1) ?: return@forEachIndexed
      val contentHeight = tree.rowContents[index].let { row ->
        var height = 0f
        row.forEachIndexed { i, child ->
          height += child.heightPx
          if (i < row.size - 1) {
            height += gapPx
          }
        }
        height
      }
      val rowHeight = maxOf(marker.height.toFloat(), contentHeight).toInt()

      markerView.measure(
        MeasureSpec.makeMeasureSpec(list.markerWidthPx.toInt(), MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(marker.height, MeasureSpec.EXACTLY),
      )
      markerView.layout(markerX, y, contentX, y + marker.height)

      contentView.measure(
        MeasureSpec.makeMeasureSpec(contentWidth, MeasureSpec.EXACTLY),
        MeasureSpec.makeMeasureSpec(contentHeight.toInt(), MeasureSpec.EXACTLY),
      )
      contentView.layout(contentX, y, contentX + contentWidth, y + contentHeight.toInt())

      y += rowHeight
      if (index < tree.markerLayouts.size - 1) {
        y += (gapPx / 2f).toInt()
      }
    }
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}
