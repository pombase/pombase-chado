Vagrant::Config.run do |config|

$pombase_script = <<SCRIPT
if [ ! -d root-pombase ]
then
  git clone /vagrant root-pombase-chado
  (cd root-pombase-chado; perl Build.PL < /dev/null; ./Build installdeps < /dev/null)
fi

if [ ! -d pombase ]
then
  su - vagrant -c '
    git clone /vagrant pombase-chado;
    (cd pombase-chado && perl Build.PL < /dev/null)'
fi

SCRIPT

config.vm.box = "precise64"
  config.vm.provision :puppet
  config.vm.provision :shell,
    :inline => $pombase_script
end

