Vagrant::Config.run do |config|

$pombase_script = <<SCRIPT
if [ ! -d root-pombase ]
then
  git clone /vagrant root-pombase
  (cd root-pombase; perl Makefile.PL < /dev/null; make)
fi

if [ ! -d pombase ]
then
  su - vagrant -c '
    git clone /vagrant pombase;
    (cd pombase && perl Build.PL < /dev/null)'
fi

SCRIPT

config.vm.box = "precise64"
  config.vm.provision :puppet
  config.vm.provision :shell,
    :inline => $pombase_script
end

