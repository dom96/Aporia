## This module contains:
## * TShortcutKey: store a keyboard shortcut (key with modifiers)
## * StrToKey(): convert a string to a TShortcutKey
## * KeyToStr(): convert a TShortcutKey to a string

import tables, strutils, glib2

type
  TShortcutKey* = object
    keyval*: guint  
    state*: guint  

var
  keyLookupTable: TTable[guint, string]   # Contains all keys which are possible for shortcuts
  stateLookupTable: TTable[guint, string] # Contains all modifier key masks which are possible for shortcuts
    
proc StrToKey*(str: string): TShortcutKey =
  # Convert a string (e.g. "F1") to TShortcutKey
  Result.keyval = 0
  Result.state = 0
  var norm = normalize(str)
  var tokens = split(normalize(str), " + ")
  for token in tokens:
    var found = false
    for key, val in stateLookupTable:
      if token == normalize(val):
        Result.state = Result.state + key
        found = true
        break
    if not found:   
      for key, val in keyLookupTable:
        if token == normalize(val):
          Result.keyval = key
          break

proc KeyToStr*(key: TShortcutKey): string =
  # Convert a TShortcutKey to a string (e.g. "F1")
  var maskStr = ""
  for mask, stateStr in stateLookupTable:
    if (key.state and mask) == mask:
      maskStr.add(stateStr)
      maskStr.add(" + ")
  if keyLookupTable.hasKey(key.keyval):
    return maskStr & keyLookupTable[key.keyval]
  return ""
  
  
##### Initialize keyLookupTable #####  

keyLookupTable = initTable[guint, string]() 
# Basic characters
for i in 33..255:
  keyLookupTable[guint(i)] = toUpper($chr(i))
# Special keys
keyLookupTable[32] = "Space"
keyLookupTable[65105] = "Acute"
keyLookupTable[65106] = "^"
keyLookupTable[65288] = "Backspace"
keyLookupTable[65289] = "Tab"
keyLookupTable[65293] = "Return"
keyLookupTable[65299] = "Pause"
keyLookupTable[65300] = "Scroll lock"
keyLookupTable[65307] = "Escape"
keyLookupTable[65360] = "Home"
keyLookupTable[65365] = "Page up"
keyLookupTable[65366] = "Page down"
keyLookupTable[65367] = "End"
keyLookupTable[65407] = "Num lock"
keyLookupTable[65421] = "Enter (Numpad)"
keyLookupTable[65452] = ". (Numpad)"
keyLookupTable[65451] = "+ (Numpad)"
keyLookupTable[65450] = "* (Numpad)"
keyLookupTable[65453] = "- (Numpad)"
keyLookupTable[65455] = "/ (Numpad)"
keyLookupTable[65535] = "Delete"
# Numbers on numpad
for i in 0..9:
  keyLookupTable[guint(65456 + i)] = $i & " (Numpad)"
# F1..F12
for i in 1..12:
  keyLookupTable[guint(65469 + i)] = "F" & $i

##### Initialize stateLookupTable #####

stateLookupTable = initTable[guint, string]() 
stateLookupTable[1] = "Shift"
stateLookupTable[4] = "Ctrl"
stateLookupTable[8] = "Alt"
