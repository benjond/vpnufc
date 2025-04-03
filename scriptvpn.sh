#!/bin/bash

# Ce script permet d'installer et de configuer le vpn Strongswan de l'IUT NFC

choisir_distribution() {
    echo "1) Debian/Ubuntu/Mint"
    echo "2) Fedora"
    echo "3) Arch/Manjaro"
    echo "4) OpenSUSE"

    read -p "Choisissez votre distribution: " distro
}

installer_paquets() {
    case $distro in
        1)
            sudo apt update -y
            sudo apt install -y network-manager-strongswan libstrongswan-extra-plugins libcharon-extra-plugins
            ;;
        2)
            sudo dnf install -y strongswan NetworkManager-strongswan
            ;;
        3)
            sudo pacman -S --needed --noconfirm strongswan networkmanager-strongswan
            ;;
        4)
            sudo zypper install -y strongswan NetworkManager-strongswan
            ;;
        *)
            echo "Erreur: distribution inconnue"
            exit 1
            ;;
    esac
}

configurer_vpn() {
    echo "Veuillez entrer vos identifiants de connexion"
    read -p "Nom d'utilisateur: " username
    read -sp "Mot de passe: " password

    sudo nmcli connection add type vpn \
    vpn-type strongswan \
    connection.id "VPN UFC" \
    connection.autoconnect no \
    vpn.data \
    "address=vpn20-2.univ-fcomte.fr, encap=yes, esp=aes256-sha1, ike=aes256-sha1-modp1024, ipcomp=no, method=eap, proposal=no, user=$username@ufc, virtual=yes, service-type=org.freedesktop.NetworkManager.strongswan" \
    vpn.secrets \
    "password=$password" \
    ipv4.method auto \
    ipv6.method auto \
    ipv6.addr-gen-mode stable-privacy

}



routes() {
VPN_NAME="VPN UFC"

# Add static routes
ROUTES=(
    "193.52.61.0/24"
    "193.52.184.0/23"
    "193.54.75.0/24"
    "193.55.65.0/24"
    "193.55.66.0/23"
    "193.55.68.0/22"
    "194.57.76.0/22"
    "194.57.80.0/21"
    "194.57.88.0/22"
    "195.83.18.0/23"
    "195.83.112.0/23"
    "195.220.182.0/23"
    "195.220.184.0/23"
    "195.221.254.0/23"
    "172.16.0.0/16"
    "172.20.0.0/16"
    "172.21.0.0/16"
    "172.22.0.0/16"
    "172.23.0.0/16"
    "172.26.0.0/18"
    "172.28.0.0/16"
    "10.0.0.0/8"
    "130.79.200.0/24"
)

for route in "${ROUTES[@]}"; do
    nmcli connection modify "$VPN_NAME" +ipv4.routes "$ROUTES" || {
        echo "Failed to add route $route to $VPN_NAME"
        exit 1
    }
done
}

main() {
    choisir_distribution
    installer_paquets
    configurer_vpn
    if [ $distro -eq 1 ]; then
        routes
    fi
}

main