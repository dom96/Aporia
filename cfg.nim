#
#
#            Aporia - Nim IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import utils, times, streams, parsecfg, strutils, os, osproc
from gtk2 import getInsert, getOffset, getIterAtMark, TTextIter,
    WrapNone, WrapChar, WrapWord, acceleratorParse, acceleratorName,
    acceleratorValid
import gdk2
import glib2
from processes import addError

type
  ECFGParse* = object of Exception

const KEY_notSet = 0.guint

proc defaultAutoSettings*(): TAutoSettings =
  result.search = SearchCaseInsens
  result.wrapAround = true
  result.winWidth = 800
  result.winHeight = 600

  result.recentlyOpenedFiles = @[]

proc defaultGlobalSettings*(): TGlobalSettings =
  result.selectHighlightAll = true
  result.searchHighlightAll = false
  when defined(macosx):
    result.font = "Menlo 12"
  else:
    result.font = "Monospace 10"
  result.outputFont = "Monospace 10"
  result.colorSchemeID = "piekno"
  result.indentWidth = 2
  result.showLineNumbers = true
  result.highlightMatchingBrackets = true
  result.toolBarVisible = true
  result.autoIndent = true
  result.compileSaveAll = false
  result.nimCmd = "$findExe(nim) c --listFullPaths $#"
  result.customCmd1 = ""
  result.customCmd2 = ""
  result.customCmd3 = ""
  result.singleInstancePort = 55679
  result.showCloseOnAllTabs = false
  result.compileUnsavedSave = true
  result.nimPath = ""
  result.wrapMode = WrapNone
  result.scrollPastBottom = false
  result.singleInstance = true
  result.restoreTabs = true
  result.activateErrorTabOnErrors = false
  
  when defined(macosx):
    let mask: guint = MetaMask
  else:
    let mask: guint = ControlMask

  result.keyCommentLines      = ShortcutKey(keyval: KEY_slash, state: mask)
  result.keyDeleteLine        = ShortcutKey(keyval: KEY_d, state: mask)
  result.keyDuplicateLines    = ShortcutKey(keyval: KEY_notSet, state: 0)
  result.keyQuit              = ShortcutKey(keyval: KEY_q, state: mask)
  result.keyNewFile           = ShortcutKey(keyval: KEY_n, state: mask)
  result.keyOpenFile          = ShortcutKey(keyval: KEY_o, state: mask)
  result.keySaveFile          = ShortcutKey(keyval: KEY_s, state: mask)
  result.keySaveFileAs        = ShortcutKey(keyval: KEY_s, state: mask or ShiftMask)
  result.keySaveAll           = ShortcutKey(keyval: KEY_notSet, state: mask or ShiftMask)
  result.keyUndo              = ShortcutKey(keyval: KEY_z, state: mask)
  result.keyRedo              = ShortcutKey(keyval: KEY_z, state: mask or ShiftMask)
  result.keyCloseCurrentTab   = ShortcutKey(keyval: KEY_w, state: mask)
  result.keyCloseAllTabs      = ShortcutKey(keyval: KEY_w, state: mask or ShiftMask)
  result.keyFind              = ShortcutKey(keyval: KEY_f, state: mask)
  result.keyReplace           = ShortcutKey(keyval: KEY_h, state: mask)
  result.keyFindNext          = ShortcutKey(keyval: KEY_notSet, state: 0)
  result.keyFindPrevious      = ShortcutKey(keyval: KEY_notSet, state: 0)
  result.keyGoToLine          = ShortcutKey(keyval: KEY_g, state: mask)
  result.keyGoToDef           = ShortcutKey(keyval: KEY_r, state: mask or ShiftMask)
  result.keyToggleBottomPanel = ShortcutKey(keyval: KEY_b, state: mask or ShiftMask)
  result.keyCompileCurrent    = ShortcutKey(keyval: KEY_F4, state: 0)
  result.keyCompileRunCurrent = ShortcutKey(keyval: KEY_F5, state: 0)
  result.keyCompileProject    = ShortcutKey(keyval: KEY_F8, state: 0)
  result.keyCompileRunProject = ShortcutKey(keyval: KEY_F9, state: 0)
  result.keyStopProcess       = ShortcutKey(keyval: KEY_F7, state: 0)
  result.keyRunCustomCommand1 = ShortcutKey(keyval: KEY_F1, state: 0)
  result.keyRunCustomCommand2 = ShortcutKey(keyval: KEY_F2, state: 0)
  result.keyRunCustomCommand3 = ShortcutKey(keyval: KEY_F3, state: 0)
  result.keyRunCheck          = ShortcutKey(keyval: KEY_F5, state: mask)

