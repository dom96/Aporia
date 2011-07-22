#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, glib2, gtksourceview, gdk2, pegs, re, strutils
import types

{.push callConv:cdecl.}

var
  win*: ptr types.MainWin

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
      if brackets == 0: result.add("_?")
    of '_':
      addx()
      result.add('?')
    of '[':
      addx()
      inc(brackets)
    of ']':
      addx()
      if brackets > 0: dec(brackets)
    of '?':
      addx()
      if s[i] == '<':
        addx()
        while s[i] != '>' and s[i] != '\0': addx()
    of '\\':
      addx()
      if s[i] in strutils.digits: 
        while s[i] in strutils.digits: addx()
      else:
        addx()
    else: addx()

proc findBoundsGen(text, pattern: string,
                   rePattern: bool, reOptions: system.set[TRegExFlag],
                   start: int = 0): 
    tuple[first: int, last: int] =
  
  if rePattern:
    return re.findBounds(text, re(pattern, reOptions), start)
  else:
    var matches: array[0..re.MaxSubpatterns-1, string]
    return pegs.findBounds(text, peg(pattern), matches, start)

proc findRePeg(forward: bool, startIter: PTextIter, buffer: PTextBuffer,
               pattern: string, rePattern: bool,
               reOptions = {reExtended, reStudy}): 
    tuple[startMatch, endMatch: TTextIter, found: bool] =
  # TODO: Clean this function up. It's way too cluttered. ( Too many params )
  var text: cstring
  var iter: TTextIter # If forward then this points to the end
                      # otherwise to the beginning.
  if forward:
    buffer.getEndIter(addr(iter))
    text = startIter.getText(addr(iter))
  else:
    buffer.getStartIter(addr(iter))
    text = addr(iter).getText(startIter)
    
  var matches: array[0..re.MaxSubpatterns, string]
  var match = (-1, 0)
  if forward:
    match = findBoundsGen($text, pattern, rePattern, reOptions)
  else: # Backward search.
    # Loop until there is no match to find the last match.
    # Yeah. I know inefficient, but that's the only way I know how to do this.
    var newMatch = (-1, 0)
    while True:
      newMatch = findBoundsGen($text, pattern, rePattern, reOptions, match[1]+1)
      if newMatch != (-1, 0): match = newMatch
      else: break

  var startMatch, endMatch: TTextIter
  
  if match != (-1, 0):
    if forward:
      buffer.getIterAtOffset(addr(startMatch), startIter.getOffset() + match[0])
      buffer.getIterAtOffset(addr(endMatch), startIter.getOffset() + 
          match[1] + 1)
    else:
      buffer.getIterAtOffset(addr(startMatch), addr(iter).getOffset() + match[0])
      buffer.getIterAtOffset(addr(endMatch), addr(iter).getOffset() +
          match[1] + 1)
          
    return (startMatch, endMatch, True)
  else:
    return (startMatch, endMatch, False)
  
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
  var matchFound: gboolean
  
  var buffer = win.Tabs[currentTab].buffer
  
  case win.settings.search
  of SearchCaseInsens, SearchCaseSens:
    var options = getSearchOptions()
    if forward:
      matchFound = gtksourceview.forwardSearch(addr(endSel), pattern, 
          options, addr(startMatch), addr(endMatch), nil)
    else:
      matchFound = gtksourceview.backwardSearch(addr(startSel), pattern, 
          options, addr(startMatch), addr(endMatch), nil)
  
  of SearchRegex, SearchPeg, SearchStyleInsens:
    var ret: tuple[startMatch, endMatch: TTextIter, found: bool]
    var regex = win.settings.search == SearchRegex
    var reOptions = {reExtended, reStudy}
    if win.settings.search == SearchStyleInsens:
      # Style insensitive search. We use case insensitive regex here.
      regex = True
      pattern = styleInsensitive(pattern)
      reOptions = reOptions + {reIgnoreCase}
    if forward:
      ret = findRePeg(forward, addr(endSel), buffer, pattern, regex, reOptions)
    else:
      ret = findRePeg(forward, addr(startSel), buffer, pattern, regex, reOptions)
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
  var options = getSearchOptions()
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
  var found = False
  while found:
    found = gtksourceview.forwardSearch(addr(iter), find, 
        options, addr(startMatch), addr(endMatch), nil)
  
    if found:
      inc(count)
      buffer.delete(addr(startMatch), addr(endMatch))
      buffer.insert(addr(startMatch), replace, replaceLen)
  
      iter = startMatch
  
  buffer.endUserAction()
  
  # Re-Enable bracket matching and status bar updates
  win.tempStuff.stopSBUpdates = False
  buffer.setHighlightMatchingBrackets(win.settings.highlightMatchingBrackets)
  
  return count
  
  
