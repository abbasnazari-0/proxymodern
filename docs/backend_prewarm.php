<?php
/**
 * Backend-side Shifter sticky-session pre-warm.
 *
 * The Flutter app intentionally does NOT pre-warm the proxy. Before the backend
 * returns the ad config, it must warm the freshly generated sticky session by
 * opening a CONNECT tunnel through the relay to Google's ad host. Only a
 * session that answered "200 Connection Established" is handed to the app, so
 * the app's first real ad load is already on a warm exit IP.
 */

function relay_prewarm_session(
    string $baseUsername,
    string $password,
    string $relayHost,
    int $relayPort,
    string $target = 'googleads.g.doubleclick.net:443',
    int $ttlSeconds = 3600,
    int $maxTries = 3
): ?string {
    for ($try = 0; $try < $maxTries; $try++) {
        $sessionId = 'stk' . intval(microtime(true) * 1000000);
        $username  = $baseUsername . '-sid-' . $sessionId . '-ttl-' . $ttlSeconds;

        $sock = @fsockopen($relayHost, $relayPort, $errno, $errstr, 8.0);
        if ($sock === false) {
            continue; // relay unreachable — try a fresh session
        }

        stream_set_timeout($sock, 8);
        $auth = base64_encode($username . ':' . $password);
        $req  = "CONNECT {$target} HTTP/1.1\r\n"
              . "Host: {$target}\r\n"
              . "Proxy-Authorization: Basic {$auth}\r\n"
              . "\r\n";
        fwrite($sock, $req);

        $response = '';
        while (!feof($sock) && strpos($response, "\r\n\r\n") === false) {
            $chunk = fread($sock, 4096);
            if ($chunk === false || $chunk === '') {
                break;
            }
            $response .= $chunk;
        }
        fclose($sock);

        if (strpos($response, ' 200 ') !== false) {
            return $sessionId; // warm — safe to give to the client
        }
    }
    return null; // could not warm any session
}

// ---- Example integration in your index.php ad-config section ----
/*
$proxyUsername = 'customer-abbasnazariaf-country-US'; // base (no -sid-)
$proxyPassword = 'kqksGNx';
$relayHost = '91.107.160.4';
$relayPort = 8081;

$sessionId = relay_prewarm_session($proxyUsername, $proxyPassword, $relayHost, $relayPort);

if ($sessionId !== null) {
    $config['proxy_mode'] = 'sticky';
    $config['proxy_session_id'] = $sessionId;
} else {
    // Fall back to rotation (no sticky session) if no session could be warmed.
    $config['proxy_mode'] = 'rotation';
    $config['proxy_session_id'] = null;
}
$config['proxy_ttl_seconds'] = 3600;
*/
