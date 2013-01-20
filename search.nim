#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, glib2, gtksourceview, gdk2, pegs, re, strutils
import utils, CustomStatusBar

{.push callConv:cdecl.}

var
  win*: ptr utils.MainWin

proc newHighlightAll*(text: string, forSearch: bool, idleID: int32): THighlightAll =
  result.isHighlighted = true
  result.text = text
  result.forSearch = forSearch
  result.idleID = idleID

proc newNoHighlightAll*(): THighlightAll =
  result.isHighlighted = false
  result.text = ""

proc getSearchOptions(mode: TSearchEnum): TTextSearchFlags =
  case mode
  of SearchCaseInsens:
    result = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY or TEXT_SEARCH_CASE_INSENSITIVE
  of SearchCaseSens:
    result = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY
  else:
    assert(false)

proc styleInsensitive(s: string): string = 
  template addx: stmt = 
    result.add(s[i])
    inc(i)
  result = ""
  var i = 0
  var brackets = 0
  while i < s.len:
    case s[i]
    of 'A'..'Z', 'a'..'z', '0'..'9': 
      addx()
      result.add("_?")
    of '_': inc(i) # Don't add this.
    of '*', '?', '\\', '#', '$', '^', '(', ')', '+',
       '|', '[', ']', '{', '}', '.':
      result.add('\\')
      addx()
    of ' ':
      result.add("\\s")
      inc(i)
    of '\t':
      result.add("\\t")
      inc(i)
    else: addx()

proc findBoundsGen(text, pattern: string,
                   rePattern: bool, reOptions: system.set[TRegExFlag],
                   start: int = 0): 
    tuple[first: int, last: int] =
  if rePattern:
    try:
      result = re.findBounds(text, re(pattern, reOptions), start)
    except EInvalidRegex:
      result = (-1, 0)
  else:
    var matches: array[0..re.MaxSubpatterns-1, string]
    try:
      result = pegs.findBounds(text, peg(pattern), matches, start)
    except EInvalidPeg, EAssertionFailed:
      result = (-1, 0)

  if result[0] == -1 or result[1] == -1: return (-1, 0)

proc findRePeg(forward: bool, startIter: PTextIter,
               buffer: PTextBuffer, pattern: string, mode: TSearchEnum,
               wrappedAround = false): 
    tuple[startMatch, endMatch: TTextIter, found: bool] =
  var text: cstring
  var iter: TTextIter # If forward then this points to the end
                      # otherwise to the beginning.
  if forward:
    buffer.getEndIter(addr(iter))
    text = startIter.getText(addr(iter))
  else:
    buffer.getStartIter(addr(iter))
    text = getText(addr(iter), startIter)
  
  # Set up some options.
  var isRegex = win.settings.search == SearchRegex
  var reOptions = {reExtended, reStudy}
  var newPattern = pattern
  if mode == SearchStyleInsens:
    reOptions = reOptions + {reIgnoreCase}
    newPattern = styleInsensitive(newPattern)
    isRegex = True  
    
  var matches: array[0..re.MaxSubpatterns, string]
  var match = (-1, 0)
  if forward:
    match = findBoundsGen($text, newPattern, isRegex, reOptions)
  else: # Backward search.
    # Loop until there is no match to find the last match.
    # Yeah. I know inefficient, but that's the only way I know how to do this.
    var newMatch = (-1, 0)
    while True:
      newMatch = findBoundsGen($text, newPattern, isRegex, reOptions, match[1])
      if newMatch != (-1, 0): match = newMatch
      else: break

  var startMatch, endMatch: TTextIter
  
  if match != (-1, 0):
    if forward:
      buffer.getIterAtOffset(addr(startMatch), startIter.getOffset() + int32(match[0]))
      buffer.getIterAtOffset(addr(endMatch), startIter.getOffset() + 
          int32(match[1]) + 1)
    else:
      buffer.getIterAtOffset(addr startMatch, getOffset(addr iter) + int32(match[0]))
      buffer.getIterAtOffset(addr(endMatch), getOffset(addr(iter)) +
          int32(match[1]) + 1)
          
    return (startMatch, endMatch, True)
  else:
    if win.settings.wrapAround and not wrappedAround:
      if forward:
        # We are at the end. Restart at the beginning.
        buffer.getStartIter(addr(startMatch))
      else:
        # We are at the beginning. Restart from the end.
        buffer.getEndIter(addr(startMatch))
      return findRePeg(forward, addr(startMatch), buffer, pattern, mode, true)
  
    return (startMatch, endMatch, False)

