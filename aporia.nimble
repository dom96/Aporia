[Package]
name          = "aporia"
version       = "0.4.2"
author        = "Dominik Picheta"
description   = "A Nim IDE."
license       = "GPLv2"
bin           = "aporia"

skipExt = "nim"

[Deps]
Requires: "nim >= 0.11.0, gtk2 >= 1.3, dialogs >= 1.1.1"
