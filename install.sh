#!/bin/bash

# Skrypt instalacyjny dla Photoprism Cron Jobs
# Ten skrypt konfiguruje automatyczne skanowanie Photoprism w k3s

set -e

# Kolory dla komunikatów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Konfiguracja
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="zotac"
TARGET_SERVER="192.168.1.109"
INSTALL_DIR="/home/$TARGET_USER/photoprism-jobs"
LOG_DIR="/mnt/shared/Others/logs/photoprism"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Funkcja sprawdzenia czy skrypt jest uruchamiany na odpowiednim serwerze
check_environment() {
    print_info "Sprawdzanie środowiska..."
    
    # Sprawdzenie czy jesteśmy na odpowiednim serwerze
    local current_ip=$(hostname -I | awk '{print $1}')
    if [[ "$current_ip" != "$TARGET_SERVER" ]]; then
        print_warning "Skrypt nie jest uruchamiany na serwerze $TARGET_SERVER (aktualny: $current_ip)"
        print_info "Czy chcesz kontynuować instalację? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Instalacja przerwana przez użytkownika"
            exit 0
        fi
    fi
    
    # Sprawdzenie czy użytkownik istnieje
    if ! id "$TARGET_USER" &>/dev/null; then
        print_error "Użytkownik $TARGET_USER nie istnieje w systemie"
        exit 1
    fi
    
    # Sprawdzenie czy kubectl jest dostępne
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl nie jest zainstalowane lub niedostępne w PATH"
        exit 1
    fi
    
    # Sprawdzenie połączenia z k3s
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Brak połączenia z klastrem k3s"
        exit 1
    fi
    
    print_success "Środowisko sprawdzone pomyślnie"
}

# Funkcja tworzenia katalogów
create_directories() {
    print_info "Tworzenie katalogów..."
    
    # Tworzenie katalogu instalacyjnego
    sudo -u "$TARGET_USER" mkdir -p "$INSTALL_DIR"
    sudo -u "$TARGET_USER" mkdir -p "$LOG_DIR"
    
    print_success "Katalogi utworzone: $INSTALL_DIR, $LOG_DIR"
}

# Funkcja kopiowania plików
install_files() {
    print_info "Instalowanie plików..."
    
    # Kopiowanie głównego skryptu
    sudo cp "$SCRIPT_DIR/photoprism-scan.sh" "$INSTALL_DIR/"
    sudo chown "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR/photoprism-scan.sh"
    sudo chmod +x "$INSTALL_DIR/photoprism-scan.sh"
    
    print_success "Skrypt główny zainstalowany: $INSTALL_DIR/photoprism-scan.sh"
}

# Funkcja konfiguracji logrotate
setup_logrotate() {
    print_info "Konfigurowanie logrotate..."
    
    # Kopiowanie konfiguracji logrotate
    sudo cp "$SCRIPT_DIR/logrotate-photoprism" "/etc/logrotate.d/photoprism-scan"
    sudo chmod 644 "/etc/logrotate.d/photoprism-scan"
    
    # Testowanie konfiguracji logrotate
    if sudo logrotate -d /etc/logrotate.d/photoprism-scan &> /dev/null; then
        print_success "Logrotate skonfigurowany pomyślnie"
    else
        print_warning "Błąd w konfiguracji logrotate - sprawdź ręcznie"
    fi
}

# Funkcja konfiguracji cron jobs
setup_cron_jobs() {
    print_info "Konfigurowanie cron jobs..."
    
    # Tworzenie tymczasowego pliku cron
    local temp_cron=$(mktemp)
    
    # Pobieranie aktualnego crona użytkownika
    sudo -u "$TARGET_USER" crontab -l 2>/dev/null > "$temp_cron" || true
    
    # Sprawdzanie czy zadania już istnieją
    if grep -q "photoprism-scan.sh" "$temp_cron"; then
        print_warning "Zadania cron dla Photoprism już istnieją. Czy chcesz je zaktualizować? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Pomijanie konfiguracji cron"
            rm "$temp_cron"
            return
        fi
        
        # Usuwanie starych wpisów
        grep -v "photoprism-scan.sh" "$temp_cron" > "${temp_cron}.new" || true
        mv "${temp_cron}.new" "$temp_cron"
    fi
    
    # Dodawanie nowych zadań cron
    cat >> "$temp_cron" << EOF

# Photoprism Scanning Jobs
# Codzienne szybkie skanowanie o 1:00
0 1 * * * $INSTALL_DIR/photoprism-scan.sh quick

# Tygodniowe pełne skanowanie (niedziela na poniedziałek o 1:00)
0 1 * * 1 $INSTALL_DIR/photoprism-scan.sh full

EOF
    
    # Instalowanie nowego crona
    sudo -u "$TARGET_USER" crontab "$temp_cron"
    rm "$temp_cron"
    
    print_success "Cron jobs skonfigurowane:"
    print_info "  - Codzienne szybkie skanowanie: 1:00"
    print_info "  - Tygodniowe pełne skanowanie: Poniedziałek 1:00"
}