proc findSimple(forward: bool, startIter: PTextIter,
                buffer: PTextBuffer, pattern: string, mode: TSearchEnum,
                wrappedAround = false):
                tuple[startMatch, endMatch: TTextIter, found: bool] =
  var options = getSearchOptions(mode)
  var matchFound: gboolean = false
  var startMatch, endMatch: TTextIter
  if forward:
    matchFound = gtksourceview.forwardSearch(startIter, pattern, 
        options, addr(startMatch), addr(endMatch), nil)
  else:
    matchFound = gtksourceview.backwardSearch(startIter, pattern, 
        options, addr(startMatch), addr(endMatch), nil)

  if not matchFound:
    if win.settings.wrapAround and not wrappedAround:
      if forward:
        # We are at the end. Restart from beginning.
        buffer.getStartIter(addr(startMatch))
      else:
        # We are at the beginning. Restart from end.
        buffer.getEndIter(addr(startMatch))
      return findSimple(forward, addr(startMatch), buffer, pattern, mode, true)
    
  return (startMatch, endMatch, matchFound)

iterator findTerm(buffer: PSourceBuffer, term: string, mode: TSearchEnum): tuple[startMatch, endMatch: TTextIter] {.closure.} =
  var iter: TTextIter
  buffer.getStartIter(addr(iter))
  
  var found = True
  var startMatch, endMatch: TTextIter
  var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
  while found:
    case mode
    of SearchCaseInsens, SearchCaseSens:
      ret = findSimple(true, addr(iter), buffer, $term, mode, wrappedAround = true)
    of SearchRegex, SearchPeg, SearchStyleInsens:
      ret = findRePeg(true, addr(iter), buffer, $term, mode, wrappedAround = true)
    startMatch = ret[0]
    endMatch = ret[1]
    found = ret[2]
    
    iter = endMatch
    if not found: break
    yield (startMatch, endMatch)

const HighlightTagName = "search-highlight-all"

proc stopHighlightAll*(w: var MainWin, forSearch: bool) =
  ## Resets the terms that are highlighted in the current tab, or if all terms
  ## haven't yet been found cancels the idle proc job (resets the already
  ## highlighted terms)
  let current = getCurrentTab(w)
  let t = w.tabs[current]
  if t.highlighted.isHighlighted:
    if not forSearch and w.tabs[current].highlighted.forSearch: return
    
    discard gSourceRemove(w.tabs[current].highlighted.idleID)
    var startIter, endIter: TTextIter
    w.tabs[current].buffer.getStartIter(addr(startIter))
    w.tabs[current].buffer.getEndIter(addr(endIter))
    w.tabs[current].buffer.removeTagByName(HighlightTagName, addr(startIter), addr(endIter))
    doAssert w.tabs[current].buffer.removeTag(HighlightTagName)
    w.tabs[current].highlighted = newNoHighlightAll()

proc highlightAll*(w: var MainWin, term: string, forSearch: bool, mode = SearchCaseInsens) =
  ## Asynchronously finds all occurrences of ``term`` in the current tab, and
  ## highlights them.
  var current = getCurrentTab(w)
  if w.tabs[current].highlighted.isHighlighted:
    if not forSearch and w.tabs[current].highlighted.forSearch:
      return 
  
  if w.tabs[current].highlighted.text == term:
    ## This is already highlighted.
    return
  
  echod("Highlighting in ", mode)
  stopHighlightAll(w, forSearch)
  
  type 
    TIdleParam = object
      buffer: PSourceBuffer
      term: string 
      mode: TSearchEnum
      findIter: iterator (buffer: PSourceBuffer, 
                          term: string, mode: TSearchEnum): 
                        tuple[startMatch, endMatch: TTextIter] {.closure.}
    
  var idleParam: ref TIdleParam; new(idleParam)
  idleParam.buffer = w.tabs[current].buffer
  idleParam.term = term
  idleParam.mode = mode
  idleParam.findIter = findTerm
  GCRef(idleParam) # Make sure `idleParam` is not deallocated by the GC.
  
  discard w.tabs[current].buffer.createTag(HighlightTagName,
                                           "background", "#F28A13",
                                           "foreground", "#ffffff", nil)
  
  proc idleHighlightAll(param: ptr TIdleParam): bool {.cdecl.} =
    result = true
    var (startMatch, endMatch) = param.findIter(param.buffer, param.term, param.mode)
    if param.findIter.finished: return false
    param.buffer.applyTagByName(HighlightTagName, addr startMatch, addr endMatch)
    
  proc idleHighlightAllRemove(param: ptr TIdleParam) {.cdecl.} =
    echod("Unreffing highlight.")
    GCUnref(cast[ref TIdleParam](param))
    GC_fullCollect()
  
  let idleID =
      gIdleAddFull(GPRIORITY_DEFAULT_IDLE, idleHighlightAll,
                   cast[ptr TIdleParam](idleParam), idleHighlightAllRemove)
  w.tabs[current].highlighted = newHighlightAll(term, forSearch, idleID)

