#!/usr/bin/python
# -*- coding: utf-8 -*-

import time
import telepot
from telepot.loop import MessageLoop
import telegram
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import subprocess
# GPIO - use real library on Pi, mock on other platforms
try:
    import RPi.GPIO as GPIO
    GPIO_AVAILABLE = True
except (ImportError, RuntimeError):
    # Mock GPIO for development on non-Pi systems
    class MockGPIO:
        BOARD = BCM = OUT = IN = HIGH = LOW = 1
        def setmode(self, *args): pass
        def setwarnings(self, *args): pass
        def setup(self, *args, **kwargs): pass
        def output(self, *args): pass
        def input(self, *args): return 0
        def cleanup(self): pass
    GPIO = MockGPIO()
    GPIO_AVAILABLE = False
    print("Note: Running with mock GPIO (not on Raspberry Pi)")
import re
import os
import threading
import requests
import bitcoin
import json

# New imports for HD wallet functionality
from mnemonic import Mnemonic
import bip32utils

# Run some system checks (optional)
os.system('pwd')
os.system('cd ~')
os.system('df -h')
os.system('ls -la')
stream = os.popen('ls -la')
stream = os.popen('df -h')
output = stream.readlines()

# Global flag variables
flag1 = False
flag2 = False
flag3 = False
flag4 = False
flag5 = False
flag6 = False
flag7 = False  # Flag for /chkinterval two-step process

# Set up GPIO output channels
GPIO.setmode(GPIO.BOARD)
GPIO.setwarnings(False)
GPIO.setup(11, GPIO.OUT)
GPIO.setup(12, GPIO.OUT)

# --- Dynamic Variable Loader ---
# The botdata.txt file should have:
# Line 1: ADMIN_ID
# Line 2: TOKEN
# Line 3: wallet_address
# Line 4: api_key
def load_variables():
    file_path = "/home/pi/botdata.txt"
    global ADMIN_ID, TOKEN, wallet_address, api_key
    try:
        with open(file_path, "r") as f:
            lines = f.readlines()
            if len(lines) >= 4:
                ADMIN_ID = int(lines[0].strip())   # First line: ADMIN_ID
                TOKEN = lines[1].strip()             # Second line: TOKEN
                wallet_address = lines[2].strip()    # Third line: wallet_address
                api_key = lines[3].strip()           # Fourth line: api_key
            else:
                print("Error: botdata.txt does not contain the required 4 lines.")
    except Exception as e:
        print(f"Error reading botdata.txt: {e}")

# Initial load of variables
load_variables()

MESSAGE = 'BTC Loto BOT is back online!'
bot = telegram.Bot(token=TOKEN)
bot.send_message(chat_id=ADMIN_ID, text=MESSAGE)

# LED control functions
def on(pin):
    GPIO.output(pin, GPIO.HIGH)

def off(pin):
    GPIO.output(pin, GPIO.LOW)

def get_btc_price():
    r = requests.get('https://min-api.cryptocompare.com/data/price?fsym=BTC&tsyms=USD')
    return r.json()['USD']

def get_btc_balance(wallet_address, api_key):
    url = f'https://www.blockonomics.co/api/balance?addr={wallet_address}'
    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    r = requests.get(url, headers=headers)
    print(r.text)
    satoshi_balance = r.json()['response'][0]['confirmed']
    return satoshi_balance / 100000000

def send_btc_balance(bot, chat_id, wallet_address, api_key):
    btc_balance = get_btc_balance(wallet_address, api_key)
    btc_price = get_btc_price()  # Gets the current BTC price in USD
    usd_value = btc_balance * btc_price
    formatted_usd = f"{usd_value:,.0f}".replace(",", " ")
    message = f"The balance of the wallet is {btc_balance:0.8f} BTC / {formatted_usd} USD"
    bot.send_message(chat_id=chat_id, text=message)

