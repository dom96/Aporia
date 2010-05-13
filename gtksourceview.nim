import gtk2, glib2

when defined(windows):
  const lib = "libgtksourceview-2.0-0.dll"
elif defined(macosx):
  const lib = "libgtksourceview-2.0-0.dylib"
else:
  const lib = "libgtksourceview-2.0.so(|.0)"

type
  TSourceLanguageManager*{.pure, final.} = object
  PSourceLanguageManager* = ptr TSourceLanguageManager

  TSourceLanguage*{.pure, final.} = object
  PSourceLanguage* = ptr TSourceLanguage
  
  TSourceBuffer*{.pure, final.} = object of TTextBuffer
  PSourceBuffer* = ptr TSourceBuffer
  
  TSourceView*{.pure, final.} = object of TTextView
  PSourceView* = ptr TSourceView
  
  TSourceStyleSchemeManager*{.pure, final.} = object
  PSourceStyleSchemeManager* = ptr TSourceStyleSchemeManager
  
  TSourceStyleScheme*{.pure, final.} = object
  PSourceStyleScheme* = ptr TSourceStyleScheme
  
const
  TEXT_SEARCH_CASE_INSENSITIVE* = 1 shl 2
  
proc source_view_new*(): PWidget {.cdecl, dynlib: lib,
  importc: "gtk_source_view_new".}

proc source_view_new*(buffer: PSourceBuffer): PWidget {.cdecl, dynlib: lib,
  importc: "gtk_source_view_new_with_buffer".}

proc language_manager_get_default*(): PSourceLanguageManager {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_get_default".}

proc language_manager_new*(): PSourceLanguageManager {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_new".}

proc guess_language*(lm: PSourceLanguageManager, filename: cstring, contentType: cstring): PSourceLanguage {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_guess_language".}

proc get_language*(lm: PSourceLanguageManager, id: cstring): PSourceLanguage {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_get_language".}

proc set_search_path*(lm: PSourceLanguageManager, dirs: cstringarray) {.cdecl, dynlib: lib,
  importc: "gtk_source_language_manager_set_search_path".}

proc set_language*(buffer: PSourceBuffer, language: PSourceLanguage) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_language".}

proc set_scheme*(buffer: PSourceBuffer, scheme: PSourceStyleScheme) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_style_scheme".}
  
proc set_highlight_syntax*(buffer: PSourceBuffer, highlight: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_highlight_syntax".}
  
proc set_insert_spaces_instead_of_tabs*(view: PSourceView, enable: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_insert_spaces_instead_of_tabs".}
  
proc set_indent_width*(view: PSourceView, width: gint) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_indent_width".}

proc set_show_line_marks*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_show_line_marks".}
  
proc set_highlight_current_line*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_highlight_current_line".}
  
proc set_show_line_numbers*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_show_line_numbers".}

proc set_auto_indent*(view: PSourceView, enable: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_auto_indent".}

proc set_show_right_margin*(view: PSourceView, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_view_set_show_right_margin".}
  
proc source_buffer_new*(table: PTextTagTable): PSourceBuffer {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_new".}
  
proc source_buffer_new*(language: PSourceLanguage): PSourceBuffer {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_new_with_language".}

proc set_highlight_matching_brackets*(view: PSourceBuffer, show: gboolean) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_set_highlight_matching_brackets".}

proc undo*(buffer: PSourceBuffer) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_undo".}
  
proc redo*(buffer: PSourceBuffer) {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_redo".}
  
proc can_undo*(buffer: PSourceBuffer): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_can_undo".}
  
proc can_redo*(buffer: PSourceBuffer): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_buffer_can_redo".}
  
proc forward_search*(iter: PTextIter, str: cstring, flags: TTextSearchFlags, 
                     match_start: PTextIter, match_end: PTextIter, 
                     limit: PTextIter): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_iter_forward_search".}
  
proc backward_search*(iter: PTextIter, str: cstring, flags: TTextSearchFlags, 
                     match_start: PTextIter, match_end: PTextIter, 
                     limit: PTextIter): gboolean {.cdecl, dynlib: lib,
  importc: "gtk_source_iter_backward_search".}
  
proc scheme_manager_get_default*(): PSourceStyleSchemeManager {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_manager_get_default".}

proc get_scheme_ids*(manager: PSourceStyleSchemeManager): cstringArray {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_manager_get_scheme_ids".}

proc get_scheme*(manager: PSourceStyleSchemeManager, scheme_id: cstring): PSourceStyleScheme {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_manager_get_scheme".}

proc set_search_path*(manager: PSourceStyleSchemeManager, dirs: cstringarray) {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_manager_set_search_path".}

proc get_name*(scheme: PSourceStyleScheme): cstring {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_get_name".}

proc get_description*(scheme: PSourceStyleScheme): cstring {.cdecl, dynlib: lib,
  importc: "gtk_source_style_scheme_get_description".}
  