proc getName*(shortcut: ShortcutKey): string =
  return $acceleratorName(shortcut.keyval, shortcut.state)

proc isValid*(shortcut: ShortcutKey): bool =
  return acceleratorValid(shortcut.keyval, shortcut.state)

proc toShortcutKey(shortcutStr: string): (ShortcutKey, bool) =
  var key: guint = 0
  var mods: guint = 0
  acceleratorParse(shortcutStr, addr key, addr mods)
  if key == 0 or mods == 0:
    result[1] = false
    return
  if not acceleratorValid(key, mods):
    result[1] = false
    return
  return (ShortcutKey(keyval: key, state: mods), true)

proc toKeyOrDefault(shortcutStr: string, def: ShortcutKey): ShortcutKey =
  let (key, valid) = toShortcutKey(shortcutStr)
  if valid:
    return key
  else:
    return def

template setShortcutIfValid*(shortcutStr: string, shortcutField: untyped): stmt =
  `shortcutField` = toKeyOrDefault(shortcutStr, `shortcutField`)

proc writeSection(f: File, sectionName: string) =
  f.write("[")
  f.write(sectionName)
  f.write("]\n")

proc writeKeyVal(f: File, key, val: string) =
  f.write(key)
  f.write(" = ")
  if val.len == 0: f.write("\"\"")
  else: f.write(osproc.quoteShell(val))
  f.write("\n")

proc writeKeyVal(f: File, key: string, val: int) =
  f.write(key)
  f.write(" = ")
  f.write(val)
  f.write("\n")

proc writeKeyValRaw(f: File, key: string, val: string) =
  f.write(key)
  f.write(" = r")
  if val.len == 0: f.write("\"\"")
  else: f.write("\"" & val & "\"")
  f.write("\n")

proc save(settings: TAutoSettings, win: var MainWin) =
  if not os.existsDir(os.getConfigDir() / "Aporia"):
    os.createDir(os.getConfigDir() / "Aporia")
  
  var f: File
  if open(f, joinPath(os.getConfigDir(), "Aporia", "config.auto.ini"), fmWrite):
    var confInfo = "; Aporia automatically generated configuration file - Last modified: "
    confInfo.add($getTime())
    f.write(confInfo & "\n")
    
    f.writeKeyVal("searchMethod", $int(settings.search))
    f.writeKeyVal("wrapAround", $settings.wrapAround)
    f.writeKeyVal("winMaximized", $settings.winMaximized)
    f.writeKeyVal("VPanedPos", settings.VPanedPos)
    f.writeKeyVal("winWidth", settings.winWidth)
    f.writeKeyVal("winHeight", settings.winHeight)
    
    f.writeKeyVal("bottomPanelVisible", $settings.bottomPanelVisible)
    if settings.recentlyOpenedFiles.len() > 0:
      let frm = max(0, (settings.recentlyOpenedFiles.len-1)-19)
      let to  = settings.recentlyOpenedFiles.len()-1
      f.writeKeyValRaw("recentlyOpenedFiles",
                    join(settings.recentlyOpenedFiles[frm..to], ";"))

    if win.tabs.len != 0:
      f.writeSection("session")
      var tabs = "tabs = r\""
      # Save all the tabs that have a filename.
      for i in items(win.tabs):
        if i.filename != "":
          var cursorIter: TTextIter
          i.buffer.getIterAtMark(addr(cursorIter), i.buffer.getInsert())
          var cursorPos = getOffset(addr cursorIter)
          # Kind of a messy way to save the cursor pos and filename.
          tabs.add(i.filename & "|" & $cursorPos & ";")
      f.write(tabs & "\"\n")
    
      # Save currently selected tab
      var current = win.getCurrentTab()
      f.writeKeyValRaw("lastSelectedTab", win.tabs[current].filename)
    f.close()

