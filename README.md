# Photoprism Cron Jobs for k3s

Automatyczne skanowanie Photoprism działającego w k3s na serwerze 192.168.1.109.

## Opis

Ten projekt zawiera skrypty do automatycznego skanowania zdjęć w Photoprism:
- **Codzienne szybkie skanowanie** o 1:00 - wyszukuje nowe pliki w `/mnt/shared/Photos`
- **Tygodniowe pełne skanowanie** w noce z niedzieli na poniedziałek o 1:00 - pełne skanowanie z czyszczeniem

## Zawartość projektu

```
PhotoprismJob/
├── README.md              # Ta dokumentacja
├── install.sh             # Skrypt instalacyjny
├── photoprism-scan.sh     # Główny skrypt skanowania  
└── logrotate-photoprism   # Konfiguracja rotacji logów
```

## Wymagania

- Serwer z zainstalowanym k3s
- Użytkownik `zotac` z dostępem do kubectl
- Photoprism działający w k3s z etykietą `app=photoprism`
- Uprawnienia sudo do instalacji

## Instalacja

### 1. Skopiowanie plików na serwer

```bash
# Skopiuj projekt na serwer
scp -r PhotoprismJob/ zotac@192.168.1.109:~/
```

### 2. Uruchomienie instalatora

```bash
# Zaloguj się na serwer
ssh zotac@192.168.1.109

# Przejdź do katalogu projektu
cd ~/PhotoprismJob

# Uruchom instalator jako root
sudo ./install.sh
```

Instalator automatycznie:
- Sprawdzi środowisko i zależności
- Utworzy niezbędne katalogi
- Zainstaluje skrypty w `/home/zotac/photoprism-jobs/`
- Skonfiguruje logrotate
- Doda zadania do cron
- Przeprowadzi test instalacji

## Konfiguracja

### Dostosowanie do środowiska

Jeśli Twoja instalacja Photoprism różni się od domyślnej, edytuj `photoprism-scan.sh`:

```bash
# Namespace w którym działa Photoprism
PHOTOPRISM_NAMESPACE="default"

# Etykieta poda Photoprism
PHOTOPRISM_POD_LABEL="app=photoprism"
```

### Harmonogram skanowania

Domyślny harmonogram (można zmienić w cron):
```bash
# Codzienne szybkie skanowanie o 1:00
0 1 * * * /home/zotac/photoprism-jobs/photoprism-scan.sh quick

# Tygodniowe pełne skanowanie (poniedziałek o 1:00)  
0 1 * * 1 /home/zotac/photoprism-jobs/photoprism-scan.sh full
```

## Użytkowanie

### Ręczne uruchamianie

```bash
# Szybkie skanowanie nowych plików
/home/zotac/photoprism-jobs/photoprism-scan.sh quick

# Pełne skanowanie z czyszczeniem
/home/zotac/photoprism-jobs/photoprism-scan.sh full

# Wyświetlenie pomocy
/home/zotac/photoprism-jobs/photoprism-scan.sh help
```

### Sprawdzanie statusu

```bash
# Sprawdzenie cron jobs
crontab -l

# Monitorowanie logów w czasie rzeczywistym
tail -f /home/zotac/logs/photoprism/scan-$(date +%Y-%m-%d).log

# Sprawdzenie ostatnich logów
ls -la /home/zotac/logs/photoprism/
```

### Sprawdzenie podów Photoprism

```bash
# Lista podów Photoprism
kubectl get pods -l app=photoprism

# Szczegóły poda
kubectl describe pod <nazwa-poda>

# Logi Photoprism
kubectl logs <nazwa-poda>
```

## Logi

### Lokalizacja logów
- Katalog logów: `/home/zotac/logs/photoprism/`
- Format nazwy: `scan-YYYY-MM-DD.log`
- Automatyczna rotacja: 30 dni (konfiguracja logrotate)

### Struktura logów
```
[2025-10-01 01:00:00] [INFO] === Rozpoczynanie quick skanowania Photoprism ===
[2025-10-01 01:00:01] [INFO] Pod Photoprism znaleziony: photoprism-xxx (Status: Running)
[2025-10-01 01:00:01] [INFO] Wykonywanie szybkiego skanowania nowych plików w /mnt/shared/Photos
[2025-10-01 01:05:30] [SUCCESS] quick skanowanie zakończone pomyślnie w czasie: 329s
[2025-10-01 01:05:30] [SUCCESS] === Skanowanie quick zakończone pomyślnie ===
```

## Rozwiązywanie problemów

### Problem: Nie można znaleźć poda Photoprism

```bash
# Sprawdź czy pod działa
kubectl get pods -A | grep photoprism

# Sprawdź etykiety poda
kubectl get pods --show-labels | grep photoprism

# Dostosuj PHOTOPRISM_POD_LABEL w skrypcie jeśli potrzeba
```

### Problem: Błędy uprawnień kubectl

```bash
# Sprawdź dostęp kubectl dla użytkownika zotac
sudo -u zotac kubectl cluster-info

# Sprawdź konfigurację kubeconfig
sudo -u zotac ls -la ~/.kube/
```

### Problem: Skanowanie kończy się błędem

```bash
# Sprawdź logi szczegółowe
tail -50 /home/zotac/logs/photoprism/scan-$(date +%Y-%m-%d).log

# Sprawdź czy katalog /mnt/shared/Photos jest dostępny w podzie
kubectl exec <pod-name> -- ls -la /photoprism/originals

# Sprawdź logi Photoprism
kubectl logs <pod-name>
```

### Problem: Zadania cron nie działają

```bash
# Sprawdź czy cron jest aktywny
systemctl status cron

# Sprawdź logi cron
grep photoprism /var/log/syslog

# Sprawdź cron jobs użytkownika
sudo -u zotac crontab -l
```

## Bezpieczeństwo

- Logi są zapisywane z ograniczonymi uprawnieniami (644)
- Skrypty działają tylko w kontekście użytkownika `zotac`
- Automatyczne czyszczenie starych logów
- Walidacja środowiska przed każdym uruchomieniem

## Aktualizacje

Aby zaktualizować skrypty:

1. Skopiuj nowe wersje plików na serwer
2. Uruchom ponownie `install.sh`
3. Instalator automatycznie zaktualizuje pliki i zachowa istniejące zadania cron

## Autor

Skrypt przygotowany dla automatyzacji Photoprism w środowisku k3s.

Data utworzenia: Październik 2025