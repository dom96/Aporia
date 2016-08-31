#
#
#            Aporia - Nim IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, glib2, gtksourceview, gdk2, pegs, re, strutils, unicode
import utils, CustomStatusBar

{.push callConv:cdecl.}

const
  NonHighlightChars = {'=', '+', '-', '*', '/', '<', '>', '@', '$', '~', '&',
                       '%', '|', '!', '?', '^', '.', ':', '\\', '(', ')',
                       '{', '}', '`', '[', ']', ',', ';'} +
                      strutils.Whitespace + {'\t'}

proc newHighlightAll*(text: string, forSearch: bool, idleID: int32): THighlightAll =
  result.isHighlighted = true
  result.text = text
  result.forSearch = forSearch
  result.idleID = idleID

proc newNoHighlightAll*(): THighlightAll =
  result.isHighlighted = false
  result.text = ""

proc canBeHighlighted(term: string): bool =
  ## Determines whether ``term`` should be highlighted.
  result = true
  if term.len < 2: return false
  let c = term[0]
  if c in NonHighlightChars: return false
  for i in 1..term.len-1:
    if term[i] in NonHighlightChars: return false
  
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

proc findRePeg(win: var utils.MainWin, forward: bool, startIter: PTextIter,
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
  var isRegex = win.autoSettings.search == SearchRegex
  var reOptions = {reExtended, reStudy}
  var newPattern = pattern
  if mode == SearchStyleInsens:
    reOptions = reOptions + {reIgnoreCase}
    newPattern = styleInsensitive(newPattern)
    isRegex = true  
    
  var matches: array[0..re.MaxSubpatterns, string]
  var match = (-1, 0)
  if forward:
    match = findBoundsGen($text, newPattern, isRegex, reOptions)
  else: # Backward search.
    # Loop until there is no match to find the last match.
    # Yeah. I know inefficient, but that's the only way I know how to do this.
    var newMatch = (-1, 0)
    while true:
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
          
    return (startMatch, endMatch, true)
  else:
    if win.autoSettings.wrapAround and not wrappedAround:
      if forward:
        # We are at the end. Restart at the beginning.
        buffer.getStartIter(addr(startMatch))
      else:
        # We are at the beginning. Restart from the end.
        buffer.getEndIter(addr(startMatch))
      return findRePeg(win, forward, addr(startMatch), buffer, pattern, mode, true)
  
    return (startMatch, endMatch, false)

proc findSimple(win: var utils.MainWin, forward: bool, startIter: PTextIter,
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
    if win.autoSettings.wrapAround and not wrappedAround:
      if forward:
        # We are at the end. Restart from beginning.
        buffer.getStartIter(addr(startMatch))
      else:
        # We are at the beginning. Restart from end.
        buffer.getEndIter(addr(startMatch))
      return findSimple(win, forward, addr(startMatch), buffer, pattern, mode, true)
    
  return (startMatch, endMatch, matchFound.bool)

iterator findTerm(win: var utils.MainWin, buffer: PSourceBuffer, term: string,
    mode: TSearchEnum): tuple[startMatch, endMatch: TTextIter] {.closure.} =
  const CurrentSearchPosName = "CurrentSearchPosMark"
  var searchPosMark = buffer.getMark(CurrentSearchPosName)
  var startIter: TTextIter
  buffer.getStartIter(addr(startIter))
  if searchPosMark == nil:
    searchPosMark = buffer.createMark(CurrentSearchPosName, addr(startIter), false)
  else:
    buffer.moveMark(searchPosMark, addr(startIter))
  
  var found = true
  var startSearchIter: TTextIter
  var startMatch, endMatch: TTextIter
  var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
  while found:
    buffer.getIterAtMark(addr(startSearchIter), searchPosMark)
    case mode
    of SearchCaseInsens, SearchCaseSens:
      ret = findSimple(win, true, addr(startSearchIter), buffer, $term, mode, wrappedAround = true)
    of SearchRegex, SearchPeg, SearchStyleInsens:
      ret = findRePeg(win, true, addr(startSearchIter), buffer, $term, mode, wrappedAround = true)
    startMatch = ret[0]
    endMatch = ret[1]
    found = ret[2]
    
    if not found: break
    buffer.moveMark(searchPosMark, addr(endMatch))
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
  
  stopHighlightAll(w, forSearch)
  
  if not forSearch:
    if not canBeHighlighted(term):
      return
  
  echod("Highlighting in ", mode)
  
  type 
    TIdleParam = object
      win: utils.MainWin
      buffer: PSourceBuffer
      term: string 
      mode: TSearchEnum
      findIter: iterator (win: var utils.MainWin, buffer: PSourceBuffer, 
                          term: string, mode: TSearchEnum): 
                        tuple[startMatch, endMatch: TTextIter] {.closure.}
    
  var idleParam: ref TIdleParam; new(idleParam)
  idleParam.win = w
  idleParam.buffer = w.tabs[current].buffer
  idleParam.term = term
  idleParam.mode = mode
  idleParam.findIter = findTerm
  GCRef(idleParam) # Make sure `idleParam` is not deallocated by the GC.
  
  discard w.tabs[current].buffer.createTag(HighlightTagName,
                                           "background", "#F28A13",
                                           "foreground", "#ffffff", nil)
  
  proc idleHighlightAll(param: ptr TIdleParam): gboolean {.cdecl.} =
    result = true
    var (startMatch, endMatch) =
        param.findIter(param.win, param.buffer, param.term, param.mode)
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

proc findText*(win: var utils.MainWin, forward: bool) =
  # This proc gets called when the 'Next' or 'Prev' buttons
  # are pressed, forward is a boolean which is
  # true for Next and false for Previous
  var pattern = $(getText(win.findEntry)) # Text to search for.

  # Get the current tab
  var currentTab = win.sourceViewTabs.getCurrentPage()
  if win.globalSettings.searchHighlightAll:
    highlightAll(win, pattern, true, win.autoSettings.search)
  else:
    # Stop it from highlighting due to selection.
    win.tabs[currentTab].highlighted = newHighlightAll("", true, -1)
  
  # Get the position where the cursor is,
  # Search based on that.
  var startSel, endSel: TTextIter
  discard win.tabs[currentTab].buffer.getSelectionBounds(
      addr(startsel), addr(endsel))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean = false
  
  var buffer = win.tabs[currentTab].buffer
  var mode = win.autoSettings.search
  
  case mode
  of SearchCaseInsens, SearchCaseSens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findSimple(win, forward, addr(endSel), buffer, pattern, mode)
    else:
      ret = findSimple(win, forward, addr(startSel), buffer, pattern, mode)
    startMatch = ret[0]
    endMatch = ret[1]
    matchFound = ret[2]
  
  of SearchRegex, SearchPeg, SearchStyleInsens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findRePeg(win, forward, addr(endSel), buffer, pattern, mode)
    else:
      ret = findRePeg(win, forward, addr(startSel), buffer, pattern, mode)
    startMatch = ret[0]
    endMatch = ret[1]
    matchFound = ret[2]
  
  if matchFound:
    buffer.moveMarkByName("insert", addr(startMatch))
    buffer.moveMarkByName("selection_bound", addr(endMatch))
    discard PTextView(win.tabs[currentTab].sourceView).
        scrollToIter(addr(startMatch), 0.2, false, 0.0, 0.0)
    
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
    var red: gdk2.TColor
    discard colorParse("#ff6666", addr(red))
    var white: gdk2.TColor
    discard colorParse("white", addr(white))
    
    win.findEntry.modifyBase(STATE_NORMAL, addr(red))
    win.findEntry.modifyText(STATE_NORMAL, addr(white))
    
    # Set the status bar
    win.statusbar.setTemp("Match not found.", UrgError, 5000)
    
proc replaceAll*(win: var utils.MainWin, find, replace: cstring): int =
  # gedit-document.c, gedit_document_replace_all
  var count = 0
  var startMatch, endMatch: TTextIter
  var replaceLen = len(replace)

  # Get the current tab
  var currentTab = win.sourceViewTabs.getCurrentPage()
  assert(currentTab <% win.tabs.len())

  var buffer = win.tabs[currentTab].buffer
  
  var iter: TTextIter
  buffer.getStartIter(addr(iter))

  # Check how many occurrences there are of the search string.
  var startIter: TTextIter
  buffer.getStartIter(addr(startIter))
  var endIter: TTextIter
  buffer.getEndIter(addr(endIter))
  var text = $buffer.getText(addr(startIter), addr(endIter), false)
  var maxCount : int
  if win.autoSettings.search == SearchCaseInsens or win.autoSettings.search == SearchStyleInsens:
    maxCount = count(unicode.toLower(text), unicode.toLower($find))
  else:
    maxCount = count(text, $find)
  
  # Disable bracket matching and status bar updates - for a speed up
  win.tempStuff.stopSBUpdates = true
  buffer.setHighlightMatchingBrackets(false)
  
  buffer.beginUserAction()
  
  # Replace all
  var found = true
  while found and count <= maxCount:
    case win.autoSettings.search
    of SearchCaseInsens, SearchCaseSens:
      var options = getSearchOptions(win.autoSettings.search)
      found = gtksourceview.forwardSearch(addr(iter), find, 
          options, addr(startMatch), addr(endMatch), nil)
    of SearchRegex, SearchPeg, SearchStyleInsens:
      var ret = findRePeg(win, true, addr(iter), buffer, $find,
                          win.autoSettings.search)
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
  win.tempStuff.stopSBUpdates = false
  buffer.setHighlightMatchingBrackets(win.globalSettings.highlightMatchingBrackets)

  return count
  
  
  
  
  