proc save*(settings: TGlobalSettings) =
  if not os.existsDir(os.getConfigDir() / "Aporia"):
    os.createDir(os.getConfigDir() / "Aporia")
  
  # Save the settings to file.
  var f: File
  if open(f, joinPath(os.getConfigDir(), "Aporia", "config.global.ini"), fmWrite):
    var confInfo = "; Aporia global configuration file - Last modified: "
    confInfo.add($getTime())
    f.write(confInfo & "\n")

    f.writeKeyVal("font", settings.font)
    f.writeKeyVal("outputFont", settings.outputFont)
    f.writeKeyVal("scheme", settings.colorSchemeID)
    f.writeKeyVal("indentWidth", settings.indentWidth)
    f.writeKeyVal("showLineNumbers", $settings.showLineNumbers)
    f.writeKeyVal("highlightMatchingBrackets",
                  $settings.highlightMatchingBrackets)
    f.writeKeyVal("rightMargin", $settings.rightMargin)
    f.writeKeyVal("highlightCurrentLine", $settings.highlightCurrentLine)
    f.writeKeyVal("autoIndent", $settings.autoIndent)
    f.writeKeyVal("suggestFeature", $settings.suggestFeature)
    f.writeKeyVal("showCloseOnAllTabs", $settings.showCloseOnAllTabs)

    f.writeKeyVal("selectHighlightAll", $settings.selectHighlightAll)
    f.writeKeyVal("searchHighlightAll", $settings.searchHighlightAll)
    f.writeKeyVal("singleInstance", $settings.singleInstance)
    f.writeKeyVal("singleInstancePort", $int(settings.singleInstancePort))
    f.writeKeyVal("compileUnsavedSave", $settings.compileUnsavedSave)
    f.writeKeyVal("restoreTabs", $settings.restoreTabs)
    f.writeKeyVal("activateErrorTabOnErrors", $settings.activateErrorTabOnErrors)
    f.writeKeyValRaw("nimPath", $settings.nimPath)
    f.writeKeyVal("toolBarVisible", $settings.toolBarVisible)
    f.writeKeyVal("wrapMode",
      case settings.wrapMode
      of WrapNone: "none"
      of WrapChar: "char"
      of WrapWord: "word"
      else:
        assert false; ""
    )
    f.writeKeyVal("scrollPastBottom", $settings.scrollPastBottom)
    f.writeKeyVal("compileSaveAll", $settings.compileSaveAll)
    
    f.writeKeyVal("nimCmd", settings.nimCmd)
    f.writeKeyVal("customCmd1", settings.customCmd1)
    f.writeKeyVal("customCmd2", settings.customCmd2)
    f.writeKeyVal("customCmd3", settings.customCmd3)
    
    f.writeSection("ShortcutKeys")
    
    f.writeKeyValRaw("keyQuit", getName(settings.keyQuit))
    f.writeKeyValRaw("keyCommentLines", getName(settings.keyCommentLines))
    f.writeKeyValRaw("keydeleteline", getName(settings.keyDeleteLine))
    f.writeKeyValRaw("keyduplicatelines", getName(settings.keyDuplicateLines))
    f.writeKeyValRaw("keyNewFile", getName(settings.keyNewFile))
    f.writeKeyValRaw("keyOpenFile", getName(settings.keyOpenFile))
    f.writeKeyValRaw("keySaveFile", getName(settings.keySaveFile))
    f.writeKeyValRaw("keySaveFileAs", getName(settings.keySaveFileAs))
    f.writeKeyValRaw("keySaveAll", getName(settings.keySaveAll))
    f.writeKeyValRaw("keyUndo", getName(settings.keyUndo))
    f.writeKeyValRaw("keyRedo", getName(settings.keyRedo))
    f.writeKeyValRaw("keyCloseCurrentTab", getName(settings.keyCloseCurrentTab))
    f.writeKeyValRaw("keyCloseAllTabs", getName(settings.keyCloseAllTabs))
    f.writeKeyValRaw("keyFind", getName(settings.keyFind))
    f.writeKeyValRaw("keyReplace", getName(settings.keyReplace))
    f.writeKeyValRaw("keyFindNext", getName(settings.keyFindNext))
    f.writeKeyValRaw("keyFindPrevious", getName(settings.keyFindPrevious))
    f.writeKeyValRaw("keyGoToLine", getName(settings.keyGoToLine))
    f.writeKeyValRaw("keyGoToDef", getName(settings.keyGoToDef))
    f.writeKeyValRaw("keyToggleBottomPanel", getName(settings.keyToggleBottomPanel))
    f.writeKeyValRaw("keyCompileCurrent", getName(settings.keyCompileCurrent))
    f.writeKeyValRaw("keyCompileRunCurrent", getName(settings.keyCompileRunCurrent))
    f.writeKeyValRaw("keyCompileProject", getName(settings.keyCompileProject))
    f.writeKeyValRaw("keyCompileRunProject", getName(settings.keyCompileRunProject))
    f.writeKeyValRaw("keyStopProcess", getName(settings.keyStopProcess))
    f.writeKeyValRaw("keyRunCustomCommand1", getName(settings.keyRunCustomCommand1))
    f.writeKeyValRaw("keyRunCustomCommand2", getName(settings.keyRunCustomCommand2))
    f.writeKeyValRaw("keyRunCustomCommand3", getName(settings.keyRunCustomCommand3))
    f.writeKeyValRaw("keyRunCheck", getName(settings.keyRunCheck))
      
    f.close()