# Funkcja testowania instalacji
test_installation() {
    print_info "Testowanie instalacji..."
    
    # Test podstawowy - sprawdzenie czy skrypt się uruchamia
    if sudo -u "$TARGET_USER" "$INSTALL_DIR/photoprism-scan.sh" help &> /dev/null; then
        print_success "Skrypt uruchamia się poprawnie"
        
        # Wyświetlenie pomocy
        print_info "Dostępne opcje skryptu:"
        sudo -u "$TARGET_USER" "$INSTALL_DIR/photoprism-scan.sh" help
    else
        print_error "Skrypt nie uruchamia się poprawnie"
        return 1
    fi
    
    # Test dostępu do k3s
    print_info "Testowanie dostępu do Photoprism w k3s..."
    if sudo -u "$TARGET_USER" kubectl get pods -l app=photoprism &> /dev/null; then
        print_success "Dostęp do k3s i Photoprism działa"
    else
        print_warning "Nie można znaleźć podów Photoprism - sprawdź konfigurację k3s"
        print_info "Możliwe przyczyny:"
        print_info "  - Pod Photoprism nie jest uruchomiony"
        print_info "  - Nieprawidłowa etykieta poda (sprawdź PHOTOPRISM_POD_LABEL w skrypcie)"
        print_info "  - Problemy z uprawnieniami kubectl dla użytkownika $TARGET_USER"
    fi
}

# Funkcja wyświetlania podsumowania
show_summary() {
    print_success "=== INSTALACJA ZAKOŃCZONA ==="
    echo ""
    print_info "Pliki zainstalowane w: $INSTALL_DIR"
    print_info "Logi będą zapisywane w: $LOG_DIR"
    print_info "Konfiguracja logrotate: /etc/logrotate.d/photoprism-scan"
    echo ""
    print_info "Harmonogram skanowania:"
    print_info "  • Codziennie o 1:00 - szybkie skanowanie nowych plików"
    print_info "  • Poniedziałki o 1:00 - pełne skanowanie z czyszczeniem"
    echo ""
    print_info "Ręczne uruchamianie:"
    print_info "  sudo -u $TARGET_USER $INSTALL_DIR/photoprism-scan.sh quick"
    print_info "  sudo -u $TARGET_USER $INSTALL_DIR/photoprism-scan.sh full"
    echo ""
    print_info "Sprawdzenie cron jobs:"
    print_info "  sudo -u $TARGET_USER crontab -l"
    echo ""
    print_info "Monitorowanie logów:"
    print_info "  tail -f $LOG_DIR/scan-\$(date +%Y-%m-%d).log"
}

# Funkcja główna
main() {
    print_info "=== INSTALATOR PHOTOPRISM CRON JOBS ==="
    print_info "Serwer docelowy: $TARGET_SERVER"
    print_info "Użytkownik: $TARGET_USER"
    echo ""
    
    # Sprawdzenie uprawnień root
    if [[ $EUID -ne 0 ]]; then
        print_error "Ten skrypt musi być uruchamiany jako root (sudo)"
        exit 1
    fi
    
    # Wykonanie kroków instalacji
    check_environment
    create_directories
    install_files
    setup_logrotate
    setup_cron_jobs
    test_installation
    show_summary
    
    print_success "Instalacja zakończona pomyślnie!"
}

# Uruchomienie instalatora
main "$@"