#!/bin/sh

. /etc/sysconfig/heat-params

if [ "$NETWORK_DRIVER" != "flannel" ]; then
    exit 0
fi
CERT_DIR=/etc/kubernetes/certs
PROTOCOL=https
FLANNEL_OPTIONS="-etcd-cafile $CERT_DIR/ca.crt \
-etcd-certfile $CERT_DIR/server.crt \
-etcd-keyfile $CERT_DIR/server.key"
ETCD_CURL_OPTIONS="--cacert $CERT_DIR/ca.crt \
--cert $CERT_DIR/server.crt --key $CERT_DIR/server.key"
FLANNELD_CONFIG=/etc/sysconfig/flanneld

if [ "$TLS_DISABLED" = "True" ]; then
    PROTOCOL=http
    FLANNEL_OPTIONS=""
    ETCD_CURL_OPTIONS=""
fi

sed -i '/FLANNEL_OPTIONS/'d $FLANNELD_CONFIG

cat >> $FLANNELD_CONFIG <<EOF
FLANNEL_OPTIONS="$FLANNEL_OPTIONS"
EOF

. $FLANNELD_CONFIG

FLANNEL_CONFIG_BIN=/usr/local/bin/flannel-config
FLANNEL_CONFIG_SERVICE=/etc/systemd/system/flannel-config.service
FLANNEL_JSON=/etc/sysconfig/flannel-network.json

echo "creating $FLANNEL_CONFIG_BIN"
cat > $FLANNEL_CONFIG_BIN <<EOF
#!/bin/sh

if ! [ -f "$FLANNEL_JSON" ]; then
  echo "ERROR: missing network configuration file" >&2
  exit 1
fi

if [ -z "$FLANNEL_ETCD_ENDPOINTS" ] || [ -z "$FLANNEL_ETCD_PREFIX" ]; then
  echo "ERROR: missing required configuration" >&2
  exit 1
fi

echo "creating flanneld config in etcd"
while ! curl -sf -L $ETCD_CURL_OPTIONS \
        $FLANNEL_ETCD_ENDPOINTS/v2/keys${FLANNEL_ETCD_PREFIX}/config \
        -X PUT --data-urlencode value@${FLANNEL_JSON}; do
    echo "waiting for etcd"
    sleep 1
done
EOF

cat > $FLANNEL_CONFIG_SERVICE <<EOF
[Unit]
After=etcd.service
Requires=etcd.service

[Service]
Type=oneshot
EnvironmentFile=/etc/sysconfig/flanneld
ExecStart=$FLANNEL_CONFIG_BIN

[Install]
WantedBy=multi-user.target
EOF

chown root:root $FLANNEL_CONFIG_BIN
chmod 0755 $FLANNEL_CONFIG_BIN

chown root:root $FLANNEL_CONFIG_SERVICE
chmod 0644 $FLANNEL_CONFIG_SERVICE

systemctl enable flannel-config
systemctl start --no-block flannel-config
