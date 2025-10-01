#!/bin/bash

# Photoprism Scanning Script for k3s
# Autor: Script for daily and weekly scanning of Photoprism
# Data: $(date +%Y-%m-%d)

# Konfiguracja
PHOTOPRISM_NAMESPACE="apps" # Namespace gdzie działa Photoprism
PHOTOPRISM_POD_LABEL="app=photoprism" # Etykieta poda Photoprism
LOG_DIR="/mnt/shared/Others/logs/photoprism"
LOG_FILE="$LOG_DIR/scan-$(date +%Y-%m-%d).log"
MAX_LOG_DAYS=30

# Kolory dla logów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funkcja logowania
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Funkcja sprawdzania czy pod Photoprism jest dostępny
check_photoprism_pod() {
    local pod_name=$(kubectl get pods -n "$PHOTOPRISM_NAMESPACE" -l "$PHOTOPRISM_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        log "ERROR" "Nie znaleziono poda Photoprism z etykietą: $PHOTOPRISM_POD_LABEL"
        return 1
    fi
    
    local pod_status=$(kubectl get pod "$pod_name" -n "$PHOTOPRISM_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$pod_status" != "Running" ]; then
        log "ERROR" "Pod Photoprism ($pod_name) nie jest w stanie Running. Aktualny status: $pod_status"
        return 1
    fi
    
    log "INFO" "Pod Photoprism znaleziony: $pod_name (Status: $pod_status)"
    echo "$pod_name"
    return 0
}

# Funkcja wykonywania skanowania
execute_scan() {
    local scan_type=$1
    local pod_name=$2
    
    log "INFO" "Rozpoczynanie $scan_type skanowania..."
    
    case $scan_type in
        "quick")
            local command="photoprism index --cleanup=false /photoprism/originals"
            log "INFO" "Wykonywanie szybkiego skanowania nowych plików w /mnt/shared/Photos"
            ;;
        "full")
            local command="photoprism index --cleanup=true /photoprism/originals && photoprism faces index"
            log "INFO" "Wykonywanie pełnego skanowania z czyszczeniem i indeksowaniem twarzy"
            ;;
        *)
            log "ERROR" "Nieznany typ skanowania: $scan_type"
            return 1
            ;;
    esac
    
    # Wykonanie komendy w podzie
    local start_time=$(date +%s)
    if kubectl exec -n "$PHOTOPRISM_NAMESPACE" "$pod_name" -- sh -c "$command" >> "$LOG_FILE" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "SUCCESS" "$scan_type skanowanie zakończone pomyślnie w czasie: ${duration}s"
        return 0
    else
        log "ERROR" "$scan_type skanowanie zakończone niepowodzeniem"
        return 1
    fi
}

# Funkcja czyszczenia starych logów
cleanup_old_logs() {
    if [ -d "$LOG_DIR" ]; then
        log "INFO" "Czyszczenie logów starszych niż $MAX_LOG_DAYS dni..."
        find "$LOG_DIR" -name "scan-*.log" -mtime +$MAX_LOG_DAYS -delete
        log "INFO" "Czyszczenie logów zakończone"
    fi
}

# Funkcja wyświetlania pomocy
show_help() {
    echo "Użycie: $0 [OPCJA]"
    echo ""
    echo "Opcje:"
    echo "  quick    Wykonaj szybkie skanowanie nowych plików"
    echo "  full     Wykonaj pełne skanowanie z czyszczeniem"
    echo "  help     Wyświetl tę pomoc"
    echo ""
    echo "Przykłady:"
    echo "  $0 quick    # Codzienne szybkie skanowanie"
    echo "  $0 full     # Tygodniowe pełne skanowanie"
}

# Funkcja główna
main() {
    # Tworzenie katalogu logów jeśli nie istnieje
    mkdir -p "$LOG_DIR"
    
    # Sprawdzenie argumentów
    if [ $# -eq 0 ]; then
        log "ERROR" "Brak argumentów. Użyj 'help' aby zobaczyć dostępne opcje."
        show_help
        exit 1
    fi
    
    case $1 in
        "quick"|"full")
            log "INFO" "=== Rozpoczynanie $1 skanowania Photoprism ==="
            
            # Sprawdzenie czy kubectl jest dostępne
            if ! command -v kubectl &> /dev/null; then
                log "ERROR" "kubectl nie jest zainstalowane lub niedostępne w PATH"
                exit 1
            fi
            
            # Sprawdzenie połączenia z klastrem
            if ! kubectl cluster-info &> /dev/null; then
                log "ERROR" "Brak połączenia z klastrem k3s"
                exit 1
            fi
            
            # Sprawdzenie poda Photoprism
            if pod_name=$(check_photoprism_pod); then
                # Wykonanie skanowania
                if execute_scan "$1" "$pod_name"; then
                    log "SUCCESS" "=== Skanowanie $1 zakończone pomyślnie ==="
                else
                    log "ERROR" "=== Skanowanie $1 zakończone niepowodzeniem ==="
                    exit 1
                fi
            else
                exit 1
            fi
            
            # Czyszczenie starych logów
            cleanup_old_logs
            ;;
        "help")
            show_help
            ;;
        *)
            log "ERROR" "Nieznana opcja: $1"
            show_help
            exit 1
            ;;
    esac
}

# Uruchomienie skryptu
main "$@"