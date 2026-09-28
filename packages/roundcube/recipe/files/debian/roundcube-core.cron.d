# Note: This is a no-op when PID1 is systemd
#
# Database cleaning: remove old records that were marked as deleted
0 5 * * * www-data test -d /run/systemd/system || /usr/share/roundcube/bin/cleandb.sh >/dev/null

# Purge expired sessions, caches and tempfiles
5,35 * * * * www-data test -d /run/systemd/system || /usr/share/roundcube/bin/gc.sh
