import glib2, gtk2, gdk2, dialogs, os
import utils, aporia

var nimrodPath: string = ""

proc getNimrodPath*(win: var MainWin): string =
    if nimrodPath == "":
        nimrodPath = findExe("nimrod")
        
        if nimrodPath == "":
            dialogs.info(win.w, "Unable to find nimrod executable. Please select it to continue.")
            nimrodPath = ChooseFileToOpen(win.w, "")

    result = nimrodPath