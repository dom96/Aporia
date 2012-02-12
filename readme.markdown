# Aporia
Aporia is an IDE for the Nimrod programming language. Aporia uses GTK as the 
default toolkit, and the gtksourceview for the text editor component.

![Aporia on Windows 7](https://github.com/nimrod-code/Aporia/raw/master/screenshots/windows.png "Aporia on Windows 7")

## Compiling
To compile Aporia you need the latest version of the Nimrod compiler, preferably
the unstable release from github. Aporia sometimes relies on bug fixes 
which have not yet made it to a stable release.

Once you have a working Nimrod compiler, all you need to do
is `nimrod c aporia.nim`

### Compiling from C sources
If you do not want to get the nimrod compiler you can still compile Aporia from
the generated C sources, it's as simple as executing the ``build.sh`` script
(or ``build.bat`` on Windows). You can then also use ``install.sh`` to install
Aporia.

## Dependencies
* GTK
* GtkSourceView
* PCRE

Installation instructions:

### Windows
#### GTK+
If you already have GTK+ on your system, you don't need to do anything. Just
make sure GTK+ is in your PATH.

If you don't have GTK+ installed then you need to install it. You can get the 
latest version from [here](http://sourceforge.net/projects/gtk-win/ "GTK+ Runtime").
Make sure that the installer adds GTK+ to the PATH.
#### GtkSourceView
The GtkSourceView doesn't have an installer, however binaries are available 
from [here](http://ftp.acc.umu.se/pub/gnome/binaries/win32/gtksourceview/ "GtkSourceView")
 ([win64](http://ftp.acc.umu.se/pub/gnome/binaries/win64/gtksourceview/ "GtkSourceView")). Just pick
the latest version and download the archive then copy the files/folders
in the archive into the directory that gtk is installed in.
#### libxml2-2
GtkSourceView depends on libxml2-2. This should be downloaded from 
[here](http://ftp.gnome.org/pub/GNOME/binaries/win32/dependencies/ "dependencies")
 ([win64](http://ftp.gnome.org/pub/GNOME/binaries/win64/dependencies/ "dependencies")).
And the contents of it should be copied to the directory that GTK was installed in.
#### pcre
The dll for this can be found in Nimrod's repo, in the ``"dist"`` directory. Just
copy it into aporia's directory or somewhere into your PATH.
### Linux
Use your package manager to install the dependencies.
### Mac OS X
I don't have a Mac. So I have no idea, if you could write a guide and let me 
know of its existence it would be greatly appreciated.