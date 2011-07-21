#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2010 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, glib2, gtksourceview, gdk2, pegs, re
import types

{.push callConv:cdecl.}

var
  win*: ptr types.MainWin

proc getSearchOptions(): TTextSearchFlags =
  if win.settings.search == "caseinsens":
    result = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY or TEXT_SEARCH_CASE_INSENSITIVE
  elif win.settings.search == "casesens":
    result = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY

proc findRegex*(pattern: TRegex, forward: bool, startIter: PTextIter, 
                buffer: PTextBuffer): 
    tuple[startMatch, endMatch: TTextIter, found: bool] =
  var text: cstring
  var iter: TTextIter
  if forward:
    buffer.getEndIter(addr(iter))
    text = startIter.getText(addr(iter))
  else:
    buffer.getStartIter(addr(iter))
    text = addr(iter).getText(startIter)
    
  var matches: array[0..re.MaxSubpatterns, string]
  var match = find($text, pattern, matches)
  var startMatch, endMatch: TTextIter
  
  echo(match, " ", matches.len())
  if match != -1:
    if forward:
      buffer.getIterAtOffset(addr(startMatch), startIter.getOffset() + match)
      buffer.getIterAtOffset(addr(endMatch), startIter.getOffset() + match + 
          matches[0].len())
    else:
      buffer.getIterAtOffset(addr(startMatch), addr(iter).getOffset() + match)
      buffer.getIterAtOffset(addr(endMatch), addr(iter).getOffset() + match +
          matches[0].len())
          
    return (startMatch, endMatch, True)
  else:
    return (startMatch, endMatch, False)
  

proc findText*(forward: bool) =
  # This proc get's called when the 'Next' or 'Prev' buttons
  # are pressed, forward is a boolean which is
  # True for Next and False for Previous
  var text = getText(win.findEntry)

  # TODO: regex, pegs, style insensitive searching

  # Get the current tab
  var currentTab = win.SourceViewTabs.getCurrentPage()
  
  # Get the position where the cursor is
  # Search based on that
  var startSel, endSel: TTextIter
  discard win.Tabs[currentTab].buffer.getSelectionBounds(
      addr(startsel), addr(endsel))
  
  var startMatch, endMatch: TTextIter
  var matchFound: gboolean
  
  var buffer = win.Tabs[currentTab].buffer
  
  if win.settings.search == "caseinsens" or win.settings.search == "casesens":
    var options = getSearchOptions()
    if forward:
      matchFound = gtksourceview.forwardSearch(addr(endSel), text, 
          options, addr(startMatch), addr(endMatch), nil)
    else:
      matchFound = gtksourceview.backwardSearch(addr(startSel), text, 
          options, addr(startMatch), addr(endMatch), nil)
  else:
    if win.settings.search == "regex":
      var ret = findRegex(re("(" & $text & ")"), forward, addr(endSel), buffer)
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
    assert(colorParse("#ff6666", addr(red)) == 1)
    var white: Gdk2.TColor
    assert(colorParse("white", addr(white)) == 1)
    
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
  
  
