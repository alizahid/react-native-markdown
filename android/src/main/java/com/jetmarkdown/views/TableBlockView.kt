package com.jetmarkdown.views

import android.content.Context
import android.graphics.Canvas
import android.view.ViewGroup
import com.jetmarkdown.render.Block
import com.jetmarkdown.render.MeasuredBlock

/**
 * Table: paints the table box, hosts a grid in a horizontal scroller so
 * wide tables keep readable column widths.
 */
class TableBlockView(context: Context) : ViewGroup(context) {
  private var measured: MeasuredBlock? = null
  private var block: Block.Table? = null
  private val scroller = NestedHorizontalScrollView(context).apply {
    isHorizontalScrollBarEnabled = false
    overScrollMode = OVER_SCROLL_NEVER
  }
  private val grid = TableGridView(context)

  init {
    setWillNotDraw(false)
    scroller.addView(grid)
    addView(scroller)
  }

  fun bind(measuredBlock: MeasuredBlock, table: Block.Table, host: MarkdownHost? = null) {
    measured = measuredBlock
    block = table
    grid.bind(measuredBlock, table, host)
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
    val tree = measured ?: return
    val left = (style.borderLeftWidth + style.paddingLeft).toInt()
    val top = (style.borderTopWidth + style.paddingTop).toInt()
    val right = (r - l) - (style.borderRightWidth + style.paddingRight).toInt()
    val gridHeight = tree.rowHeights.sum().toInt()

    scroller.measure(
      MeasureSpec.makeMeasureSpec(right - left, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(gridHeight, MeasureSpec.EXACTLY),
    )
    scroller.layout(left, top, right, top + gridHeight)
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}

/** The unclipped grid inside the scroller: row boxes + cell text. */
class TableGridView(context: Context) : ViewGroup(context) {
  private var measured: MeasuredBlock? = null
  private var block: Block.Table? = null

  init {
    setWillNotDraw(false)
  }

  fun bind(measuredBlock: MeasuredBlock, table: Block.Table, host: MarkdownHost? = null) {
    measured = measuredBlock
    block = table
    // One text view per cell, row-major; grow/shrink then rebind in place.
    val needed = measuredBlock.cellLayouts.sumOf { it.size }
    while (childCount > needed) {
      removeViewAt(childCount - 1)
    }
    while (childCount < needed) {
      addView(BlockTextView(context))
    }
    var index = 0
    for (row in measuredBlock.cellLayouts) {
      for (cell in row) {
        (getChildAt(index++) as BlockTextView).apply {
          this.host = host
          setTextLayout(cell)
        }
      }
    }
    invalidate()
    requestLayout()
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    val tree = measured
    setMeasuredDimension(
      tree?.contentWidthPx?.toInt() ?: 0,
      tree?.rowHeights?.sum()?.toInt() ?: 0,
    )
  }

  override fun onDraw(canvas: Canvas) {
    val table = block ?: return
    val tree = measured ?: return
    val width = tree.contentWidthPx
    var y = 0f
    tree.rowHeights.forEachIndexed { rowIndex, rowHeight ->
      val isHeader = table.rows.getOrNull(rowIndex)?.isHeader == true
      canvas.save()
      canvas.translate(0f, y)
      BoxDrawing.draw(canvas, table.rowStyle(isHeader), width, rowHeight)
      canvas.restore()
      y += rowHeight
    }
  }

  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    val table = block ?: return
    val tree = measured ?: return

    var index = 0
    var y = 0f
    tree.cellLayouts.forEachIndexed { rowIndex, row ->
      var x = 0f
      val isHeader = table.rows.getOrNull(rowIndex)?.isHeader == true
      row.forEachIndexed { column, cell ->
        val child = getChildAt(index++) ?: return@forEachIndexed
        val cellLeft = (x + table.padLeft(isHeader)).toInt()
        val cellTop =
          (y + table.padTop(isHeader) + table.rowStyle(isHeader).borderTopWidth).toInt()
        child.measure(
          MeasureSpec.makeMeasureSpec(cell.width, MeasureSpec.EXACTLY),
          MeasureSpec.makeMeasureSpec(cell.height, MeasureSpec.EXACTLY),
        )
        child.layout(cellLeft, cellTop, cellLeft + cell.width, cellTop + cell.height)
        x += tree.columnWidths[column]
      }
      y += tree.rowHeights[rowIndex]
    }
  }

  override fun shouldDelayChildPressedState(): Boolean = false
}
