milter = yes;
bind_socket = "/var/run/rspamd/milter.sock mode=0666 owner=rspamd";
# the following specifies self-scan mode, for when rspamd is on the same
# machine as postfix
timeout = 120s;
upstream "local" {
  default = yes;
  self_scan = yes;
}