proc save*(win: var MainWin) =
  win.autoSettings.save(win)
  win.globalSettings.save()
  if existsFile(os.getConfigDir() / "Aporia" / "config.ini"):
    echo(os.getConfigDir() / "Aporia" / "config.ini")
    removeFile(os.getConfigDir() / "Aporia" / "config.ini")


proc istrue(s: string): bool =
  result = cmpIgnoreStyle(s, "true") == 0

proc loadOld(cfgErrors: var seq[TError], lastSession: var seq[string]): tuple[a: TAutoSettings, g: TGlobalSettings] =
  var p: CfgParser
  var filename = os.getConfigDir() / "Aporia" / "config.ini"
  var input = newFileStream(filename, fmRead)
  open(p, input, joinPath(os.getConfigDir(), "Aporia", "config.ini"))
  # It is important to initialize every field, because some fields may not
  # be set in the configuration file:
  result.a = defaultAutoSettings()
  result.g = defaultGlobalSettings()
  while true:
    var e = next(p)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key)
      of "font": result.g.font = e.value
      of "outputfont": result.g.outputFont = e.value
      of "scheme": result.g.colorSchemeID = e.value
      of "indentwidth": result.g.indentWidth = int32(e.value.parseInt())
      of "showlinenumbers": result.g.showLineNumbers = isTrue(e.value)
      of "highlightmatchingbrackets":
        result.g.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.g.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.g.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.g.autoIndent = isTrue(e.value)
      of "suggestfeature": result.g.suggestFeature = isTrue(e.value)
      of "showcloseonalltabs": result.g.showCloseOnAllTabs = isTrue(e.value)
      of "searchmethod": result.a.search = TSearchEnum(e.value.parseInt())
      of "selecthighlightall": result.g.selectHighlightAll = isTrue(e.value)
      of "searchhighlightall": result.g.searchHighlightAll = isTrue(e.value)
      of "singleinstanceport":
        result.g.singleInstancePort = int32(e.value.parseInt())
      of "winmaximized": result.a.winMaximized = isTrue(e.value)
      of "vpanedpos": result.a.VPanedPos = int32(e.value.parseInt())
      of "toolbarvisible": result.g.toolBarVisible = isTrue(e.value)
      of "bottompanelvisible": result.a.bottomPanelVisible = isTrue(e.value)
      of "winwidth": result.a.winWidth = int32(e.value.parseInt())
      of "winheight": result.a.winHeight = int32(e.value.parseInt())
      of "nimcmd", "nimrodcmd": result.g.nimCmd = e.value
      of "customcmd1": result.g.customCmd1 = e.value
      of "customcmd2": result.g.customCmd2 = e.value
      of "customcmd3": result.g.customCmd3 = e.value
      of "tabs":
        # Add the filepaths of the last session
        for i in e.value.split(';'):
          if i != "":
            lastSession.add(i)
      of "recentlyopenedfiles":
        for count, file in pairs(e.value.split(';')):
          if file != "":
            if count > 19:
              cfgErrors.add(Terror(kind: TETError, desc: "Too many recent files", file: filename, line: "", column: ""))
            result.a.recentlyOpenedFiles.add(file)
      of "lastselectedtab":
        result.a.lastSelectedTab = e.value
      of "compileunsavedsave":
        result.g.compileUnsavedSave = isTrue(e.value)
      of "nimpath", "nimrodpath":
        result.g.nimPath = e.value
      else:
        cfgErrors.add(Terror(kind: TETError, desc: "Key \"" & e.key & "\" is invalid.", file: filename, line: "", column: ""))
    of cfgError:
      cfgErrors.add(Terror(kind: TETError, desc: e.msg, file: filename, line: "", column: ""))
    of cfgSectionStart, cfgOption:
      discard
  input.close()
  p.close()

