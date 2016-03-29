# Aporia
Aporia is an IDE for the Nim programming language. Aporia uses GTK as the
default toolkit, and the gtksourceview for the text editor component.

![Aporia on Windows 7](https://github.com/nim-lang/Aporia/raw/master/screenshots/windows.png "Aporia on Windows 7")

![Aporia on Mac OS X](https://github.com/nim-lang/Aporia/raw/master/screenshots/osx.png "Aporia on Mac OS X")

## Compiling

To compile Aporia you need the latest version of the nim compiler, preferably
the unstable release from github. Aporia sometimes relies on bug fixes
which have not yet made it to a stable release.

To build Aporia execute ``nimble build`` in its directory. To build and install
Aporia execute ``nimble install`` in its directory.

You can also quickly install it using nimble without the need to clone this repo
yourself, just execute ``nimble install aporia@#head``.

**Note:** You also need to install some dependencies for Aporia to run. The
section below explains this in more detail.

Assuming that all dependencies are installed and you installed Nimble properly,
you will be able to launch Aporia by executing ``aporia`` in the terminal.

### Compiling from C sources

If you do not want to get the nim compiler you can still compile Aporia from
the generated C sources, it's as simple as executing the ``build.sh`` script
(or ``build.bat`` on Windows). You can then also use ``install.sh`` to install
Aporia.

## Dependencies

Aporia depends on the following libraries. You may already have those installed
especially if you are on Linux.

* GTK (version 2!)
* GtkSourceView (any version compatible with GTK2)
* PCRE

### Windows

**Warning:** If you are on a 64bit version of Windows you must not compile Aporia using a 64 bit version of Nim.
This is because there are no 64 bit GTK+ binaries available, see discussion [here](https://github.com/nim-lang/Aporia/issues/51).

#### GTK+

If you already have GTK+ on your system, you don't need to do anything. Just
make sure GTK+ is in your PATH.

If you don't have GTK+ installed then you need to install it. You can get the
latest version from [here](http://sourceforge.net/projects/gtk-win/ "GTK+ Runtime").
Make sure that the installer adds GTK+ to the PATH.
#### GtkSourceView
The GtkSourceView doesn't have an installer, however binaries are available
from [here](http://ftp.acc.umu.se/pub/gnome/binaries/win32/gtksourceview/ "GtkSourceView")
 (these are 32 bit only!). Just pick
the latest version and download the archive then copy the files/folders
in the archive into the 'bin' directory in gtk's directory
(Most likely: ``C:\Program Files\GTK2-Runtime\bin``).
#### libxml2-2
GtkSourceView depends on libxml2-2. This should be downloaded from
[here](http://ftp.gnome.org/pub/GNOME/binaries/win32/dependencies/ "dependencies")
 (these are 32 bit only!).
And the contents of it should be copied the same 'bin' directory as GtkSourceView above.
The zip you are looking for is usually called ``libxml2_2.X.X-1_win32.zip``
#### pcre
The dll for this can be found in nim's repo, in the ``"dist"`` directory. Just
copy it into aporia's directory or somewhere into your PATH.
#### Microsoft Visual C++ 2010 Redistributable Package (*optional*)
If you are experiencing a ``MSVC100.dll cannot be found`` then you may need to install
the Microsoft Visual C++ 2010 Redistributable Package, this can be downloaded from [here](http://www.microsoft.com/download/en/details.aspx?id=5555)
 ([win64](http://www.microsoft.com/download/en/details.aspx?id=14632))

### Linux

Use your package manager to install the dependencies
(gtk2, gtksourceview and PCRE).

### Mac OS X

The easiest way to get Aporia running on Mac OS X is by installing its
dependencies using Homebrew.

```bash
$ brew install gtk gtksourceview
```

To get a nice OS X theme you will also need the GTK Quartz engine. The best
one to get is from [TingPing/homebrew-gnome](https://github.com/TingPing/homebrew-gnome).

```bash
$ brew tap TingPing/gnome
$ brew install --HEAD gtk-quartz-engine
```

To use the Quartz engine you must also define the following environment
variables.

```bash
export GTK_DATA_PREFIX=/usr/local
export GTK_EXE_PREFIX=/usr/local
export GTK2_RC_FILES=$(nimble path aporia | tail -n 1)/share/themes/Quartz/gtk-2.0/gtkrc
```

You can put those in your ``.bash_rc`` file or similar to make it system-wide.

**Note:** For this to work you must have Aporia installed via Nimble.

If running ``aporia`` now tells you about a missing dynamic library,
dependencies might have changed and you could need to ``brew install`` another
package (tell us this is broken by [creating an
issue](https://github.com/nim-lang/Aporia/issues) and we will update the
documentation).

Assuming that you have set everything up correctly, you should see an Aporia
window that looks like this:

![Aporia on Mac OS X](https://github.com/nim-lang/Aporia/raw/master/screenshots/osx.png "Aporia on Mac OS X")