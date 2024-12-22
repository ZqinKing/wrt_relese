#!/bin/sh

if [ ! -f /etc/config/argon ]; then
    touch /etc/config/argon
    uci add argon global
fi

uci set argon.@global[0].primary='#31A1A1'
uci set argon.@global[0].transparency='0.3'
uci commit argon
