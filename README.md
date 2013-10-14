PomBase Chado code
==================

Installation
------------

    sudo apt-get install libmodule-install-perl
	perl Build.PL
	./Build
	./Build installdeps
	./Build test
	./Build install


Scripts
-------

The following scripts are provided in the script directory:

  - `pombase-import.pl`  - import files in various formats
  - `pombase-export.pl`  - export flat files
  - `pombase-chado.pl`   - process data in Chado

Run these scripts with the "-h" argument for more documentation.


License and Copyright
---------------------

Copyright (C) 2011-2013 PomBase

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

