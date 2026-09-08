#!/bin/bash
set -e
cd /opt/pangolin
curl -sL -o GeoLite2-Country.tar.gz https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/GeoLite2-Country.tar.gz
tar -xzf GeoLite2-Country.tar.gz
mv GeoLite2-Country_*/GeoLite2-Country.mmdb config/
rm -rf GeoLite2-Country.tar.gz GeoLite2-Country_*
docker compose restart pangolin
echo "$(date): GeoIP database updated" >> /var/log/geoip-update.log
