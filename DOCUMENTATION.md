# Dokumentacja Skryptu photoprism-scan.sh

## Spis treści
1. [Przegląd](#przegląd)
2. [Architektura](#architektura)
3. [Konfiguracja](#konfiguracja)
4. [Funkcje](#funkcje)
5. [Użytkowanie](#użytkowanie)
6. [Logi](#logi)
7. [Rozwiązywanie problemów](#rozwiązywanie-problemów)
8. [Przykłady](#przykłady)
9. [API Reference](#api-reference)

---

## Przegląd

`photoprism-scan.sh` to zaawansowany skrypt bash do automatycznego skanowania biblioteki zdjęć w Photoprism działającym w środowisku Kubernetes (k3s). Skrypt zapewnia dwa tryby skanowania: szybki i pełny, z kompleksowym systemem logowania i obsługą błędów.

### Kluczowe funkcje:
- ✅ Automatyczne wykrywanie podów Photoprism w k3s
- ✅ Dwa tryby skanowania (quick/full)
- ✅ Kolorowe logi z timestampami
- ✅ Automatyczne czyszczenie starych logów
- ✅ Walidacja środowiska przed uruchomieniem
- ✅ Obsługa błędów i raportowanie statusu

---

## Architektura

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                            │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │   CRON JOBS     │    │  BASH SCRIPT    │    │    LOGS     │ │
│  │                 │    │                 │    │             │ │
│  │ Daily  01:00    │───▶│ photoprism-     │───▶│ /mnt/shared/│ │
│  │ Weekly 01:00    │    │ scan.sh         │    │ Others/logs/│ │
│  └─────────────────┘    └─────────────────┘    └─────────────┘ │
│                                 │                               │
│                                 ▼                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    KUBECTL                                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      K3S CLUSTER                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                   NAMESPACE: apps                          │ │
│  │  ┌─────────────────┐    ┌─────────────────────────────────┐ │ │
│  │  │ PHOTOPRISM POD  │    │        VOLUMES                  │ │ │
│  │  │                 │    │                                 │ │ │
│  │  │ app=photoprism  │◄───┤ /photoprism/originals          │ │ │
│  │  │                 │    │ (/mnt/shared/Photos)            │ │ │
│  │  └─────────────────┘    └─────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Konfiguracja

### Zmienne środowiskowe

```bash
# Główne zmienne konfiguracyjne (w skrypcie)
PHOTOPRISM_NAMESPACE="apps"                    # Namespace k3s
PHOTOPRISM_POD_LABEL="app=photoprism"          # Etykieta poda
LOG_DIR="/mnt/shared/Others/logs/photoprism"   # Katalog logów
MAX_LOG_DAYS=30                                # Retention logów
```

### Struktura katalogów

```
/home/zotac/photoprism-jobs/
├── photoprism-scan.sh              # Główny skrypt
└── [backup files]                  # Opcjonalne backupy

/mnt/shared/Others/logs/photoprism/
├── scan-2025-10-01.log            # Dzisiejsze logi
├── scan-2025-09-30.log            # Wczorajsze logi
└── [older logs...]                # Starsze logi (max 30 dni)

/etc/logrotate.d/
└── photoprism-scan                # Konfiguracja rotacji logów
```

### Wymagania systemowe

- **System operacyjny**: Ubuntu/Debian Linux
- **Uprawnienia**: kubectl dostęp dla użytkownika `zotac`
- **Narzędzia**: kubectl, bash 4.0+
- **Sieć**: Dostęp do klastra k3s
- **Pamięć**: Minimum 512MB RAM wolnego
- **Dysk**: Minimum 1GB wolnego miejsca na logi

---

## Funkcje

### 1. `log(level, message)`
**Opis**: Centralna funkcja logowania z kolorami i timestampami.

**Parametry**:
- `level`: INFO, WARN, ERROR, SUCCESS
- `message`: Treść wiadomości

**Przykład**:
```bash
log "INFO" "Rozpoczynanie skanowania..."
log "ERROR" "Błąd połączenia z klastrem"
```

### 2. `check_photoprism_pod()`
**Opis**: Sprawdza dostępność i status poda Photoprism.

**Zwraca**: 
- `0` + nazwa poda - sukces
- `1` - błąd

**Logika**:
1. Wyszukuje pod po etykiecie `$PHOTOPRISM_POD_LABEL`
2. Sprawdza status poda (musi być "Running")
3. Zwraca nazwę poda lub komunikat błędu

### 3. `execute_scan(scan_type, pod_name)`
**Opis**: Wykonuje skanowanie w podzie Photoprism.

**Parametry**:
- `scan_type`: "quick" lub "full"
- `pod_name`: Nazwa poda do wykonania skanowania

**Typy skanowania**:

#### Quick Scan
```bash
photoprism index --cleanup=false /photoprism/originals
```
- Skanuje tylko nowe pliki
- Nie wykonuje czyszczenia
- Szybsze wykonanie (5-15 min)
- Idealne do codziennego użytku

#### Full Scan
```bash
photoprism index --cleanup=true /photoprism/originals && photoprism faces index
```
- Pełne ponowne indeksowanie
- Czyszczenie nieaktualnych wpisów
- Indeksowanie twarzy
- Wolniejsze wykonanie (30-120 min)
- Idealne do tygodniowego użytku

### 4. `cleanup_old_logs()`
**Opis**: Usuwa logi starsze niż `$MAX_LOG_DAYS`.

**Logika**:
```bash
find "$LOG_DIR" -name "scan-*.log" -mtime +$MAX_LOG_DAYS -delete
```

### 5. `show_help()`
**Opis**: Wyświetla instrukcje użytkowania.

---

## Użytkowanie

### Składnia
```bash
photoprism-scan.sh [OPCJA]
```

### Opcje
- `quick` - Szybkie skanowanie nowych plików
- `full` - Pełne skanowanie z czyszczeniem
- `help` - Wyświetl pomoc

### Przykłady użycia

#### Ręczne uruchamianie
```bash
# Szybkie skanowanie
/home/zotac/photoprism-jobs/photoprism-scan.sh quick

# Pełne skanowanie
/home/zotac/photoprism-jobs/photoprism-scan.sh full

# Pomoc
/home/zotac/photoprism-jobs/photoprism-scan.sh help
```

#### Automatyczne harmonogramy (cron)
```bash
# Codziennie o 1:00 - szybkie skanowanie
0 1 * * * /home/zotac/photoprism-jobs/photoprism-scan.sh quick

# Poniedziałki o 1:00 - pełne skanowanie
0 1 * * 1 /home/zotac/photoprism-jobs/photoprism-scan.sh full
```

### Kody wyjścia
- `0` - Sukces
- `1` - Błąd (brak argumentów, błąd kubectl, błąd skanowania)

---

## Logi

### Format logów
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] MESSAGE
```

### Przykład logu
```
[2025-10-01 01:00:00] [INFO] === Rozpoczynanie quick skanowania Photoprism ===
[2025-10-01 01:00:01] [INFO] Pod Photoprism znaleziony: photoprism-7d8f9c-xyz (Status: Running)
[2025-10-01 01:00:01] [INFO] Wykonywanie szybkiego skanowania nowych plików w /mnt/shared/Photos
[2025-10-01 01:05:30] [SUCCESS] quick skanowanie zakończone pomyślnie w czasie: 329s
[2025-10-01 01:05:30] [INFO] Czyszczenie logów starszych niż 30 dni...
[2025-10-01 01:05:30] [SUCCESS] === Skanowanie quick zakończone pomyślnie ===
```

### Poziomy logowania

| Poziom | Kolor | Opis |
|--------|-------|------|
| INFO | 🔵 Niebieski | Informacje o przebiegu |
| WARN | 🟡 Żółty | Ostrzeżenia |
| ERROR | 🔴 Czerwony | Błędy krytyczne |
| SUCCESS | 🟢 Zielony | Operacje zakończone sukcesem |

### Monitoring logów
```bash
# Logi na żywo
tail -f /mnt/shared/Others/logs/photoprism/scan-$(date +%Y-%m-%d).log

# Ostatnie 50 linii
tail -50 /mnt/shared/Others/logs/photoprism/scan-$(date +%Y-%m-%d).log

# Szukanie błędów
grep -i error /mnt/shared/Others/logs/photoprism/scan-*.log

# Statystyki skanowania
grep -i "zakończone pomyślnie" /mnt/shared/Others/logs/photoprism/scan-*.log
```

---

## Rozwiązywanie problemów

### 1. Pod Photoprism nie został znaleziony

**Objawy**:
```
[ERROR] Nie znaleziono poda Photoprism z etykietą: app=photoprism
```

**Diagnoza**:
```bash
# Sprawdź wszystkie pody w namespace apps
kubectl get pods -n apps

# Sprawdź etykiety podów
kubectl get pods -n apps --show-labels | grep photoprism

# Sprawdź czy pod działa
kubectl describe pod <pod-name> -n apps
```

**Rozwiązania**:
1. Sprawdź czy Photoprism jest uruchomiony
2. Zweryfikuj namespace (domyślnie: `apps`)
3. Sprawdź etykietę poda (domyślnie: `app=photoprism`)
4. Dostosuj zmienne w skrypcie jeśli potrzeba

### 2. Błędy uprawnień kubectl

**Objawy**:
```
[ERROR] Brak połączenia z klastrem k3s
error: You must be logged in to the server (Unauthorized)
```

**Diagnoza**:
```bash
# Jako użytkownik zotac
kubectl cluster-info
kubectl get nodes
ls -la ~/.kube/
```

**Rozwiązania**:
1. Sprawdź konfigurację kubeconfig
2. Zweryfikuj uprawnienia użytkownika zotac
3. Sprawdź czy certyfikaty nie wygasły

### 3. Błędy skanowania Photoprism

**Objawy**:
```
[ERROR] quick skanowanie zakończone niepowodzeniem
```

**Diagnoza**:
```bash
# Sprawdź logi Photoprism
kubectl logs <pod-name> -n apps

# Sprawdź czy volumes są zamontowane
kubectl exec <pod-name> -n apps -- ls -la /photoprism/originals

# Sprawdź procesy w podzie
kubectl exec <pod-name> -n apps -- ps aux
```

**Rozwiązania**:
1. Zweryfikuj montowanie volume `/mnt/shared/Photos`
2. Sprawdź dostępność plików w kontenerze
3. Sprawdź zasoby systemowe (CPU/RAM)
4. Sprawdź logi aplikacji Photoprism

### 4. Problemy z logami

**Objawy**:
```bash
mkdir: cannot create directory '/mnt/shared/Others/logs/photoprism': Permission denied
```

**Rozwiązania**:
```bash
# Utwórz katalog z odpowiednimi uprawnieniami
sudo mkdir -p /mnt/shared/Others/logs/photoprism
sudo chown zotac:zotac /mnt/shared/Others/logs/photoprism
sudo chmod 755 /mnt/shared/Others/logs/photoprism

# Sprawdź uprawnienia
ls -la /mnt/shared/Others/logs/
```

### 5. Problemy z cron

**Objawy**: Zadania się nie wykonują

**Diagnoza**:
```bash
# Sprawdź cron jobs
crontab -l

# Sprawdź logi systemowe
grep photoprism /var/log/syslog

# Sprawdź status crond
systemctl status cron
```

---

## Przykłady

### Typowy przepływ pracy

```bash
# 1. Ręczne testowanie
/home/zotac/photoprism-jobs/photoprism-scan.sh quick

# 2. Sprawdzenie logów
tail -f /mnt/shared/Others/logs/photoprism/scan-$(date +%Y-%m-%d).log

# 3. Analiza wydajności
grep "zakończone pomyślnie w czasie" /mnt/shared/Others/logs/photoprism/scan-*.log

# 4. Sprawdzenie statusu podów
kubectl get pods -n apps -l app=photoprism

# 5. Monitoring zasobów
kubectl top pods -n apps
```

### Skrypt diagnostyczny

```bash
#!/bin/bash
# diagnostic.sh - Skrypt diagnostyczny dla Photoprism

echo "=== DIAGNOSTYKA PHOTOPRISM SCAN ==="

echo "1. Status klastra k3s:"
kubectl cluster-info

echo "2. Pody Photoprism:"
kubectl get pods -n apps -l app=photoprism

echo "3. Ostatnie logi skanowania:"
tail -20 /mnt/shared/Others/logs/photoprism/scan-$(date +%Y-%m-%d).log

echo "4. Cron jobs:"
crontab -l | grep photoprism

echo "5. Uprawnienia katalogów:"
ls -la /mnt/shared/Others/logs/photoprism/

echo "=== KONIEC DIAGNOSTYKI ==="
```

---

## API Reference

### Zmienne globalne

| Zmienna | Typ | Domyślna wartość | Opis |
|---------|-----|------------------|------|
| `PHOTOPRISM_NAMESPACE` | string | "apps" | Namespace k3s |
| `PHOTOPRISM_POD_LABEL` | string | "app=photoprism" | Etykieta poda |
| `LOG_DIR` | string | "/mnt/shared/Others/logs/photoprism" | Katalog logów |
| `LOG_FILE` | string | "$LOG_DIR/scan-$(date +%Y-%m-%d).log" | Plik logu |
| `MAX_LOG_DAYS` | integer | 30 | Retention logów (dni) |

### Funkcje

#### `log(level, message)`
Centralna funkcja logowania.

**Parametry**:
- `level` (string): "INFO", "WARN", "ERROR", "SUCCESS"
- `message` (string): Treść komunikatu

**Zwraca**: void

**Side effects**: 
- Zapisuje do `$LOG_FILE`
- Wyświetla kolorowy output na stdout

#### `check_photoprism_pod()`
Sprawdza dostępność poda Photoprism.

**Parametry**: brak

**Zwraca**: 
- `0` + echo pod_name - sukces
- `1` - błąd

**Side effects**: Loguje status operacji

#### `execute_scan(scan_type, pod_name)`
Wykonuje skanowanie w podzie.

**Parametry**:
- `scan_type` (string): "quick" lub "full"
- `pod_name` (string): Nazwa poda

**Zwraca**:
- `0` - sukces
- `1` - błąd

**Side effects**: 
- Wykonuje kubectl exec
- Loguje progress i wyniki
- Mierzy czas wykonania

#### `cleanup_old_logs()`
Usuwa stare pliki logów.

**Parametry**: brak

**Zwraca**: void

**Side effects**: Usuwa pliki starsze niż `$MAX_LOG_DAYS`

#### `show_help()`
Wyświetla pomoc.

**Parametry**: brak

**Zwraca**: void

**Side effects**: Wypisuje help na stdout

#### `main(args...)`
Główna funkcja programu.

**Parametry**: 
- `args` (array): Argumenty linii poleceń

**Zwraca**:
- `0` - sukces
- `1` - błąd

**Side effects**: Wykonuje pełny workflow skanowania

---

## Historia zmian

### v1.0 (2025-10-01)
- ✅ Pierwsza wersja robocza
- ✅ Obsługa namespace "apps"
- ✅ Logi w /mnt/shared/Others/logs/photoprism
- ✅ Kolorowe logowanie
- ✅ Automatyczne czyszczenie logów

### Planowane funkcje
- 🔄 Integracja z systemami monitoringu (Prometheus)
- 🔄 Notyfikacje e-mail przy błędach
- 🔄 Konfiguracja przez plik YAML
- 🔄 Metryki wydajności skanowania
- 🔄 Backup bazy danych przed pełnym skanowaniem

---

**Autor**: System automatyzacji Photoprism  
**Data**: Październik 2025  
**Wersja**: 1.0