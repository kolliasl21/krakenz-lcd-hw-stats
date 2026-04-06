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

Copy krakenz.sh to /usr/bin/krakenz and make it executable:

```bash
sudo cp krakenz.sh /usr/bin/krakenz
sudo chmod +x /usr/bin/krakenz
```

Create `/etc/systemd/system/krakenz.service`:

```ini
[Unit]
Description=NZXT Z63 startup service

[Service]
Type=simple
ExecStart=/usr/bin/krakenz -b 50 -s 25,40,30,60,35,80,40,100 -t

[Install]
WantedBy=default.target

```

Enable service:


```bash
sudo systemctl daemon-reload
sudo systemctl enable krakenz.service --now
```

<img width="320" height="320" alt="image pLRk" src="https://github.com/user-attachments/assets/78e5f3e3-1cf8-45be-bf2c-0153b2563816" />
<img width="320" height="320" alt="time" src="https://github.com/user-attachments/assets/0fff53ed-3e0b-45a8-b23d-ed1fcd8fe28e" />
