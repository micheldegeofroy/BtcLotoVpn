<link rel="shortcut icon" type="image/x-icon" href="favicon.ico">
<title>Lotominer</title>

<?php
// Set the page refresh header before any output.
$page = $_SERVER['PHP_SELF'];
$sec = 60;
header("Refresh: $sec; url=$page");

// Execute the startup script.
shell_exec("sudo root.sh");

// Define Bitcoin CLI path and users.
$bitcoinCli = "/usr/local/bin/bitcoin-cli";
$userPi = "pi";
$userBitcoin = "bitcoin";
$datadir = '/mnt/hdd/.bitcoin';
$cookieFile = $datadir . '/.cookie';

// Retrieve Bitcoin data.
$ver = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getnetworkinfo 2> /dev/null | jq -r '.subversion'"));
$chainRaw = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getblockchaininfo 2> /dev/null | jq -r '.chain'"));
$chainLabel = "Bitcoin Core ";
$netLabel = "Net ";
$chainVersion = ucfirst(trim($chainRaw));
$verClean = str_replace(str_split('/:Satoshi'), '', $ver);
$chain = $chainLabel . $chainVersion . $netLabel . "V" . $verClean;

// Retrieve other Bitcoin CLI data.
$diff = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getblockchaininfo 2>&1 | jq -r '.difficulty'"));
$mempool = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getmempoolinfo 2>&1 | jq -r '.size'"));
$btcblock = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getblockchaininfo 2>&1 | jq -r '.blocks'"));
$btcpeers = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getpeerinfo 2>&1 | jq 'length'"));
// Updated $btcsync: Multiply verificationprogress by 100 and format to 2 decimal places.
$btcsync = trim(shell_exec("sudo $bitcoinCli -datadir={$datadir} -rpccookiefile={$cookieFile} getblockchaininfo 2>&1 | jq -r '.verificationprogress' | awk '{printf \"%.2f\", 100*$1}'"));

// Retrieve system information.
$exstoragepercentused = trim(shell_exec("df -h | grep '/dev/sd' | awk '{print($5)}'"));
$exstoragefree = trim(shell_exec("df -h | grep '/dev/sd' | awk '{print($4)}'"));
$exstoragesize = trim(shell_exec("df -h | grep '/dev/sd' | awk '{print($2)}'"));
$exstorageused = trim(shell_exec("df -h | grep '/dev/sd' | awk '{print($3)}'"));
$ip = trim(shell_exec("hostname -I"));
$temp = round((float) shell_exec('cat /sys/class/thermal/thermal_zone*/temp') / 1000, 1);
$geoloc = trim(shell_exec("curl -s 'https://extreme-ip-lookup.com/json/?key=ACJdcEKqljZrmlXp1GZA' | jq -r '.country' | tr '[:lower:]' '[:upper:]'"));
$localtimeRaw = trim(shell_exec("uptime | awk '{print($1)}'"));
// Split the time using ':' to extract hour and minute.
$timeParts = explode(":", $localtimeRaw);
if (count($timeParts) >= 2) {
    $localtime = $timeParts[0] . ":" . $timeParts[1];
} else {
    $localtime = $localtimeRaw;
}
$users = trim(shell_exec("uptime | awk '{print substr($5, 1, length($2)-1)}'"));
$pubip = trim(shell_exec('curl -s ifconfig.co'));
$HW = trim(shell_exec('cat /proc/device-tree/model'));
$cpupercent = trim(shell_exec("vmstat 1 2 | tail -1 | awk '{print $15}'"));
$uptimeRaw = trim(shell_exec("uptime -p"));
$uptime = rtrim(str_replace(str_split('upoteu,'), '', $uptimeRaw));

// Retrieve memory statistics using popen.
$raw = [];
$handle = popen('free -mt 2>&1', 'r');
while (!feof($handle)) {
    $raw[] = fgets($handle);
}
pclose($handle);
$trmem = $tumem = $tfmem = "";
foreach ($raw as $line) {
    if (strpos($line, "Mem:") !== false) {
        list($junk, $trmem, $tumem, $tfmem) = preg_split('/\s+/', trim($line));
    }
}