def check_wallet_balance(wallet_address2, api_key):
    url = f'https://www.blockonomics.co/api/balance?addr={wallet_address2}'
    headers = {'Authorization': f'Bearer {api_key}'}
    r = requests.get(url, headers=headers)
    if r.status_code != 200:
        return f"Error: {r.text}"
    data = r.json()['response'][0]['confirmed']
    btc_balance = data / 100000000
    btc_price = get_btc_price()  # Get current BTC price in USD
    usd_value = btc_balance * btc_price
    formatted_usd = f"{usd_value:,.0f}".replace(",", " ")
    return f"The balance of the wallet is {btc_balance:0.8f} BTC / {formatted_usd} USD"

def blink_led():
    global flag3
    flag3 = True
    while flag3:
        GPIO.output(11, GPIO.HIGH)
        time.sleep(0.5)
        GPIO.output(11, GPIO.LOW)
        time.sleep(0.5)

def read_chat_ids():
    with open('/home/pi/chat_ids.txt', 'r') as f:
        return [int(line.strip()) for line in f]

def make_seed_wallet():
    mnemo = Mnemonic("english")
    mnemonic_phrase = mnemo.generate(strength=256)
    seed = mnemo.to_seed(mnemonic_phrase, passphrase="")
    root_key = bip32utils.BIP32Key.fromEntropy(seed)
    child_key = root_key.ChildKey(0)
    child_private_wif = child_key.WalletImportFormat()
    child_public_hex = child_key.PublicKey().hex()
    typical_address = bitcoin.pubkey_to_address(child_public_hex)
    output = (
        f"Seed Phrase:\n{mnemonic_phrase}\n\n"
        f"Private Key:\n{child_private_wif}\n\n"
        f"Public Address:\n{typical_address}"
    )
    return output

def update_botdata_wallet(new_wallet_address):
    file_path = "/home/pi/botdata.txt"
    try:
        with open(file_path, "r") as f:
            lines = f.readlines()
        if len(lines) >= 3:
            # Update the third line (index 2) with the new wallet address
            lines[2] = new_wallet_address + "\n"
            with open(file_path, "w") as f:
                f.writelines(lines)
    except Exception as e:
        print(f"Error updating botdata.txt: {e}")

def check_private_key(check_address2):
    try:
        address_info = bitcoin.rpc.call('validateaddress', [check_address2])
        if address_info['isvalid']:
            return f'{check_address2} is a valid bitcoin address'
        else:
            return f'{check_address2} is not a valid bitcoin address'
    except:
        return f'An error occurred while checking {check_address2} (Bitcoin Core may not be running)'

def update_botdata_wallet(new_wallet_address):
    file_path = "/home/pi/botdata.txt"
    try:
        with open(file_path, "r") as f:
            lines = f.readlines()
        if len(lines) >= 3:
            # Update the third line (index 2) with the new wallet address
            lines[2] = new_wallet_address + "\n"
            with open(file_path, "w") as f:
                f.writelines(lines)
    except Exception as e:
        print(f"Error updating botdata.txt: {e}")

