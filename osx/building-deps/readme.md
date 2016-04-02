# Building GTK on Mac OS X

Before you start know this: building GTK on OS X is no picnic. It took me a 
solid week to build ``.dylib``'s which worked. Throughout my time attempting
to get the damn thing to work I ran into many issues. Some of which I hope I
can document here for future reference as well as to help others like yourself.

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