proc findText*(forward: bool) =
  # This proc gets called when the 'Next' or 'Prev' buttons
  # are pressed, forward is a boolean which is
  # True for Next and False for Previous
  var pattern = $(getText(win.findEntry)) # Text to search for.

  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  if win.settings.searchHighlightAll:
    highlightAll(win[], pattern, true, win.settings.search)
  else:
    # Stop it from highlighting due to selection.
    win.tabs[currentTab].highlighted = newHighlightAll("", true, -1)
  
  # Get the position where the cursor is,
  # Search based on that.
  var startSel, endSel: TTextIter
  discard win.Tabs[currentTab].buffer.getSelectionBounds(
      addr(startsel), addr(endsel))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean = false
  
  var buffer = win.Tabs[currentTab].buffer
  var mode = win.settings.search
  
  case mode
  of SearchCaseInsens, SearchCaseSens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findSimple(forward, addr(endSel), buffer, pattern, mode)
    else:
      ret = findSimple(forward, addr(startSel), buffer, pattern, mode)
    startMatch = ret[0]
    endMatch = ret[1]
    matchFound = ret[2]
  
  of SearchRegex, SearchPeg, SearchStyleInsens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findRePeg(forward, addr(endSel), buffer, pattern, mode)
    else:
      ret = findRePeg(forward, addr(startSel), buffer, pattern, mode)
    startMatch = ret[0]
    endMatch = ret[1]
    matchFound = ret[2]
  
  if matchFound:
    buffer.moveMarkByName("insert", addr(startMatch))
    buffer.moveMarkByName("selection_bound", addr(endMatch))
    discard PTextView(win.Tabs[currentTab].sourceView).
        scrollToIter(addr(startMatch), 0.2, False, 0.0, 0.0)
    
    # Reset the findEntry color
    win.findEntry.modifyBase(STATE_NORMAL, nil)
    win.findEntry.modifyText(STATE_NORMAL, nil)
    
    # Reset statusbar
    win.statusbar.restorePrevious()
    
    let compared = compare(addr(startSel), addr(endMatch))
    if forward:
      if compared > 0:
        win.statusbar.setTemp("Wrapped around end of file", UrgNormal, 5000)
    else:
      if compared < 0:
        win.statusbar.setTemp("Wrapped around end of file", UrgNormal, 5000)
  else:
    # Change the findEntry color to red
    var red: Gdk2.TColor
    discard colorParse("#ff6666", addr(red))
    var white: Gdk2.TColor
    discard colorParse("white", addr(white))
    
    win.findEntry.modifyBase(STATE_NORMAL, addr(red))
    win.findEntry.modifyText(STATE_NORMAL, addr(white))
    
    # Set the status bar
    win.statusbar.setTemp("Match not found.", UrgError, 5000)
    
proc replaceAll*(find, replace: cstring): Int =
  # gedit-document.c, gedit_document_replace_all
  var count = 0
  var startMatch, endMatch: TTextIter
  var replaceLen = len(replace)

  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  assert(currentTab <% win.Tabs.len())

  var buffer = win.Tabs[currentTab].buffer
  
  var iter: TTextIter
  buffer.getStartIter(addr(iter))
  
  # Disable bracket matching and status bar updates - for a speed up
  win.tempStuff.stopSBUpdates = True
  buffer.setHighlightMatchingBrackets(False)
  
  buffer.beginUserAction()
  
  # Replace all
  var found = True
  while found:
    case win.settings.search
    of SearchCaseInsens, SearchCaseSens:
      var options = getSearchOptions(win.settings.search)
      found = gtksourceview.forwardSearch(addr(iter), find, 
          options, addr(startMatch), addr(endMatch), nil)
    of SearchRegex, SearchPeg, SearchStyleInsens:
      var ret = findRePeg(true, addr(iter), buffer, $find, win.settings.search)
      startMatch = ret[0]
      endMatch = ret[1]
      found = ret[2]
  
    if found:
      inc(count)
      gtk2.delete(buffer, addr(startMatch), addr(endMatch))
      buffer.insert(addr(startMatch), replace, int32(replaceLen))
  
      iter = startMatch
  
  buffer.endUserAction()
  
  # Re-Enable bracket matching and status bar updates
  win.tempStuff.stopSBUpdates = False
  buffer.setHighlightMatchingBrackets(win.settings.highlightMatchingBrackets)

  return count
  
  
  
  
  