def backup_and_notify(context, chat_id):
    usb_device = "/dev/sdb2"     # Device to check for
    mount_point = "/mnt/usb"     # Mount point for backup

    if not os.path.exists(usb_device):
        context.bot.send_message(chat_id, "USB drive not detected. Please plug in your USB HD.")
        return

    os.makedirs(mount_point, exist_ok=True)
    mount_check = subprocess.run(["mountpoint", "-q", mount_point])
    if mount_check.returncode != 0:
        mount_result = subprocess.run(["sudo", "mount", usb_device, mount_point],
                                      capture_output=True, text=True)
        if mount_result.returncode != 0:
            context.bot.send_message(chat_id, "Failed to mount USB drive: " + mount_result.stderr)
            return

    proc_bitcoin_size = subprocess.run("du -sh /mnt/hdd/.bitcoin",
                                         shell=True, capture_output=True, text=True)
    bitcoin_size = proc_bitcoin_size.stdout.strip()

    proc_usb_space = subprocess.run(f"df -h {mount_point}",
                                      shell=True, capture_output=True, text=True)
    usb_space = proc_usb_space.stdout.strip()

    context.bot.send_message(chat_id,
                             text=f"Starting backup...\nBitcoin directory size: {bitcoin_size}\nUSB free space:\n{usb_space}")

    subprocess.run("sudo systemctl stop bitcoind.service", shell=True)
    context.bot.send_message(chat_id, text="bitcoind stopped, starting backup process...")

    backup_cmd = f"rsync -av --progress /mnt/hdd/.bitcoin {mount_point}/.bitcoin"
    rsync_proc = subprocess.run(backup_cmd, shell=True, capture_output=True, text=True)
    if rsync_proc.returncode != 0:
        context.bot.send_message(chat_id, text="Backup failed: " + rsync_proc.stderr)
        subprocess.run("sudo systemctl start bitcoind.service", shell=True)
        return
    else:
        context.bot.send_message(chat_id, text="Backup finished successfully!")

    subprocess.run("sudo systemctl start bitcoind.service", shell=True)
    context.bot.send_message(chat_id, text="bitcoind restarted.")

    unmount_proc = subprocess.run(["sudo", "umount", mount_point],
                                    capture_output=True, text=True)
    if unmount_proc.returncode != 0:
        context.bot.send_message(chat_id,
                                 text="Warning: USB drive could not be unmounted: " + unmount_proc.stderr)
    else:
        context.bot.send_message(chat_id, text="USB drive unmounted successfully.")

    eject_proc = subprocess.run(["sudo", "eject", usb_device],
                                  capture_output=True, text=True)
    if eject_proc.returncode != 0:
        context.bot.send_message(chat_id,
                                 text="Warning: USB drive could not be ejected: " + eject_proc.stderr)
    else:
        context.bot.send_message(chat_id,
                                 text="USB drive ejected successfully. Please unplug the USB drive now.")

