import gtk2, gtksourceview
type

  TSettings* = object
  
    search*: string
    
    font*: string # font used by the sourceview
    colorSchemeID*: string # color scheme used by the sourceview
    indentWidth*: int # how many spaces used for indenting code(in the sourceview)
    showLineNumbers*: bool # whether to show line numbers in the sourceview
    highlightMatchingBrackets*: bool # whether to highlight matching brackets

  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme
    SourceViewTabs*: PNotebook
    bottomBar*: PStatusBar
    
    findBar*: PHBox # findBar
    findEntry*: PEntry
    replaceEntry*: PEntry
    replaceLabel*: PLabel
    replaceBtn*: PButton
    replaceAllBtn*: PButton
    
    Tabs*: seq[Tab] # Other
    
    settings*: TSettings

  Tab* = object
    buffer*: PSourceBuffer
    sourceView*: PWidget
    saved*: bool
    filename*: string