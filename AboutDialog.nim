import gtk2
from gdk2 import WINDOW_TYPE_HINT_MENU

type
  TAboutDialog* = object
    dialog: PWindow
    titleLabel: PLabel
    descLabel: PLabel
    copyrightLabel: PLabel

  PAboutDialog* = ref TAboutDialog

proc closeBtn_click(btn: PButton, dummy: pointer) =
  # Kinda hackish.
  btn.parent.parent.parent.destroy()

proc newAboutDialog*(title, desc, copyright: string): PAboutDialog =
  new(result)
  result.dialog = windowNew(WINDOW_TOPLEVEL)
  result.dialog.setTitle("About Aporia")
  result.dialog.setResizable(false)
  setPosition(result.dialog, WIN_POS_CENTER)
  result.dialog.setDestroyWithParent(true)
  result.dialog.setTypeHint(WINDOW_TYPE_HINT_MENU) # Removes minimize button.
  
  var hbox = hboxNew(false, 5)
  result.dialog.add(hbox)
  hbox.show()
  var vbox = vboxNew(false, 5)
  hbox.packStart(vbox, false, false, 15)
  vbox.show()
  
  result.titleLabel = labelNew("")
  result.titleLabel.setMarkup("<span font_desc=\"20.0\">" & title & "</span>")
  vbox.packStart(result.titleLabel, true, true, 0)
  result.titleLabel.show()

  result.descLabel = labelNew("")
  result.descLabel.setMarkup("<span font_desc=\"10.0\">" & desc & "</span>")
  result.descLabel.setJustify(JUSTIFY_CENTER)
  vbox.packStart(result.descLabel, true, true, 0)
  result.descLabel.show()

  result.copyrightLabel = labelNew("")
  result.copyrightLabel.setMarkup("<span font_desc=\"7.0\">" & copyright &
                                  "</span>")
  vbox.packStart(result.copyrightLabel, true, true, 0)
  result.copyrightLabel.show()

  var closeBtn = buttonNew("Close")
  vbox.packStart(closeBtn, true, true, 5)
  closeBtn.show()
  discard closeBtn.signalConnect("clicked", 
      SIGNAL_FUNC(closeBtn_click), nil)

proc show*(about: PAboutDialog) =
  about.dialog.show()
