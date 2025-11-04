#!/bin/bash

# Ce script permet d'installer et de configuer le vpn Strongswan de l'IUT NFC

function choisir_distribution() {
    echo "1) Debian/Ubuntu/Mint"
    echo "2) Fedora"
    echo "3) Arch/Manjaro"
    echo "4) OpenSUSE"
    echo "5) DNS"

    read -p "Choisissez votre distribution: " distro
}

function installer_paquets() {
    case $distro in
        1)
            sudo apt update -y
            sudo apt install -y network-manager-strongswan libstrongswan-extra-plugins libcharon-extra-plugins 
            ;;
        2)
            sudo dnf install -y strongswan NetworkManager-strongswan NetworkManager-strongswan-gnome
            ;;
        3)
            sudo pacman -S --needed --noconfirm strongswan networkmanager-strongswan
            autoriser_selinux
            ;;
        4)
            sudo zypper install -y strongswan NetworkManager-strongswan NetworkManager-strongswan-gnome
            ;;
        5)
            creer_fichiers_dns
            autoriser_selinux
            ;;
        *)
            echo "Erreur: distribution inconnue"
            exit 1
            ;;
    esac
}

function configurer_vpn() {
    # Supprimer toutes les connexions VPN existantes (actives ou non)
    vpn_connections="$(sudo nmcli --terse --fields NAME,TYPE connection show | grep vpn | cut -d: -f1)"
    sudo nmcli connection delete "$vpn_connections" > /dev/null
    echo "Veuillez entrer vos identifiants de connexion"
    read -p "Nom d'utilisateur: " username
    read -sp "Mot de passe: " password

    sudo nmcli connection add type vpn \
    vpn-type strongswan \
    connection.id "VPN UFC" \
    connection.autoconnect no \
    vpn.data \
    "address=vpn20-2.univ-fcomte.fr, ca=/etc/ssl/certs/USERTrust_RSA_Certification_Authority.pem, encap=yes, esp=aes256-sha1, ike=aes256-sha1-modp1024, ipcomp=no, method=eap, proposal=no, user=$username@ufc, virtual=yes, service-type=org.freedesktop.NetworkManager.strongswan" \
    vpn.secrets \
    "password=$password" \
    ipv4.method auto \
    ipv6.method auto \
    ipv6.addr-gen-mode stable-privacy
    
    sudo nmcli connection modify "VPN UFC" ipv4.never-default no


}

function routes() {
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
        nmcli connection modify "$VPN_NAME" +ipv4.routes "$route"
    done
}

function creer_fichiers_dns() {



    # Ensure the DNS configuration is managed by NetworkManager
    sudo nmcli connection modify "VPN UFC" ipv4.dns-search "univ-fcomte.fr"
    sudo nmcli connection modify "VPN UFC" ipv4.dns "127.0.0.53"
    sudo nmcli connection modify "VPN UFC" ipv4.dns-options "edns0,trust-ad"


    sudo systemctl restart NetworkManager


    
  
}

function autoriser_selinux() {
    # Detect SELinux and try to apply safe, conservative authorisations for strongSwan
    if ! command -v getenforce >/dev/null 2>&1; then
        echo "SELinux non détecté (pas de getenforce). Aucune action SELinux effectuée."
        return
    fi

    selinux_status="$(getenforce 2>/dev/null || echo Disabled)"
    if [ "$selinux_status" != "Enforcing" ]; then
        echo "SELinux status: $selinux_status — aucune action nécessaire."
        return
    fi

    read -p "SELinux est en mode Enforcing. Voulez-vous que le script tente d'autoriser strongSwan maintenant ? [y/N] " answer
    case "$answer" in
        [yY]) ;;
        *) echo "Changements SELinux ignorés par l'utilisateur."; return ;;
    esac

    echo "Installation des outils SELinux nécessaires (si absents)..."
    if [ $distro -eq 2 ]; then
        sudo dnf install -y policycoreutils-python-utils checkpolicy setools-console || true
    elif [ $distro -eq 4 ]; then
        sudo zypper install -y policycoreutils-python-utils checkpolicy setools-console || true
    fi

    # Try to find and install any shipped strongSwan SELinux policy module
    echo "Recherche d'un module SELinux fourni pour strongSwan..."
    found_module=0
    for f in /usr/share/selinux/*/*strongswan*.pp /usr/share/selinux/*/strongswan.pp /usr/share/selinux/strongswan/*.pp; do
        if [ -f "$f" ]; then
            echo "Module trouvé : $f — installation..."
            sudo semodule -i "$f" && found_module=1 && break || true
        fi
    done

    if [ "$found_module" -eq 1 ]; then
        echo "Module SELinux strongSwan installé (si compatible)."
        return
    fi

    echo "Aucun module SELinux explicite trouvé. Tentative d'ajout de domaines permissifs courants (peut échouer sans effet si le domaine n'existe pas)."
    # Semanage permissive is a pragmatic fallback; it may fail harmlessly if domain names differ.
    for domain in charon_t ipsec_t strongswan_t; do
        if command -v semanage >/dev/null 2>&1; then
            sudo semanage permissive -a "$domain" 2>/dev/null || true
        fi
    done

    echo "Opérations SELinux terminées."
}

main() {
    choisir_distribution
    if [ $distro -eq 5 ]; then
        exit 1
    fi
    installer_paquets
    configurer_vpn
    if [ $distro -eq 1 ]; then
        routes
        creer_fichiers_dns
    fi
    
}

main
