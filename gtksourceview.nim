import gtk2, glib2

const
  lib = "libgtksourceview-2.0-0.dll"

type
  TSourceLanguageManager*{.pure, final.} = object
  PSourceLanguageManager* = ptr TSourceLanguageManager

  TSourceLanguage*{.pure, final.} = object
  PSourceLanguage* = ptr TSourceLanguage
  
  TSourceBuffer*{.pure, final.} = object of TTextBuffer
  PSourceBuffer* = ptr TSourceBuffer
  
  TSourceView*{.pure, final.} = object of TTextView
  PSourceView* = ptr TSourceView
  
proc source_view_new*(): PWidget {.cdecl, dynlib: lib,
  importc: "gtk_source_view_new".}

proc language_manager_get_default*(): PSourceLanguageManager {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_get_default".}

proc language_manager_new*(): PSourceLanguageManager {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_new".}

proc guess_language*(lm: PSourceLanguageManager, filename: cstring, contentType: cstring): PSourceLanguage {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_guess_language".}

proc get_language*(lm: PSourceLanguageManager, id: cstring): PSourceLanguage {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_get_language".}

proc set_language*(buffer: PSourceBuffer, language: PSourceLanguage) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_language".}
  
proc set_highlight_syntax*(buffer: PSourceBuffer, highlight: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_highlight_syntax".}
  
proc set_insert_spaces_instead_of_tabs*(view: PSourceView, enable: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_insert_spaces_instead_of_tabs".}
  
proc set_indent_width*(view: PSourceView, width: gint) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_indent_width".}

proc set_show_line_marks*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_show_line_marks".}
  
proc set_show_line_numbers*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_show_line_numbers".}
  
proc source_buffer_new*(table: PTextTagTable): PSourceBuffer {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_new".}
  
proc source_buffer_new_with_language*(language: PSourceLanguage): PSourceBuffer {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_new_with_language".}
  
proc undo*(buffer: PSourceBuffer) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_undo".}
  
proc redo*(buffer: PSourceBuffer) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_redo".}
  
proc can_undo*(buffer: PSourceBuffer): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_can_undo".}
  
proc can_redo*(buffer: PSourceBuffer): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_can_redo".}
  
  
  
  
  