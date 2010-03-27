import gtk2, gtksourceview
type

  TSettings* = object
    search*: string
    font*: string
    colorSchemeID*: string

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