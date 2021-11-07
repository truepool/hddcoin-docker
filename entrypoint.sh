if [[ -n "${TZ}" ]]; then
  echo "Setting timezone to ${TZ}"
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

# Setup locations for /data to be functional
if [ ! -d "/data" ] ; then
	echo "Warning: No /data, container state data will be lost at restart/shutdown!"
	mkdir /data
fi

# Setup hddcoin main state directory
if [ ! -d "/data/hddcoin" ] ; then
	mkdir -p /data/hddcoin
fi
ln -fs /data/hddcoin /root/.hddcoin

# Setup Farmr Files
if [ ! -d "/data/farmr/config" ] ; then
	mkdir -p /data/farmr/config
fi
rm -rf /farmr/config
ln -fs /data/farmr/config /farmr/config

if [ ! -d "/data/farmr/cache" ] ; then
	mkdir -p /data/farmr/cache
fi
rm -rf /farmr/cache
ln -fs /data/farmr/cache /farmr/cache
ln -fs /data/farmr/id.json /farmr/id.json

# Set location of XCH binary
echo "/hddcoin-blockchain/venv/bin/hddcoin" > /farmr/override-xch-binary.txt

# Setup plotman persistence
if [ ! -d "/data/plotman" ] ; then
	mkdir -p /data/plotman
fi
if [ ! -d /root/.config ] ; then
	mkdir /root/.config/
fi
ln -fs /data/plotman /root/.config/plotman

# Setup Chiadog
if [ ! -d "/data/chiadog" ] ; then
	mkdir -p /data/chiadog
fi
if [ ! -e "/data/chiadog/config.yaml" ] ; then
	cp /chiadog/config-example.yaml /data/chiadog/config.yaml
fi

cd /hddcoin-blockchain

. ./activate

hddcoin init

# Enable INFO log level by default
hddcoin configure -log-level INFO

if [[ ${keys} == "generate" ]]; then
  echo "to use your own keys pass them as a text file -v /path/to/keyfile:/path/in/container and -e keys=\"/path/in/container\""
  hddcoin keys generate
else
  hddcoin keys add -f ${keys}
fi

# Check if a CA cert is provided for harvester
if [[ -n "${ca}" ]]; then
  if [[ -z ${ca} ]]; then
    echo "A path to a copy of the farmer peer's ssl/ca required."
    exit
  fi
  hddcoin init -c ${ca}
fi

for p in ${plots_dir//:/ }; do
    mkdir -p ${p}
    if [[ ! "$(ls -A $p)" ]]; then
        echo "Plots directory '${p}' appears to be empty, try mounting a plot directory with the docker -v command"
    fi
    hddcoin plots add -d ${p}
done

sed -i 's/localhost/127.0.0.1/g' ~/.hddcoin/mainnet/config/config.yaml

if [[ ${farmer} == 'true' ]]; then
  hddcoin start farmer-only
elif [[ ${harvester} == 'true' ]]; then
  if [[ -z ${farmer_address} || -z ${farmer_port} || -z ${ca} ]]; then
    echo "A farmer peer address, port, and ca path are required."
    exit
  else
    hddcoin configure --set-farmer-peer ${farmer_address}:${farmer_port}
    hddcoin start harvester
  fi
else
  hddcoin start farmer
fi

if [[ ${testnet} == "true" ]]; then
  if [[ -z $full_node_port || $full_node_port == "null" ]]; then
    hddcoin configure --set-fullnode-port 58444
  else
    hddcoin configure --set-fullnode-port ${var.full_node_port}
  fi
fi

if [[ $farmr == 'farmer' ]]; then
	(cd /farmr/ && sleep 60 && ./farmr farmer headless) &
fi
if [[ $farmr == 'harvester' ]]; then
	(cd /farmr/ && sleep 60 && ./farmr harvester headless) &
fi

if [[ $chiadog == 'true' ]] ; then
	(cd /chiadog/ && sleep 60 && . ./venv/bin/activate && python3 main.py --config /data/chiadog/config.yaml) &
fi

if [[ $plotman == 'true' ]]; then
	(nohup plotman plot >> /data/plotman/daemon.log 2>&1) &
fi

while true; do sleep 30; done;
