class @Annotator
  constructor: ->
    @_pages = []
    @_activeHighlightStart = null
    @_activeHighlightEnd = null

  setPage: (page) =>
    # Initialize the page
    @_pages[page.pageNumber - 1] =
      pageNumber: page.pageNumber
      textSegments: []
      imageSegments: []
      highlightsEnabled: false

  setTextContent: (pageNumber, textContent) =>
    @_pages[pageNumber - 1].textContent = textContent

  _roundArea: (area) =>
    areaRounded = _.clone area
    areaRounded.left = Math.floor areaRounded.left
    areaRounded.top = Math.floor areaRounded.top
    areaRounded.width += area.left - areaRounded.left
    areaRounded.height += area.top - areaRounded.top
    areaRounded.width = Math.ceil areaRounded.width
    areaRounded.height = Math.ceil areaRounded.height
    areaRounded

  textLayer: (pageNumber) =>
    page = @_pages[pageNumber - 1]

    beginLayout: =>
      page.textSegmentsDone = false

    endLayout: =>
      page.textSegmentsDone = true

      @_enableHighligts pageNumber

    appendText: (geom) =>
      page.textSegments.push PDFJS.pdfTextSegment page.textContent, page.textSegments.length, geom

  imageLayer: (pageNumber) =>
    page = @_pages[pageNumber - 1]

    beginLayout: =>
      page.imageLayerDone = false

    endLayout: =>
      page.imageLayerDone = true

      @_enableHighligts pageNumber

    appendImage: (geom) =>
      page.imageSegments.push _.pick(geom, 'left', 'top', 'width', 'height')

  # For debugging: draw divs for all segments
  _showSegments: (pageNumber) =>
    page = @_pages[pageNumber - 1]
    $displayPage = $("#display-page-#{ pageNumber }")

    for segment in page.textSegments
      $displayPage.append(
        $('<div/>').addClass('segment text-segment').css _.pick(segment, 'left', 'top', 'width', 'height')
      )

    for segment in page.imageSegments
      $displayPage.append(
        $('<div/>').addClass('segment image-segment').css  _.pick(segment, 'left', 'top', 'width', 'height')
      )

  _distance: (position, area) =>
    distanceXLeft = position.left - area.left
    distanceXRight = position.left - (area.left + area.width)

    distanceYTop = position.top - area.top
    distanceYBottom = position.top - (area.top + area.height)

    distanceX = if Math.abs(distanceXLeft) < Math.abs(distanceXRight) then distanceXLeft else distanceXRight
    if position.left > area.left and position.left < area.left + area.width
      distanceX = 0

    distanceY = if Math.abs(distanceYTop) < Math.abs(distanceYBottom) then distanceYTop else distanceYBottom
    if position.top > area.top and position.top < area.top + area.height
      distanceY = 0

    distanceX * distanceX + distanceY * distanceY

  _findClosestPage: (position) =>
    $closestCanvas = null
    closestPageNumber = -1
    closestDistance = Number.MAX_VALUE

    $('.display-page canvas').each (i, canvas) =>
      $canvas = $(canvas)
      pageNumber = $canvas.data 'page-number'

      return unless @_pages[pageNumber - 1]?.highlightsEnabled

      offset = $canvas.offset()
      distance = @_distance position,
        left: offset.left
        top: offset.top
        width: $canvas.width()
        height: $canvas.height()
      if distance < closestDistance
        $closestCanvas = $canvas
        closestPageNumber = pageNumber
        closestDistance = distance

    assert.notEqual closestPageNumber, -1
    assert $closestCanvas

    [$closestCanvas, closestPageNumber]

  _findClosestSegment: (pageNumber, position) =>
    page = @_pages[pageNumber - 1]

    closestSegmentIndex = -1
    closestDistance = Number.MAX_VALUE

    for segment, i in page.textSegments
      distance = @_distance position, segment
      if distance < closestDistance
        closestSegmentIndex = i
        closestDistance = distance

    closestSegmentIndex

  _normalizeActiveHighlightStartEnd: =>
    if @_activeHighlightStart.pageNumber < @_activeHighlightEnd.pageNumber
      # We don't have to do anything
      return [@_activeHighlightStart, @_activeHighlightEnd]
    else if @_activeHighlightStart.pageNumber > @_activeHighlightEnd.pageNumber
      # We just swap
      return [@_activeHighlightEnd, @_activeHighlightStart]

    # Start and end are on the same page

    if @_activeHighlightStart.index < @_activeHighlightEnd.index
      # We don't have to do anything
      return [@_activeHighlightStart, @_activeHighlightEnd]
    else if @_activeHighlightStart.index > @_activeHighlightEnd.index
      # We just swap
      return [@_activeHighlightEnd, @_activeHighlightStart]

    # Start and end are in the same segment, we prefer the left point (and top)

    # TODO: What about right-to-left texts? Or top-down texts?
    if @_activeHighlightStart.left < @_activeHighlightEnd.left
      return [@_activeHighlightStart, @_activeHighlightEnd]
    else if @_activeHighlightStart.left > @_activeHighlightEnd.left
      return [@_activeHighlightEnd, @_activeHighlightStart]

    # Left coordinates are equal, we prefer top one

    if @_activeHighlightStart.top < @_activeHighlightEnd.top
      return [@_activeHighlightStart, @_activeHighlightEnd]
    else
      return [@_activeHighlightEnd, @_activeHighlightStart]

  _hideActiveHiglight: =>
    $(".display-page .highlight").remove()

  _showActiveHighlight: =>
    # TODO: It is costy to first hide (remove) everything and the reshow (add), we should reuse things if we can
    @_hideActiveHiglight()

    assert @_activeHighlightStart
    assert @_activeHighlightEnd

    [activeHighlightStart, activeHighlightEnd] = @_normalizeActiveHighlightStartEnd()

    if activeHighlightStart.pageNumber is activeHighlightEnd.pageNumber
      $displayPage = $("#display-page-#{ activeHighlightStart.pageNumber }")

      textSegments = @_pages[activeHighlightStart.pageNumber - 1].textSegments
      for segment in textSegments[activeHighlightStart.index..activeHighlightEnd.index]
        $displayPage.append(
          $('<div/>').addClass('highlight').css _.pick(segment, 'left', 'top', 'width', 'height')
        )
    else
      # Show for the first page

      $displayPage = $("#display-page-#{ activeHighlightStart.pageNumber }")

      textSegments = @_pages[activeHighlightStart.pageNumber - 1].textSegments
      for segment in textSegments[activeHighlightStart.index...textSegments.length] # Exclusive range (...) here instead of inclusive (..)
        $displayPage.append(
          $('<div/>').addClass('highlight').css _.pick(segment, 'left', 'top', 'width', 'height')
        )

      # Show intermediate pages

      for page in @_pages[activeHighlightStart.pageNumber...(activeHighlightEnd.pageNumber - 1)] # Range without the first and the last pages
        continue unless page?.highlightsEnabled

        $displayPage = $("#display-page-#{ page.pageNumber }")

        for segment in page.textSegments
          $displayPage.append(
            $('<div/>').addClass('highlight').css _.pick(segment, 'left', 'top', 'width', 'height')
          )

      # Show for the last page

      $displayPage = $("#display-page-#{ activeHighlightEnd.pageNumber }")

      textSegments = @_pages[activeHighlightEnd.pageNumber - 1].textSegments
      for segment in textSegments[0..activeHighlightEnd.index] # Inclusive range (..) here
        $displayPage.append(
          $('<div/>').addClass('highlight').css _.pick(segment, 'left', 'top', 'width', 'height')
        )

  _openActiveHighlight: =>
    # TODO: Implement

  _closeActiveHighlight: =>
    @_hideActiveHiglight()

    # TODO: Implement

  _enableHighligts: (pageNumber) =>
    page = @_pages[pageNumber - 1]

    return unless page.textSegmentsDone and page.imageLayerDone

    # Highlights already enabled for this page
    return if page.highlightsEnabled
    page.highlightsEnabled = true

    # For debugging
    #@_showSegments pageNumber

    $canvas = $("#display-page-#{ pageNumber } canvas")

    $canvas.on 'mousedown', (e) =>
      offset = $canvas.offset()
      left = e.pageX - offset.left
      top = e.pageY - offset.top
      index = @_findClosestSegment pageNumber,
        left: left
        top: top

      return if index is -1

      @_activeHighlightStart =
        pageNumber: pageNumber
        left: left
        top: top
        index: index

      $(document).on 'mousemove.highlighting', (e) =>
        assert @_activeHighlightStart

        [$c, pn] = @_findClosestPage
          left: e.pageX
          top: e.pageY
        offset = $c.offset()
        left = e.pageX - offset.left
        top = e.pageY - offset.top
        index = @_findClosestSegment pn,
          left: left
          top: top

        return if index is -1

        @_activeHighlightEnd =
          pageNumber: pn
          left: left
          top: top
          index: index

        @_showActiveHighlight()

      $(document).on 'mouseup.highlighting', (e) =>
        $(document).off '.highlighting'

        assert @_activeHighlightStart

        [$c, pn] = @_findClosestPage
          left: e.pageX
          top: e.pageY
        offset = $c.offset()
        left = e.pageX - offset.left
        top = e.pageY - offset.top
        index = @_findClosestSegment pn,
          left: left
          top: top

        if index is -1
          @_closeHighlight()
          return

        @_activeHighlightEnd =
          pageNumber: pn
          left: left
          top: top
          index: index

        if @_activeHighlightStart.left is @_activeHighlightEnd.left and @_activeHighlightStart.top is @_activeHighlightEnd.top
          # Mouse went up at the same location that it started, we just cleanup
          @_closeActiveHighlight()
        else
          @_openActiveHighlight()

        @_activeHighlightStart = null
        @_activeHighlightEnd = null