proc loadAuto(cfgErrors: var seq[TError], lastSession: var seq[string]): TAutoSettings =
  result = defaultAutoSettings()
  let filename = os.getConfigDir() / "Aporia" / "config.auto.ini"
  if not existsFile(filename): return
  var pAuto: CfgParser
  var autoStream = newFileStream(filename, fmRead)
  open(pAuto, autoStream, filename)
  # It is important to initialize every field, because some fields may not
  # be set in the configuration file:
  while true:
    var e = next(pAuto)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key):
      of "searchmethod": result.search = TSearchEnum(e.value.parseInt())
      of "wraparound": result.wrapAround = isTrue(e.value)
      of "winmaximized": result.winMaximized = isTrue(e.value)
      of "vpanedpos": result.VPanedPos = int32(e.value.parseInt())
      of "bottompanelvisible": result.bottomPanelVisible = isTrue(e.value)
      of "winwidth": result.winWidth = int32(e.value.parseInt())
      of "winheight": result.winHeight = int32(e.value.parseInt())
      of "tabs":
        # Add the filepaths of the last session
        for i in e.value.split(';'):
          if i != "":
            lastSession.add(i)
      of "recentlyopenedfiles":
        for count, file in pairs(e.value.split(';')):
          if file != "":
            if count > 19:
              cfgErrors.add(Terror(kind: TETError, desc: "Too many recent files", file: filename, line: "", column: ""))
            result.recentlyOpenedFiles.add(file)
      of "lastselectedtab":
        result.lastSelectedTab = e.value
      else:
        cfgErrors.add(Terror(kind: TETError, desc: "Key \"" & e.key & "\" is invalid.", file: filename, line: "", column: ""))
    of cfgError:
      cfgErrors.add(Terror(kind: TETError, desc: e.msg, file: filename, line: "", column: ""))
    of cfgSectionStart, cfgOption:
      discard

  autoStream.close()
  pAuto.close()

