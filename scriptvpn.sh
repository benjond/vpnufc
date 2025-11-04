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
            autoriser_selinux
            ;;
        3)
            sudo pacman -S --needed --noconfirm strongswan networkmanager-strongswan
            
            ;;
        4)
            sudo zypper install -y strongswan NetworkManager-strongswan NetworkManager-strongswan-gnome
            autoriser_selinux
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
    "address=vpn20-2.univ-fcomte.fr, encap=yes, esp=aes256-sha1, ike=aes256-sha1-modp1024, ipcomp=no, method=eap, proposal=no, user=$username@ufc, virtual=yes, service-type=org.freedesktop.NetworkManager.strongswan" \
    vpn.secrets \
    "password=$password" \
    ipv4.method auto \
    ipv6.method auto \
    ipv6.addr-gen-mode stable-privacy
    
    sudo nmcli connection modify "VPN UFC" ipv4.never-default no
    
    # Ajouter le certificat CA en éditant directement le fichier de configuration NetworkManager
    echo ""
    echo "Configuration du certificat CA..."

    CA_NAME="USERTrust_RSA_Certification_Authority.pem"
    CA_DST="/etc/ssl/certs/${CA_NAME}"

    # Fedora specific: extract the USERTrust RSA CA directly into a PEM file
    if [ "$distro" -eq 2 ]; then
        echo "Distribution: Fedora — extraction du certificat CA via 'trust'..."
        # Use 'trust' to extract the specific CA into the expected path
        sudo trust extract --format=pem --filter "USERTrust RSA Certification Authority" "$CA_DST" 2>/dev/null || true
        if [ -f "$CA_DST" ]; then
            echo "Certificat extrait vers $CA_DST"
        else
            echo "Échec de l'extraction du certificat avec 'trust'. Vérifiez que le CA existe dans le magasin système." 
        fi
    fi

    # Trouver le fichier de connexion (peut avoir un nom encodé)
    CONN_FILE=$(sudo find /etc/NetworkManager/system-connections/ -type f -name "*VPN*UFC*.nmconnection" 2>/dev/null | head -1)

    if [ -z "$CONN_FILE" ]; then
        # Essayer sans extension .nmconnection
        CONN_FILE=$(sudo find /etc/NetworkManager/system-connections/ -type f -name "*VPN*UFC*" 2>/dev/null | head -1)
    fi

    if [ -z "$CONN_FILE" ]; then
        # Essayer avec le nom exact entre guillemets
        CONN_FILE="/etc/NetworkManager/system-connections/VPN UFC.nmconnection"
    fi

    if [ -f "$CONN_FILE" ]; then
        echo "Fichier de configuration trouvé : $CONN_FILE"
        # Vérifier si le certificat n'est pas déjà présent
        if ! sudo grep -q "^certificate=" "$CONN_FILE"; then
            if [ -f "$CA_DST" ]; then
                # Ajouter la ligne certificate= dans la section [vpn]
                sudo sed -i '/^\[vpn\]/a certificate='"$CA_DST" "$CONN_FILE"
                sudo chmod 600 "$CONN_FILE"
                sudo nmcli connection reload || true
                # Sur Fedora on restart NetworkManager to be safe
                if [ "$distro" -eq 2 ]; then
                    sudo systemctl restart NetworkManager || true
                fi
                echo "Certificat CA ajouté avec succès : $CA_DST"
            else
                echo "Impossible d'ajouter le certificat : $CA_DST introuvable."
                echo "Si vous êtes sur Fedora, placez ${CA_NAME} dans le répertoire courant ou vérifiez le magasin de certificats." 
            fi
        else
            echo "Le certificat est déjà configuré."
        fi
    else
        echo "ATTENTION : Fichier de configuration introuvable. Le certificat devra être ajouté manuellement."
        echo "Recherchez le fichier avec : sudo ls -la /etc/NetworkManager/system-connections/"
    fi


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
    # Some distributions (e.g. OpenSUSE) ship getenforce in /usr/sbin and it may require sudo.
    GETENFORCE_CMD=""
    if command -v getenforce >/dev/null 2>&1; then
        GETENFORCE_CMD="getenforce"
    elif [ -x /usr/sbin/getenforce ]; then
        GETENFORCE_CMD="sudo /usr/sbin/getenforce"
    elif [ -x /sbin/getenforce ]; then
        GETENFORCE_CMD="sudo /sbin/getenforce"
    else
        echo "SELinux non détecté (pas de getenforce). Aucune action SELinux effectuée."
        return
    fi

    selinux_status="$($GETENFORCE_CMD 2>/dev/null || echo Disabled)"
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
