# Solana monitoring
Script for monitoring Solana validator node with grafana and node exporter

# Features
* Simple setup with minimal performance impact to monitor validator node.
* Easy to check SFDP position
* Monitor voting rate and Score (how validator close to top performance leader in net)
* Calculate estimation for validator balance in days hours:minutes:seconds 
* Sample Dashboard to import into Grafana.
* Customizable Parameters. You can use your own RPC node or Solana public RPC nodes (much slower).


# Installation & Setup
## Prepare

### Install required packages
- jq
- bc
- curl
- node_exporter
- wget (optional)

```bash
sudo apt install jq bc curl wget
```

#### Node exporter installation if need
```bash
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvf node_exporter-1.8.2.linux-amd64.tar.gz && rm -rf node_exporter-1.8.2.linux-amd64.tar.gz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin
rm -rf node_exporter-1.8.2.linux-amd64
```

**Create node exporter service**

```bash
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
```

**Reload daemon and start node exporter**

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter
```


### Create directory for metrics file

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chmod 777 /var/lib/node_exporter/textfile_collector
```

## Add directory path in node exporter config

`--collector.textfile --collector.textfile.directory /var/lib/node_exporter/textfile_collector/`


**Edit node exporter service file**
`/etc/systemd/system/node_exporter.service`

**It will look like that** 
```text
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.textfile --collector.textfile.directory /var/lib/node_exporter/textfile_collector/
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

### Reload daemon and restart node exporter

```bash
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
```


## Monitoring

### Create directory for script
```bash
mkdir -p /home/sol/solanamonitoring
cd /home/sol/solanamonitoring
```

### Download script and change permissions
```bash
wget -O monitor.sh https://raw.githubusercontent.com/AiNodes-Tech/solana-monitoring/refs/heads/main/monitor.sh && chmod +x monitor.sh
```

### Checking the all works
```bash
./monitor.sh
```
If no errors on the screen - great! 

#### Print metrics 
By default metrics write to `/var/lib/node_exporter/textfile_collector/sol.prom`
```bash
cat /var/lib/node_exporter/textfile_collector/sol.prom
```

### Add script to cron

```bash
crontab -e
```

```text
*/1 * * * * /home/sol/solanamonitoring/monitor.sh
```

## Grafana dashboard

Import Solana Monitoring Dashboard from `Dashboard` directory to grafana

![Sample Solana Monitoring Dashboard](https://i.imgur.com/4SJ2uSH.png)


### SFDP priority and onboarding in mainnet estimation + score
Score is how validator close to top performance leader in net

![Sample Solana Monitoring Dashboard](https://i.imgur.com/DUdj9cJ.png)



## Prometheus config job
```yaml
scrape_configs:
  - job_name: "node-exporter"
    scrape_interval: 5s
    static_configs:
      - targets: ['YOUR_IP:9100']
        labels:
          instance: 'solana-validator'
```




Stake with **AiNodes** validator on Solflare.

Vote Account: [EsSodfiCfuM4ANfpPAunwj3wo8RaoRrZR9yY79CoXoUV](https://solanabeach.io/validator/EsSodfiCfuM4ANfpPAunwj3wo8RaoRrZR9yY79CoXoUV)

[AiNodes.tech](https://ainodes.tech)
