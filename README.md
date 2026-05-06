# Display sensor data on NZXT Kraken Z63 liquid cooler

- Display sensors
- Display digital clock
- Other basic functionality (set pump speed, set LCD brightness, etc)

## Dependencies

- liquidctl
- imagemagick
- jq
- lm_sensors
- noto-fonts (Optional)

## Service

Copy krakenz.sh to /usr/local/bin/krakenz and make it executable:

```bash
sudo cp krakenz.sh /usr/local/bin/krakenz
sudo chmod +x /usr/local/bin/krakenz
```

Create `/etc/systemd/system/krakenz.service`:

```ini
[Unit]
Description=NZXT Z63 startup service

[Service]
Type=simple
ExecStart=/usr/local/bin/krakenz -b 50 -s 25,40,30,60,35,80,40,100 -t

[Install]
WantedBy=default.target

```

Enable service:


```bash
sudo systemctl daemon-reload
sudo systemctl enable krakenz.service --now
```

<img width="320" height="320" alt="image sBnn" src="https://github.com/user-attachments/assets/9ef6849d-2676-495c-9af3-6f75ad26886c" />
<img width="320" height="320" alt="image D7OQ" src="https://github.com/user-attachments/assets/cefee771-d8d6-4653-9ed3-4b3b93ac164f" />
