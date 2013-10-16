class pombase {
  exec { "apt-update":
    command => "/usr/bin/apt-get update"
  }

  Exec["apt-update"] -> Package <| |>

  package { "ntpdate":
    ensure => present,
  }

  package { "sqlite3":
    ensure => present,
  }

  package { "make":
    ensure => present,
  }

  package { "git-core":
    ensure => present,
  }

  package { "perl":
    ensure => present,
  }

  package { "gcc":
    ensure => present,
  }

  package { "g++":
    ensure => present,
  }

  package { "tar":
    ensure => present,
  }

  package { "gzip":
    ensure => present,
  }

  package { "bzip2":
    ensure => present,
  }

  package { "libbio-perl-perl":
    ensure => present,
  }

  package { "liblocal-lib-perl":
    ensure => present,
  }
}

include pombase
