TokenIterator = require './token-iterator'
{Point} = require 'text-buffer'

module.exports =
class LinesYardstick
  constructor: (@model, @lineNodesProvider, @lineTopIndex, grammarRegistry) ->
    @tokenIterator = new TokenIterator({grammarRegistry})
    @rangeForMeasurement = document.createRange()
    @invalidateCache()

  invalidateCache: ->
    @pixelPositionsByLineIdAndColumn = {}

  measuredRowForPixelPosition: (pixelPosition) ->
    targetTop = pixelPosition.top
    row = Math.floor(targetTop / @model.getLineHeightInPixels())
    row if 0 <= row <= @model.getLastScreenRow()

  screenPositionForPixelPosition: (pixelPosition) ->
    targetTop = pixelPosition.top
    targetLeft = pixelPosition.left
    defaultCharWidth = @model.getDefaultCharWidth()
    row = @lineTopIndex.rowForPixelPosition(targetTop, 'floor')
    targetLeft = 0 if targetTop < 0
    targetLeft = Infinity if row > @model.getLastScreenRow()
    row = Math.min(row, @model.getLastScreenRow())

    line = @model.tokenizedLineForScreenRow(row)
    lineNode = @lineNodesProvider.lineNodeForLineIdAndScreenRow(line?.id, row)

    return Point(row, 0) unless lineNode? and line?

    textNodes = @lineNodesProvider.textNodesForLineIdAndScreenRow(line.id, row)
    column = 0
    previousColumn = 0
    previousLeft = 0

    @tokenIterator.reset(line, false)
    while @tokenIterator.next()
      text = @tokenIterator.getText()
      textIndex = 0
      while textIndex < text.length
        if @tokenIterator.isPairedCharacter()
          char = text
          charLength = 2
          textIndex += 2
        else
          char = text[textIndex]
          charLength = 1
          textIndex++

        unless textNode?
          textNode = textNodes.shift()
          textNodeLength = textNode.textContent.length
          textNodeIndex = 0
          nextTextNodeIndex = textNodeLength

        while nextTextNodeIndex <= column
          textNode = textNodes.shift()
          textNodeLength = textNode.textContent.length
          textNodeIndex = nextTextNodeIndex
          nextTextNodeIndex = textNodeIndex + textNodeLength

        indexWithinTextNode = column - textNodeIndex
        left = @leftPixelPositionForCharInTextNode(lineNode, textNode, indexWithinTextNode)
        charWidth = left - previousLeft

        return Point(row, previousColumn) if targetLeft <= previousLeft + (charWidth / 2)

        previousLeft = left
        previousColumn = column
        column += charLength

    if targetLeft <= previousLeft + (charWidth / 2)
      Point(row, previousColumn)
    else
      Point(row, column)

  pixelPositionForScreenPosition: (screenPosition, clip=true) ->
    screenPosition = Point.fromObject(screenPosition)
    screenPosition = @model.clipScreenPosition(screenPosition) if clip

    targetRow = screenPosition.row
    targetColumn = screenPosition.column

    top = @lineTopIndex.pixelPositionForRow(targetRow)
    left = @leftPixelPositionForScreenPosition(targetRow, targetColumn)

    {top, left}

  leftPixelPositionForScreenPosition: (row, column) ->
    line = @model.tokenizedLineForScreenRow(row)
    lineNode = @lineNodesProvider.lineNodeForLineIdAndScreenRow(line?.id, row)

    return 0 unless line? and lineNode?

    if cachedPosition = @pixelPositionsByLineIdAndColumn[line.id]?[column]
      return cachedPosition

    textNodes = @lineNodesProvider.textNodesForLineIdAndScreenRow(line.id, row)
    indexWithinTextNode = null
    charIndex = 0

    @tokenIterator.reset(line, false)
    while @tokenIterator.next()
      break if foundIndexWithinTextNode?

      text = @tokenIterator.getText()

      textIndex = 0
      while textIndex < text.length
        if @tokenIterator.isPairedCharacter()
          char = text
          charLength = 2
          textIndex += 2
        else
          char = text[textIndex]
          charLength = 1
          textIndex++

        unless textNode?
          textNode = textNodes.shift()
          textNodeLength = textNode.textContent.length
          textNodeIndex = 0
          nextTextNodeIndex = textNodeLength

        while nextTextNodeIndex <= charIndex
          textNode = textNodes.shift()
          textNodeLength = textNode.textContent.length
          textNodeIndex = nextTextNodeIndex
          nextTextNodeIndex = textNodeIndex + textNodeLength

        if charIndex is column
          foundIndexWithinTextNode = charIndex - textNodeIndex
          break

        charIndex += charLength

    if textNode?
      foundIndexWithinTextNode ?= textNode.textContent.length
      position = @leftPixelPositionForCharInTextNode(
        lineNode, textNode, foundIndexWithinTextNode
      )
      @pixelPositionsByLineIdAndColumn[line.id] ?= {}
      @pixelPositionsByLineIdAndColumn[line.id][column] = position
      position
    else
      0

  leftPixelPositionForCharInTextNode: (lineNode, textNode, charIndex) ->
    if charIndex is 0
      width = 0
    else
      @rangeForMeasurement.setStart(textNode, 0)
      @rangeForMeasurement.setEnd(textNode, charIndex)
      width = @rangeForMeasurement.getBoundingClientRect().width

    @rangeForMeasurement.setStart(textNode, 0)
    @rangeForMeasurement.setEnd(textNode, textNode.textContent.length)
    left = @rangeForMeasurement.getBoundingClientRect().left

    offset = lineNode.getBoundingClientRect().left

    left + width - offset
