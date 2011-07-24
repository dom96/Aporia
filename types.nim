#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gtksourceview

type
  TSettings* = object
    search*: TSearchEnum # Search mode.
    
    font*: string # font used by the sourceview
    colorSchemeID*: string # color scheme used by the sourceview
    indentWidth*: int # how many spaces used for indenting code (in sourceview)
    showLineNumbers*: bool # whether to show line numbers in the sourceview
    highlightMatchingBrackets*: bool # whether to highlight matching brackets
    rightMargin*: bool # Whether to show the right margin
    highlightCurrentLine*: bool # Whether to highlight the current line
    autoIndent*: bool

    winMaximized*: bool # Whether the MainWindow is maximized on startup
    VPanedPos*: int # Position of the VPaned, which splits
                    # the sourceViewTabs and bottomPanelTabs
    winWidth*, winHeight*: int # The size of the window.
                    
    bottomPanelVisible*: bool # Whether the bottom panel is shown
    nimrodCmd*: string  # command template to use to exec the Nimrod compiler
    customCmd1*: string # command template to use to exec a custom command
    customCmd2*: string # command template to use to exec a custom command
    customCmd3*: string # command template to use to exec a custom command
    
  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    suggest*: TSuggestDialog
    langMan*: PSourceLanguageManager
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme # color scheme the sourceview is meant to use
    SourceViewTabs*: PNotebook # Tabs which hold the sourceView
    bottomBar*: PStatusBar 
    
    bottomPanelTabs*: PNotebook
    outputTextView*: PTextView
    
    findBar*: PHBox # findBar
    findEntry*: PEntry
    replaceEntry*: PEntry
    replaceLabel*: PLabel
    replaceBtn*: PButton
    replaceAllBtn*: PButton
    
    viewBottomPanelMenuItem*: PMenuItem # view menu

    Tabs*: seq[Tab] # Other
    
    tempStuff*: Temp # Just things to remember. TODO: Rename to `other' ?
    
    settings*: TSettings

  TSuggestDialog* = object
    dialog*: gtk2.PWindow
    treeView*: PTreeView
    items*: seq[TSuggestItem]
  
  ExecThrParams* = tuple[cmd: string, execMode: TExecMode]
  TExecMode* = enum
    ExecNone, ExecNimrod, ExecRun, ExecCustom
  Temp = object
    lastSaveDir*: string # Last saved directory
    stopSBUpdates*: Bool
    
    procExecRunning*: bool
    ifSuccess*: string
    procExecThread*: TThread[tuple[cmd: string, execMode: TExecMode]]

  Tab* = object
    buffer*: PSourceBuffer
    sourceView*: PSourceView
    label*: PLabel
    saved*: bool
    filename*: string
    
  TSuggestItem* = object
    nodeType*, name*, nimType*, file*: string
    line*, col*: int
  
  TSearchEnum* = enum
    SearchCaseSens, SearchCaseInsens, SearchStyleInsens, SearchRegex, SearchPeg
