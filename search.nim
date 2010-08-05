import gtk2, glib2, gtksourceview, gdk2
import types
{.push callConv:cdecl.}

# yay, you can export variables!
var win*: ptr types.MainWin

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
  
  var options: TTextSearchFlags
  if win.settings.search == "caseinsens":
    options = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY or TEXT_SEARCH_CASE_INSENSITIVE
  else:
    options = TEXT_SEARCH_TEXT_ONLY or 
        TEXT_SEARCH_VISIBLE_ONLY
  
  if forward:
    matchFound = gtksourceview.forwardSearch(addr(endSel), text, 
        options, addr(startMatch), addr(endMatch), nil)
  else:
    matchFound = gtksourceview.backwardSearch(addr(startSel), text, 
        options, addr(startMatch), addr(endMatch), nil)
  
  if matchFound:
    win.Tabs[currentTab].buffer.moveMarkByName("insert", addr(startMatch))
    win.Tabs[currentTab].buffer.moveMarkByName("selection_bound", addr(endMatch))
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