// --- Replace Bitcoin CLI getbalance with Blockonomics API call ---
// Read wallet address (3rd line) and Blockonomics API key (4th line) from botdata.txt
$botdata = file('/home/pi/botdata.txt', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
$wallet_address = isset($botdata[2]) ? trim($botdata[2]) : '';
$blockonomics_api_key = isset($botdata[3]) ? trim($botdata[3]) : '';

$balance_text = "N/A";
if (!empty($wallet_address) && !empty($blockonomics_api_key)) {
    // Build the Blockonomics API URL.
    $blockonomics_url = "https://www.blockonomics.co/api/balance?addr=" . $wallet_address;

    // Prepare the HTTP context with the API key in the header.
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'header' => "Authorization: Bearer " . $blockonomics_api_key . "\r\n"
        ]
    ]);

    // Get the API response.
    $response = file_get_contents($blockonomics_url, false, $context);
    if ($response === false) {
        $balance_text = "Error: Unable to retrieve balance.";
    } else {
        $json = json_decode($response, true);
        if (isset($json['response'][0]['confirmed'])) {
            $confirmed = $json['response'][0]['confirmed'];
            // Convert satoshi to BTC
            $btc_balance = $confirmed / 100000000;
            // Retrieve current BTC price (implement get_btc_price() or use a hardcoded value)
            function get_btc_price() {
                // Example: hardcode a BTC price or implement API call logic here.
                return 30000; // Replace with current BTC price in USD.
            }
            $btc_price = get_btc_price();
            $usd_value = $btc_balance * $btc_price;
            $formatted_usd = number_format($usd_value, 0, '', ' ');
            $balance_text = number_format($btc_balance, 1) . " BTC / " . $formatted_usd . " USD";
        } else {
            $balance_text = "Error: Invalid API response.";
        }
    }
} else {
    $balance_text = "Error: Wallet address or API key not set.";
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>System Dashboard</title>
    <!-- Meta refresh as a fallback -->
    <meta http-equiv="refresh" content="<?php echo $sec; ?>;url=<?php echo $page; ?>">
    <style>
        body {
            background-color: black;
            color: green;
            font-family: "Times New Roman", Times, serif;
            font-size: 12px;
        }
        a {
            color: green;
            font-family: "Times New Roman", Times, serif;
            font-size: 12px;
            font-weight: normal;
            text-decoration: none;
        }
        pre {
            margin: 0;
            line-height: 1.2;
        }
    </style>
</head>
<body>
<!-- Display the ASCII art header -->
<pre>
               ___ ___________
              / _ )_  __/ ___/
             / _  |/ / / /__
            /____//_/  \___/_____
           / /  / __ \/_  __/ __ \
          / /__/ /_/ / / / / /_/ /
         /____/\____/_/_/  \____/
        / _ \/ _ \/  _/
       / , _/ ___// /
      /_/|_/_/  /___/
</pre>
<ul>
<pre>
<?php
echo $HW . "\n\n";
echo "Local Time:   " . $localtime . "\n";
echo "Geo Location: " . (!empty($geoloc) ? $geoloc : "N/A") . "\n";
echo "Public IP:    " . $pubip . "\n";
echo "Local IP:     " . $ip . "\n";
echo "CPU % Load:   " . $cpupercent . " %\n";
echo "Uptime:      " . $uptime . "\n";
echo "Temp:         " . $temp . " °C\n";
echo "Ex HD % Used: " . (!empty($exstoragepercentused) ? $exstoragepercentused : "N/A") . "\n";
echo "Ex HD Free:   " . (!empty($exstoragefree) ? $exstoragefree : "N/A") . "\n";
echo "Ex HD Used:   " . (!empty($exstorageused) ? $exstorageused : "N/A") . "\n";
echo "Ex HD Total:  " . (!empty($exstoragesize) ? $exstoragesize : "N/A") . "\n";
echo "Free Mem:     " . (!empty($tfmem) ? $tfmem . "MB" : "N/A") . "\n";
echo "Used Mem:     " . (!empty($tumem) ? $tumem . "MB" : "N/A") . "\n";
echo "Total Mem:    " . (!empty($trmem) ? $trmem . "MB" : "N/A") . "\n\n";
echo $chain . "\n\n";
echo "BTC Peers:    " . (!empty($btcpeers) ? $btcpeers : "N/A") . "\n";
echo "BTC Block:    " . (!empty($btcblock) ? $btcblock : "N/A") . "\n";
echo "BTC Diff:     " . (!empty($diff) ? $diff : "N/A") . "\n";
echo "BTC Mempool:  " . (!empty($mempool) ? $mempool : "N/A") . "\n";
echo "BTC Balance:  " . $balance_text . "\n";
echo "BTC Sync:     " . (!empty($btcsync) ? $btcsync . "%" : "N/A") . "\n";
?>
</pre>
<br>
<a href="http://<?php echo $_SERVER['SERVER_ADDR']; ?>/miner.php">MINER STATS</a>
</ul>
</body>
</html>
