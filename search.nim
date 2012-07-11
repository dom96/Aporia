#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, glib2, gtksourceview, gdk2, pegs, re, strutils
import utils

{.push callConv:cdecl.}

var
  win*: ptr utils.MainWin

proc getSearchOptions(): TTextSearchFlags =
  case win.settings.search
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
               buffer: PTextBuffer, pattern: string, wrappedAround = false): 
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
  if win.settings.search == SearchStyleInsens:
    reOptions = reOptions + {reIgnoreCase}
    newPattern = styleInsensitive(newPattern)
    echo(newPattern)
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
      newMatch = findBoundsGen($text, newPattern, isRegex, reOptions, match[1]+1)
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
      return findRePeg(forward, addr(startMatch), buffer, pattern, true)
  
    return (startMatch, endMatch, False)

proc findSimple(forward: bool, startIter: PTextIter,
                buffer: PTextBuffer, pattern: string, wrappedAround = false):
                tuple[startMatch, endMatch: TTextIter, found: bool] =
  var options = getSearchOptions()
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
      return findSimple(forward, addr(startMatch), buffer, pattern, true)
    
  return (startMatch, endMatch, matchFound)

proc findText*(forward: bool) =
  # This proc gets called when the 'Next' or 'Prev' buttons
  # are pressed, forward is a boolean which is
  # True for Next and False for Previous
  var pattern = $(getText(win.findEntry)) # Text to search for.

  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  
  # Get the position where the cursor is,
  # Search based on that.
  var startSel, endSel: TTextIter
  discard win.Tabs[currentTab].buffer.getSelectionBounds(
      addr(startsel), addr(endsel))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean = false
  
  var buffer = win.Tabs[currentTab].buffer
  
  case win.settings.search
  of SearchCaseInsens, SearchCaseSens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findSimple(forward, addr(endSel), buffer, pattern)
    else:
      ret = findSimple(forward, addr(startSel), buffer, pattern)
    startMatch = ret[0]
    endMatch = ret[1]
    matchFound = ret[2]
  
  of SearchRegex, SearchPeg, SearchStyleInsens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    if forward:
      ret = findRePeg(forward, addr(endSel), buffer, pattern)
    else:
      ret = findRePeg(forward, addr(startSel), buffer, pattern)
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
  else:
    # Change the findEntry color to red
    var red: Gdk2.TColor
    discard colorParse("#ff6666", addr(red))
    var white: Gdk2.TColor
    discard colorParse("white", addr(white))
    
    win.findEntry.modifyBase(STATE_NORMAL, addr(red))
    win.findEntry.modifyText(STATE_NORMAL, addr(white))
    
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
      var options = getSearchOptions()
      found = gtksourceview.forwardSearch(addr(iter), find, 
          options, addr(startMatch), addr(endMatch), nil)
    of SearchRegex, SearchPeg, SearchStyleInsens:
      var ret = findRePeg(true, addr(iter), buffer, $find)
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
  
  
