# Building GTK on Mac OS X

Before you start, know this: building GTK on OS X is no picnic. It took me a 
solid week to build ``.dylib``'s which worked. Throughout my time attempting
to get the damn thing to work I ran into many issues. Some of which I hope I
can document here for future reference, as well as to help others like yourself.

**Note:** I am writing this mostly from memory, so you will likely need to
tinker this a bit.

## Steps to build

Before you start,
you want to make sure that you use the ``jhbuildrc-custom`` file in this
directory. Save it as ``.jhbuildrc-custom`` in your ``~``. But before you do,
create a new user just for this build (yeah, it sucks but it's the
easiest way and the link below recommends it).

Follow the steps in this wiki: https://wiki.gnome.org/Projects/GTK+/OSX/Building

Pay especially good attention to ensuring that there is nothing GTK+ related
installed on your system previously using MacPorts, Fink or Homebrew.
Personally I had to remove the following (and probably more):

* atk
* gobject-introspection
* cvs
* gnome-common
* gtk+
* gtk3+
* gtksourceview
* gettext
* autoconf
* automake
* libcsv
* libffi
* hicolor-icon-theme
* gdk-pixbuf
* pygtk
* py2cairo
* pygobject
* libpng/libtiff/jpeg
* intltool (!)
* icu4c
* freetype
* fontconfig
* cairo
* harfbuzz (!)
* gtk-quartz-engine
* gtk-mac-integration
* gobject
* gobject-introspection
* glib

Basically check ``/usr/local/Cellar/`` (for brew) to see if there is anything
GTK-related in there and remove it. Unless you ensure that these are all
removed, you WILL get odd errors. Like random
[bash segfaults](https://twitter.com/d0m96/status/714488850786164736),
problems related to ``Makefile.in.in`` not being found and other things.

While executing any of the following (as recommended by Gnome's wiki):

```
jhbuild build python
jhbuild bootstrap
jhbuild build meta-gtk-osx-bootstrap
jhbuild build meta-gtk-osx-core
```

You will likely run into some issues, some of them are due to caching by 
autoconf or due to something else. Thankfully they can be pretty easily fixed
by simply asking ``jhbuild`` to retry the "build phase" (it gives you a nice
prompt when things go wrong). Occassionally you may need to tinker, I needed
to patch gtksourceview manually for example, I took the patch straight out of
[Homebrew's formula](https://github.com/Homebrew/homebrew/blob/master/Library/Formula/gtksourceview.rb).

The commands above will build gtk2+ and dependencies. But you will also likely
need fontconfig/freetype which you can build by using the
``meta-gtk-osx-freetype`` package. After that you will also need to build
``gtk-quartz-engine`` and ``gtksourceview`` (if needed), these modules are
all defined in the ``jhbuildrc-custom`` file.

Hope that helps. Unfortunately this takes a lot of trial and error, and the
errors you will get on your system will likely be completely different to the
errors I got on mine. If all else fails grab the binaries that I am using in
the Aporia bundle, I hope that they work on most OS X machines (time will tell).

## Some other random info

The ``jhbuildrc-custom`` file specifies versions for gtk2 and its dependencies.
I have used the versions specified by Homebrew, as those versions worked for
Aporia when I built it all via Homebrew.

You can use ``otool -L <blah.dylib>`` to get some information about what
``blah.dylib`` depends on. This can be very useful for solving problems. For
example, here is output for ``otool -L libgtk-quartz-2.0.0.dylib``:

```
Contents/Resources/lib/libgtk-quartz-2.0.0.dylib:
  /Users/gtk/gtk/inst/lib/libgtk-quartz-2.0.0.dylib (compatibility version 2401.0.0, current version 2401.30.0)
  @executable_path/../Resources/lib/libgdk-quartz-2.0.0.dylib (compatibility version 2401.0.0, current version 2401.30.0)
  @executable_path/../Resources/lib/libgmodule-2.0.0.dylib (compatibility version 4601.0.0, current version 4601.2.0)
  @executable_path/../Resources/lib/libpangocairo-1.0.0.dylib (compatibility version 3801.0.0, current version 3801.1.0)
  @executable_path/../Resources/lib/libpango-1.0.0.dylib (compatibility version 3801.0.0, current version 3801.1.0)
  @executable_path/../Resources/lib/libatk-1.0.0.dylib (compatibility version 21810.0.0, current version 21810.1.0)
  @executable_path/../Resources/lib/libcairo.2.dylib (compatibility version 11403.0.0, current version 11403.6.0)
  @executable_path/../Resources/lib/libgdk_pixbuf-2.0.0.dylib (compatibility version 3201.0.0, current version 3201.3.0)
  @executable_path/../Resources/lib/libgio-2.0.0.dylib (compatibility version 4601.0.0, current version 4601.2.0)
  @executable_path/../Resources/lib/libgobject-2.0.0.dylib (compatibility version 4601.0.0, current version 4601.2.0)
  @executable_path/../Resources/lib/libglib-2.0.0.dylib (compatibility version 4601.0.0, current version 4601.2.0)
  /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1226.10.1)
  @executable_path/../Resources/lib/libintl.8.dylib (compatibility version 10.0.0, current version 10.3.0)
  /System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa (compatibility version 1.0.0, current version 22.0.0)
  /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0, current version 1404.32.0)
  /System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices (compatibility version 1.0.0, current version 48.0.0)
  /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation (compatibility version 150.0.0, current version 1256.14.0)
  /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 1256.1.0)
  /usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
```

## What do I do after everything is built?

You will need to run the ``gtk-mac-bundler`` tool. This tool will modify each
``.dylib``, ensuring that it correctly references its dependencies (yep, 
OS X's dylib resolution is interesting).

