#!/bin/sh

# Function to generate a random string of 5 alphanumeric characters
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Array for generating IPv6 segments
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Function to generate an IPv6 address segment
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Function to install 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    URL="https://raw.githubusercontent.com/ngochoaitn/multi_proxy_ipv6/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Function to generate the 3proxy configuration file
gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate a proxy file for the user
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Function to upload the proxy file and provide download details
upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://bashupload.com/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

# Function to generate data for proxies
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables rules for the proxies
gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

# Function to configure network interfaces with IPv6 addresses for the proxies
gen_ifconfig() {
    awk -F "/" '{print "ifconfig '${INTERFACE}' inet6 add " $5 "/64"}' ${WORKDATA}
}

echo "Installing required packages..."
dnf -y install gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "Setting up working directory..."
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External subnet for IPv6 = ${IP6}"

echo "How many proxies do you want to create? Example: 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

gen_data >$WORKDIR/data.txt

echo "Generating iptables rules..."
gen_iptables >$WORKDIR/boot_iptables.sh

echo "Detecting network interface..."
INTERFACE=$(ip route show default | awk '/default/ {print $5}')
if [ -z "$INTERFACE" ]; then 
   echo "No network interface found. Exiting."
   exit 1 
fi

echo "Using network interface: ${INTERFACE}"

echo "Generating network interface configurations..."
gen_ifconfig >$WORKDIR/boot_ifconfig.sh

chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

echo "Generating 3proxy configuration..."
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local

gen_proxy_file_for_user

upload_proxy

echo "Setup complete!"
