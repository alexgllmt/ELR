sudo ln -s ./etnalog.service /etc/systemd/system/
sudo systemctl daemon-reload
cp ./Git/* $1/.git/hooks/

sudo systemctl status etnalog