def message_received(update, context):
    chat_id = update.message.chat_id
    allowed_chat_ids = read_chat_ids()
    if chat_id not in allowed_chat_ids:
        context.bot.send_message(chat_id=chat_id, text='Unauthorized Access')
        return

    command = update.message.text
    print('Got command: %s' % command)
    global flag1, flag2, flag3, flag4, flag5, flag6, flag7, wallet_address

    if command == '/walletcheck':
        flag4 = True
        context.bot.send_message(chat_id, 'Enter a bitcoin wallet address')

    elif flag4:
        wallet_address2 = command
        balance = check_wallet_balance(wallet_address2, api_key)
        context.bot.send_message(chat_id, balance)
        flag4 = False

    elif command == '/tailstop':
        try:
            result = subprocess.run(['sudo', 'systemctl', 'stop', 'tailscaled'],
                                    capture_output=True, text=True)
            if result.returncode == 0:
                context.bot.send_message(chat_id, 'Tailscaled service stopped successfully.')
            else:
                context.bot.send_message(chat_id, f'Failed to stop Tailscaled service: {result.stderr}')
        except Exception as e:
            context.bot.send_message(chat_id, f'Error stopping Tailscaled service: {str(e)}')

    elif command == '/wallet':
        send_btc_balance(bot, chat_id, wallet_address, api_key)

    elif command == '/chainstate':
        try:
            run = subprocess.run(["sudo", "bitcoin-cli", "getblockchaininfo"],
                                  capture_output=True, text=True)
            if run.returncode != 0:
                context.bot.send_message(chat_id, f"Error: {run.stderr}")
            else:
                blockchain_info = json.loads(run.stdout)
                size_on_disk = blockchain_info.get("size_on_disk")
                verification_progress = blockchain_info.get("verificationprogress")
                if size_on_disk is None or verification_progress is None or verification_progress == 0:
                    context.bot.send_message(chat_id, "Blockchain size or progress information not available.")
                else:
                    # Calculate sizes in gigabytes
                    current_size_gb = size_on_disk / (1024 ** 3)
                    estimated_total = size_on_disk / verification_progress
                    estimated_total_gb = estimated_total / (1024 ** 3)
                    progress_percentage = verification_progress * 100
                    estimated_remaining = estimated_total_gb - current_size_gb

                    # Get the total disk size on the partition containing the blockchain.
                    # Using 'df --output=size' returns the total size in 1K blocks.
                    df_total_proc = subprocess.run(["df", "--output=size", "/mnt/hdd"],
                                                   capture_output=True, text=True)
                    lines_total = df_total_proc.stdout.strip().splitlines()
                    if len(lines_total) >= 2:
                        # Convert from 1K blocks to bytes, then to GB
                        total_blocks = int(lines_total[1].strip())
                        total_space_bytes = total_blocks * 1024
                        total_space_gb = total_space_bytes / (1024 ** 3)
                    else:
                        total_space_gb = 0

                    # Calculate estimated remaining free disk space after blockchain download.
                    estimated_memory_remaining = total_space_gb - estimated_total_gb

                    message = (
                        f"Verification Progress: {progress_percentage:.2f}%\n"
                        f"Current downloaded blockchain: {current_size_gb:.2f} GB\n"
                        f"Estimated Total Blockchain Size: {estimated_total_gb:.2f} GB\n"
                        f"Estimated Remaining to Download: {estimated_remaining:.2f} GB\n"
                        f"Estimated Memory Remaining Free: {estimated_memory_remaining:.2f} GB"
                    )
                    context.bot.send_message(chat_id, message)
        except Exception as e:
            context.bot.send_message(chat_id, f"Error: {e}")

    elif command == '/cpu':
        usage_proc = subprocess.run(
            ["""vmstat 1 2 | tail -1 | awk '{print $13}' | tr -d '\n'"""],
            shell=True, capture_output=True, text=True)
        cpu_usage = usage_proc.stdout.strip()
        clock_proc = subprocess.run(
            ["""vcgencmd measure_clock arm | awk 'BEGIN { FS="=" } { print $2 / 1000000000 }'"""],
            shell=True, capture_output=True, text=True)
        try:
            cpu_clock = float(clock_proc.stdout.strip())
        except ValueError:
            cpu_clock = 0.0
        message = f"CPU: {cpu_usage}% {cpu_clock:.1f} GHz"
        context.bot.send_message(chat_id, text=message)

    elif command == '/chatid':
        context.bot.send_message(chat_id, text=f"Your chat ID is: {chat_id}")

    elif command == '/checkadd':
        flag5 = True
        context.bot.send_message(chat_id, 'Enter the Bitcoin address to check')

    elif flag5:
        check_address2 = command
        check = check_private_key(check_address2)
        context.bot.send_message(chat_id, check)
        flag5 = False

    elif command == '/btc':
        btc_price = get_btc_price()
        context.bot.send_message(chat_id, f'The current price of BTC in USD is: ${btc_price:.0f} USD')

    elif command == '/mywallet':
        context.bot.send_message(chat_id, f'The public address of your wallet is: {wallet_address}')

    elif command == '/ping':
        flag1 = True
        context.bot.send_message(chat_id, 'Which IP do you want to ping?')

    elif flag1:
        ip = command
        run = subprocess.run(['ping', '-c', '3', ip],
                             capture_output=True)
        context.bot.send_message(chat_id, run.stdout.decode())
        flag1 = False

    elif command == '/sudo':
        flag2 = True
        context.bot.send_message(chat_id, 'Type your cmd')

    elif flag2:
        sudo2 = command.split()
        run = subprocess.run(['sudo'] + sudo2,
                             capture_output=True)
        context.bot.send_message(chat_id, run.stdout.decode())
        flag2 = False

    elif command == '/ledon':
        GPIO.output(11, GPIO.HIGH)
        context.bot.send_message(chat_id, 'LED turned on')

    elif command == '/ledoff':
        GPIO.output(11, GPIO.LOW)
        context.bot.send_message(chat_id, 'LED turned off')

    elif command == '/blinkon':
        thread = threading.Thread(target=blink_led)
        thread.start()
        context.bot.send_message(chat_id, 'LED blinking started')

    elif command == '/blinkoff':
        flag3 = False
        GPIO.output(11, GPIO.LOW)
        context.bot.send_message(chat_id, 'LED stopped blinking')

    elif command == '/fanon':
        on(12)
        context.bot.send_message(chat_id, 'FAN turned on')

    elif command == '/fanoff':
        off(12)
        context.bot.send_message(chat_id, 'FAN turned off')

    elif command == '/net':
        run_eth0 = subprocess.run(
            ["ip link show eth0 | awk '/ether/ {print $2}'"],
            shell=True, capture_output=True, text=True)
        run_wlan0 = subprocess.run(
            ["ip link show wlan0 | awk '/ether/ {print $2}'"],
            shell=True, capture_output=True, text=True)
        mac_eth0 = run_eth0.stdout.strip()
        mac_wlan0 = run_wlan0.stdout.strip()
        message = f"Mac Eth0: {mac_eth0}\nMac Wlan0: {mac_wlan0}"
        context.bot.send_message(chat_id, text=message)

    elif command == '/ip':
        run_public = subprocess.run(['curl ifconfig.co'],
                                      shell=True, capture_output=True, text=True)
        public_ip = run_public.stdout.strip()
        run_local = subprocess.run(['hostname -I'],
                                     shell=True, capture_output=True, text=True)
        local_ips = run_local.stdout.strip().split()
        if local_ips:
            local_ip = local_ips[0]
            tail_ip = local_ips[-1]
        else:
            local_ip = "N/A"
            tail_ip = "N/A"
        message = f"Public IP: {public_ip}\nLocal IP: {local_ip}\nTail IP: {tail_ip}"
        context.bot.send_message(chat_id, text=message)

    elif command == '/storage':
        run_sd = subprocess.run(
            ["df -h / | tail -1 | awk '{print $3 \" (\" $5 \")\"}'"],
            shell=True, capture_output=True, text=True)
        sd_usage = run_sd.stdout.strip()
        run_hdex = subprocess.run(
            ["df -h | grep '/dev/sd' | awk '{print $3 \" (\" $5 \")\"}'"],
            shell=True, capture_output=True, text=True)
        hdex_usage = run_hdex.stdout.strip()
        message = f"SD Used: {sd_usage}\nExternal HD Used: {hdex_usage}"
        context.bot.send_message(chat_id, text=message)

    elif command == '/htop':
        run = subprocess.run(['ps -e --sort -%mem | head -10'],
                             shell=True, capture_output=True)
        context.bot.send_message(chat_id, text='Processes Running: ' + run.stdout.decode('utf-8'))

    elif command == '/device':
        model_proc = subprocess.run(['cat', '/proc/device-tree/model'],
                                    capture_output=True, text=True)
        model = model_proc.stdout.strip()
        user_proc = subprocess.run(['whoami'],
                                   capture_output=True, text=True)
        user = user_proc.stdout.strip()
        uptime_proc = subprocess.run(['uptime', '-p'],
                                     capture_output=True, text=True)
        uptime_str = uptime_proc.stdout.strip()
        if uptime_str.lower().startswith("up "):
            uptime_str = uptime_str[3:]
        location_proc = subprocess.run(
            ["curl -s https://extreme-ip-lookup.com/json/?key=ACJdcEKqljZrmlXp1GZA | jq -r '.country' | tr '[:lower:]' '[:upper:]'"],
            shell=True, capture_output=True, text=True)
        location = location_proc.stdout.strip()
        time_proc = subprocess.run(['date'],
                                   capture_output=True, text=True)
        time_date = time_proc.stdout.strip()
        volts_proc = subprocess.run(
            ["vcgencmd measure_volts $id | awk '{print substr($0, 6, length($0)-9) \" V\"}'"],
            shell=True, capture_output=True, text=True)
        volts_used = volts_proc.stdout.strip()
        temp_proc = subprocess.run(['vcgencmd', 'measure_temp'],
                                   capture_output=True, text=True)
        raw_temp = temp_proc.stdout.strip()
        if raw_temp.startswith("temp=") and raw_temp.endswith("'C"):
            cpu_temp = raw_temp[len("temp="):-2]
        else:
            cpu_temp = "N/A"
        message = (
            f"{model}\n"
            f"User: {user}\n"
            f"Uptime: {uptime_str}\n"
            f"Location: {location}\n"
            f"Time/Date: {time_date}\n"
            f"Volts Used: {volts_used}\n"
            f"CPU temp: {cpu_temp} C"
        )
        context.bot.send_message(chat_id, text=message)

    elif command == '/backup':
        backup_and_notify(context, chat_id)

    elif command == '/chkinterval':
        service_file = '/etc/systemd/system/wallet.service'
        try:
            with open(service_file, 'r') as f:
                content = f.read()
            m = re.search(r'RestartSec=(\d+)', content)
            if m:
                current_sec = int(m.group(1))
                hours = current_sec // 3600
                minutes = (current_sec % 3600) // 60
                seconds = current_sec % 60
                current_interval = f"{hours:02}:{minutes:02}:{seconds:02}"
            else:
                current_interval = "Unknown"
        except Exception as e:
            current_interval = f"Error reading service file: {str(e)}"
        context.bot.send_message(chat_id,
                                 text=f"Current interval is {current_interval}.\nEnter new interval in hh:mm:ss format:")
        flag7 = True

    elif flag7:
        new_interval = command.strip()
        try:
            time_parts = new_interval.split(':')
            if len(time_parts) != 3:
                raise ValueError("Invalid format. Use hh:mm:ss")
            hours, minutes, seconds = map(int, time_parts)
            new_seconds = hours * 3600 + minutes * 60 + seconds
            service_file = '/etc/systemd/system/wallet.service'
            with open(service_file, 'r') as f:
                lines = f.readlines()
            for i, line in enumerate(lines):
                if line.startswith("RestartSec="):
                    lines[i] = f"RestartSec={new_seconds}\n"
            with open(service_file, 'w') as f:
                f.writelines(lines)
            os.system("sudo systemctl daemon-reload")
            os.system("sudo systemctl restart wallet.service")
            context.bot.send_message(chat_id, f"Wallet service interval updated to {new_interval}.")
        except Exception as e:
            context.bot.send_message(chat_id, f"Error updating interval: {str(e)}")
        flag7 = False

    elif command == '/guide':
        guide_text = (
            "/help: Shows you all the commands available\n"
            "/reboot: Reboots the device\n"
            "/shutdown: Shuts down the device\n"
            "/startminer: Starts the BTC miner\n"
            "/stopminer: Stops the BTC miner\n"
            "/stopbtc: Stops Bitcoind\n"
            "/startbtc: Start Bitcoind\n"
            "/tailstop: Stops Tailscale\n"
            "/sync: Shows Blockchain Sync state in (% and size)\n"
            "/chainstate: Shows Chainstate\n"
            "/btc: Shows the current price of BTC in USD\n"
            "/backup: Tool to backup Blockchain\n"
            "/wallet: Shows the current balance of your BTC wallet in (BTC and USD)\n"
            "/mywallet: Shows the current wallet public address\n"
            "/changeadd: Change wallet your address\n"
            "/walletcheck: Checks the wallet balance in (BTC and USD) of your choice\n"
            "/checkadd: Checks Validity of BTC Address\n"
            "/chkinterval: Updates interval between wallet check\n"
            "/makewallet: Generates HD seed phrase & addresses\n"
            "/chatid: Your Telegram Chatid\n"
            "/fanon: Turns the fan on\n"
            "/fanoff: Turns the fan off\n"
            "/ledon: Turns LED on\n"
            "/ledoff: Turns LED off\n"
            "/blinkon: Turns LED on Blinking mode\n"
            "/blinkoff: Turns LED off Blinking mode\n"
            "/device: Shows Device Information\n"
            "/cpu: Shows CPU usage & clock speed\n"
            "/storage: Shows used space (GB and %)\n"
            "/htop: Runs htop limited to top processes\n"
            "/net: Shows Network Information\n"
            "/ip: Shows Public, Local, and Tail IP addresses\n"
            "/ping: Prompts for ping IP or Domain & gives you results\n"
            "/sudo: Prompts for sudo cmd and then executes it\n"
        )
        context.bot.send_message(chat_id, text=guide_text)

    elif command == '/help':
        help_text = (
            "/help /guide /reboot /shutdown /startminer /stopminer /stopbtc /startbtc /tailstop /sync /chainstate /btc /backup /wallet "
            "/mywallet /changeadd /walletcheck /checkadd /chkinterval /makewallet /fanon /fanoff /ledon /ledoff "
            "/blinkon /blinkoff /device /cpu /storage /htop /net /ip /ping /sudo"
        )
        context.bot.send_message(chat_id, text=help_text)

    elif command == '/reboot':
        context.bot.send_message(chat_id, 'Rebooting Now !')
        os.system('sudo reboot')

    elif command == '/shutdown':
        context.bot.send_message(chat_id, 'Shutting Down Now !')
        os.system('sudo shutdown')

    elif command == '/startminer':
        context.bot.send_message(chat_id, 'Miner Started !')
        os.system('sudo systemctl start bfgminer.service')

    elif command == '/stopminer':
        context.bot.send_message(chat_id, 'Miner Stopped !')
        os.system('sudo systemctl stop bfgminer.service')

    elif command == '/stopbtc':
        os.system('sudo systemctl stop bitcoind.service')
        context.bot.send_message(chat_id, 'bitcoind service stopped')

    elif command == '/startbtc':
        os.system('sudo systemctl start bitcoind.service')
        context.bot.send_message(chat_id, 'bitcoind service started')

    elif command == '/changeadd':
        flag6 = True
        context.bot.send_message(chat_id, 'Enter the new Bitcoin wallet address')

    elif flag6:
        wallet_address = command.strip()
        update_botdata_wallet(wallet_address)  # Update botdata.txt here
        context.bot.send_message(chat_id, f"Wallet address updated to: {wallet_address}")
        flag6 = False

    elif command == '/makewallet':
        seed_wallet_info = make_seed_wallet()
        context.bot.send_message(chat_id, seed_wallet_info)

    elif command == '/sync':
        try:
            run = subprocess.run(["sudo", "bitcoin-cli", "getblockchaininfo"],
                                 capture_output=True, text=True)
            if run.returncode != 0:
                print(f"Error: {run.stderr}")
                context.bot.send_message(chat_id, f"Error: {run.stderr}")
            else:
                blockchain_info = json.loads(run.stdout)
                verification_progress = float(blockchain_info["verificationprogress"])
                formatted_output = f"{verification_progress * 100:.2f}"
                context.bot.send_message(chat_id, f"Sync progress: {formatted_output}%")
        except Exception as e:
            print(f"An error occurred: {e}")
            context.bot.send_message(chat_id, f"An error occurred: {e}")

    else:
        context.bot.send_message(chat_id, 'Try /help')

# Initialize the updater and dispatcher outside the message handler
updater = Updater(token=TOKEN, use_context=True)
dispatcher = updater.dispatcher
dispatcher.add_handler(MessageHandler(Filters.text, message_received))

updater.start_polling()
updater.idle()