proc loadGlobal*(cfgErrors: var seq[TError], input: Stream): TGlobalSettings =
  result = defaultGlobalSettings()
  if input == nil: return
  var pGlobal: CfgParser
  var filename = os.getConfigDir() / "Aporia" / "config.global.ini"
  open(pGlobal, input, filename)
  while true:
    var e = next(pGlobal)
    case e.kind
    of cfgEof:
      break
    of cfgKeyValuePair:
      case normalize(e.key)
      of "font": result.font = e.value
      of "outputfont": result.outputFont = e.value
      of "scheme": result.colorSchemeID = e.value
      of "indentwidth": result.indentWidth = int32(e.value.parseInt())
      of "showlinenumbers": result.showLineNumbers = isTrue(e.value)
      of "highlightmatchingbrackets":
        result.highlightMatchingBrackets = isTrue(e.value)
      of "rightmargin": result.rightMargin = isTrue(e.value)
      of "highlightcurrentline": result.highlightCurrentLine = isTrue(e.value)
      of "autoindent": result.autoIndent = isTrue(e.value)
      of "suggestfeature": result.suggestFeature = isTrue(e.value)
      of "showcloseonalltabs": result.showCloseOnAllTabs = isTrue(e.value)
      of "selecthighlightall": result.selectHighlightAll = isTrue(e.value)
      of "searchhighlightall": result.searchHighlightAll = isTrue(e.value)
      of "singleinstance": result.singleInstance = isTrue(e.value)
      of "singleinstanceport":
        result.singleInstancePort = int32(e.value.parseInt())
      of "restoretabs": result.restoreTabs = isTrue(e.value)
      of "activateerrortabonerrors": result.activateErrorTabOnErrors = isTrue(e.value)
      of "toolbarvisible": result.toolBarVisible = isTrue(e.value)
      of "compilesaveall": result.compileSaveAll = isTrue(e.value)
      of "nimcmd", "nimrodcmd": result.nimCmd = e.value
      of "customcmd1": result.customCmd1 = e.value
      of "customcmd2": result.customCmd2 = e.value
      of "customcmd3": result.customCmd3 = e.value
      of "compileunsavedsave":
        result.compileUnsavedSave = isTrue(e.value)
      of "keyquit": result.keyQuit = toKeyOrDefault(e.value, result.keyQuit)
      of "keycommentlines": result.keyCommentLines = toKeyOrDefault(e.value, result.keyCommentLines)
      of "keydeleteline": result.keyDeleteLine = toKeyOrDefault(e.value, result.keyDeleteLine)
      of "keyduplicatelines": result.keyDuplicateLines = toKeyOrDefault(e.value, result.keyDuplicateLines)
      of "keynewfile": result.keyNewFile = toKeyOrDefault(e.value, result.keyNewFile)
      of "keyopenfile": result.keyOpenFile = toKeyOrDefault(e.value, result.keyOpenFile)
      of "keysavefile": result.keySaveFile = toKeyOrDefault(e.value, result.keySaveFile)
      of "keysavefileas": result.keySaveFileAs = toKeyOrDefault(e.value, result.keySaveFileAs)
      of "keysaveall": result.keySaveAll = toKeyOrDefault(e.value, result.keySaveAll)
      of "keyundo": result.keyUndo = toKeyOrDefault(e.value, result.keyUndo)
      of "keyredo": result.keyRedo = toKeyOrDefault(e.value, result.keyRedo)
      of "keyclosecurrenttab": result.keyCloseCurrentTab = toKeyOrDefault(e.value, result.keyCloseCurrentTab)
      of "keyclosealltabs": result.keyCloseAllTabs = toKeyOrDefault(e.value, result.keyCloseAllTabs)
      of "keyfind": result.keyFind = toKeyOrDefault(e.value, result.keyFind)
      of "keyreplace": result.keyReplace = toKeyOrDefault(e.value, result.keyReplace)
      of "keyfindnext": result.keyFindNext = toKeyOrDefault(e.value, result.keyFindNext)
      of "keyfindprevious": result.keyFindPrevious = toKeyOrDefault(e.value, result.keyFindPrevious)
      of "keygotoline": result.keyGoToLine = toKeyOrDefault(e.value, result.keyGoToLine)
      of "keygotodef": result.keyGoToDef = toKeyOrDefault(e.value, result.keyGoToDef)
      of "keytogglebottompanel": result.keyToggleBottomPanel = toKeyOrDefault(e.value, result.keyToggleBottomPanel)
      of "keycompilecurrent": result.keyCompileCurrent = toKeyOrDefault(e.value, result.keyCompileCurrent)
      of "keycompileruncurrent": result.keyCompileRunCurrent = toKeyOrDefault(e.value, result.keyCompileRunCurrent)
      of "keycompileproject": result.keyCompileProject = toKeyOrDefault(e.value, result.keyCompileProject)
      of "keycompilerunproject": result.keyCompileRunProject = toKeyOrDefault(e.value, result.keyCompileRunProject)
      of "keystopprocess": result.keyStopProcess = toKeyOrDefault(e.value, result.keyStopProcess)
      of "keyruncustomcommand1": result.keyRunCustomCommand1 = toKeyOrDefault(e.value, result.keyRunCustomCommand1)
      of "keyruncustomcommand2": result.keyRunCustomCommand2 = toKeyOrDefault(e.value, result.keyRunCustomCommand2)
      of "keyruncustomcommand3": result.keyRunCustomCommand3 = toKeyOrDefault(e.value, result.keyRunCustomCommand3)
      of "keyruncheck": result.keyRunCheck = toKeyOrDefault(e.value, result.keyRunCheck)

      of "nimpath", "nimrodpath":
        result.nimPath = e.value
      of "wrapmode":
        case e.value.normalize
        of "none":
          result.wrapMode = WrapNone
        of "char":
          result.wrapMode = WrapChar
        of "word":
          result.wrapMode = WrapWord
        else:
          cfgErrors.add(Terror(kind: TETError, desc: "WrapMode invalid, got: '" & e.value & "'", file: filename, line: "", column: ""))
      of "scrollpastbottom":
        result.scrollPastBottom = isTrue(e.value)
      else:
        cfgErrors.add(Terror(kind: TETError, desc: "Key \"" & e.key & "\" is invalid.", file: filename, line: "", column: ""))
    of cfgError:
      cfgErrors.add(Terror(kind: TETError, desc: e.msg, file: filename, line: "", column: ""))
    of cfgSectionStart, cfgOption:
      discard
  close(pGlobal)

proc load*(cfgErrors: var seq[TError], lastSession: var seq[string]): tuple[a: TAutoSettings, g: TGlobalSettings] =
  if existsFile(os.getConfigDir() / "Aporia" / "config.ini"):
    return loadOld(cfgErrors, lastSession)
  else:
    result.a = loadAuto(cfgErrors, lastSession)
    var globalStream = newFileStream(os.getConfigDir() / "Aporia" / "config.global.ini", fmRead)
    result.g = loadGlobal(cfgErrors, globalStream)
    if globalStream != nil:
      globalStream.close()
